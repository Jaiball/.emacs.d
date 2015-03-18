(defun wikipedia-search (search-term)
  “Search for SEARCH-TERM on wikipedia”
   (interactive
    (let ((term (if mark-active
                    (buffer-substring (region-beginning) (region-end))
                  (word-at-point))))
      (list
       (read-string
        (format “Wikipedia (%s):” term) nil nil term)))
    )
   (browse-url
    (concat
     “http://en.m.wikipedia.org/w/index.php?search=”
      search-term
      ))
   )

(defun w3m-open-site (site)
  “Opens site in new w3m session with ‘http://’ appended”

   (interactive
    (list (read-string “Enter website address(default: w3m-home):” nil nil w3m-home-page nil )))
   (w3m-goto-url-new-session
    (concat “http://” site)))

(defun hn ()
  (interactive)
  (browse-url “http://news.ycombinator.com”))

(defun my-setup-php ()
  ;; enable web mode
  (web-mode)

  ;; make these variables local
  (make-local-variable 'web-mode-code-indent-offset)
  (make-local-variable 'web-mode-markup-indent-offset)
  (make-local-variable 'web-mode-css-indent-offset)

  ;; set indentation, can set different indentation level for different code type
  (setq web-mode-code-indent-offset 4)
  (setq web-mode-css-indent-offset 2)
  (setq web-mode-markup-indent-offset 2))


(setq w5m-default-display-inline-images t)
