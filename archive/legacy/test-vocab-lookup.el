;;; test-vocab-lookup.el --- Debug vocabulary lookup

(defun test-lookup ()
  "Test vocabulary lookup for specific words."
  (interactive)
  (let ((test-words '("གནས" "ལུགས" "གནས་ལུགས" "ཕྱིར" "ཕྱིར།")))
    (with-output-to-temp-buffer "*Vocab Test*"
      (princ "=== VOCABULARY LOOKUP TEST ===\n\n")
      (princ (format "Hash table has %d entries\n\n"
                    (hash-table-count tibetan-comprehensive-vocabulary)))
      (dolist (word test-words)
        (let ((result (gethash word tibetan-comprehensive-vocabulary)))
          (princ (format "%-15s => %s\n" word (or result "[NOT FOUND]"))))))))

(test-lookup)
