;;; squiggly-clojure.el --- Flycheck: Clojure support    -*- lexical-binding: t; -*-

;; Copyright © 2014 Peter Fraenkel
;; Copyright (C) 2014 Sebastian Wiesner <swiesner@lunaryorn.com>
;;
;; Author: Peter Fraenkel <pnf@podsnap.com>
;;     Sebastian Wiesner <swiesner@lunaryorn.com>
;; Maintainer: Peter Fraenkel <pnf@podsnap.com>
;; URL: https://github.com/clojure-emacs/squiggly-clojure
;; Version: 1.1.0
;; Package-Requires: ((cider "0.8.1") (flycheck "0.22-cvs1") (let-alist "1.0.1") (emacs "24"))

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Add Clojure support to Flycheck.
;;
;; Provide syntax checkers to check Clojure code using a running Cider repl.
;;
;; Installation:
;;
;; (eval-after-load 'flycheck '(flycheck-clojure-setup))

;;; Code:

(require 'cider-client)
(require 'flycheck)
(require 'json)
(require 'url-parse)
(eval-when-compile (require 'let-alist))

;;;###autoload
(defun flycheck-clojure-parse-cider-errors (value checker)
  "Parse cider errors from JSON VALUE from CHECKER.

Return a list of parsed `flycheck-error' objects."
  ;; Parse the nested JSON from Cider.  The outer JSON contains the return value
  ;; from Cider, and the inner JSON the errors returned by the individual
  ;; checker.
  (let ((error-objects (json-read-from-string (json-read-from-string value))))
    (mapcar (lambda (o)
              (let-alist o
                ;; Use the file name reported by the syntax checker, but only if
                ;; its absolute, because typed reports relative file names that
                ;; are hard to expand correctly, since they are relative to the
                ;; source directory (not the project directory).
                (let* ((parsed-file (when .file
                                      (url-filename
                                       (url-generic-parse-url .file))))
                       (filename (if (and parsed-file
                                          (file-name-absolute-p parsed-file))
                                     parsed-file
                                   (buffer-file-name))))
                  (flycheck-error-new-at .line .column (intern .level) .msg
                                         :checker checker
                                         :filename filename))))
            error-objects)))

(defun flycheck-clojure-start-cider (checker callback)
  "Start a cider syntax CHECKER with CALLBACK."
  (let ((ns (clojure-find-ns))
        (form (get checker 'flycheck-clojure-form)))
    (cider-tooling-eval
     (funcall form ns)
     (nrepl-make-response-handler
      (current-buffer)
      (lambda (buffer value)
        (funcall callback 'finished
                 (with-current-buffer buffer
                   (flycheck-clojure-parse-cider-errors value checker))))
      nil                               ; stdout
      nil                               ; stderr
      (lambda (_)
        ;; If the evaluation completes without returning any value, there has
        ;; gone something wrong.  Ideally, we'd report *what* was wrong, but
        ;; `nrepl-make-response-handler' is close to useless for this :(,
        ;; because it just `message's for many status codes that are errors for
        ;; us :(
        (funcall callback 'errored "Done with no errors"))
      (lambda (_buffer ex _rootex _sess)
        (funcall callback 'errored
                 (format "Form %s of checker %s failed: %s"
                         form checker ex)))))))

(defun flycheck-clojure-may-use-cider-checker ()
  "Determine whether a cider checker may be used.

Checks for `cider-mode', and a current nREPL connection.

Standard predicate for cider checkers."
  (let ((connection-buffer (nrepl-current-connection-buffer)))
    (and (bound-and-true-p cider-mode)
         connection-buffer
         (buffer-live-p (get-buffer connection-buffer)))))

(defun flycheck-clojure-define-cider-checker (name docstring &rest properties)
  "Define a Cider syntax checker with NAME, DOCSTRING and PROPERTIES.

NAME, DOCSTRING, and PROPERTIES are like for
`flycheck-define-generic-checker', except that `:start' and
`:modes' are invalid PROPERTIES.  A syntax checker defined with
this function will always check in `clojure-mode', and only if
`cider-mode' is enabled.

Instead of `:start', this syntax checker requires a `:form
FUNCTION' property.  FUNCTION takes the current Clojure namespace
as single argument, and shall return a string containing a
Clojure form to be sent to Cider to check the current buffer."
  (declare (indent 1)
           (doc-string 2))
  (let* ((form (plist-get properties :form))
         (orig-predicate (plist-get properties :predicate)))

    (when (plist-get :start properties)
      (error "Checker %s may not have :start" name))
    (when (plist-get :modes properties)
      (error "Checker %s may not have :modes" name))
    (unless (functionp form)
      (error ":form %s of %s not a valid function" form name))
    (apply #'flycheck-define-generic-checker
           name docstring
           :start #'flycheck-clojure-start-cider
           :modes '(clojure-mode)
           :predicate (if orig-predicate
                          (lambda ()
                            (and (flycheck-clojure-may-use-cider-checker)
                                 (funcall orig-predicate)))
                        #'flycheck-clojure-may-use-cider-checker)
           properties)

    (put name 'flycheck-clojure-form form)))

(flycheck-clojure-define-cider-checker 'clojure-cider-eastwood
  "A syntax checker for Clojure, using Eastwood in Cider.

See URL `https://github.com/jonase/eastwood' and URL
`https://github.com/clojure-emacs/cider/' for more information."
  :form (lambda (ns)
          (format "(do (require 'squiggly-clojure.core) (squiggly-clojure.core/check-ew '%s))"
                  ns))
  :next-checkers '(clojure-cider-kibit clojure-cider-typed))

(flycheck-clojure-define-cider-checker 'clojure-cider-kibit
  "A syntax checker for Clojure, using Kibit in Cider.

See URL `https://github.com/jonase/kibit' and URL
`https://github.com/clojure-emacs/cider/' for more information."
  :form (lambda (ns)
          (format
           "(do (require 'squiggly-clojure.core) (squiggly-clojure.core/check-kb '%s %s))"
           ns
           ;; Escape file name for Clojure
           (flycheck-sexp-to-string (buffer-file-name))))
  :predicate (lambda () (buffer-file-name))
  :next-checkers '(clojure-cider-typed))

(flycheck-clojure-define-cider-checker 'clojure-cider-typed
  "A syntax checker for Clojure, using Typed Clojure in Cider.

See URL `https://github.com/clojure-emacs/cider/' for more
information."
  :form (lambda (ns)
          (format
           "(do (require 'squiggly-clojure.core) (squiggly-clojure.core/check-tc '%s))"
           ns)))

;;;###autoload
(defun flycheck-clojure-setup ()
  "Setup Flycheck for Clojure."
  (interactive)
  ;; Add checkers in reverse order, because `add-to-list' adds to front.
  (dolist (checker '(clojure-cider-typed
                     clojure-cider-kibit
                     clojure-cider-eastwood))
    (add-to-list 'flycheck-checkers checker)))

(provide 'squiggly-clojure)

;; Local Variables:
;; indent-tabs-mode: nil
;; End:

;;; squiggly-clojure.el ends here