;;; demo-vocabulary-improvement.el --- Demonstrate vocabulary coverage improvement

;; Load the Rangjung Yeshe integration
(defvar rangjung-yeshe-dictionary (make-hash-table :test 'equal :size 170000))
(defvar rangjung-yeshe-loaded nil)

(defun load-rangjung-yeshe-dictionary ()
  "Load the Rangjung Yeshe dictionary into memory."
  (unless rangjung-yeshe-loaded
    (let ((dict-file (expand-file-name
                      "~/buddhist-studies/translation-tools/rangjung-yeshe-tibetan.txt"))
          (start-time (current-time))
          (count 0))
      (if (file-exists-p dict-file)
          (progn
            (message "Loading Rangjung Yeshe Dictionary...")
            (with-temp-buffer
              (insert-file-contents dict-file)
              (goto-char (point-min))
              (while (not (eobp))
                (let ((line (buffer-substring-no-properties
                             (line-beginning-position)
                             (line-end-position))))
                  (unless (or (string-match-p "^#" line) (string= "" line))
                    (let* ((parts (split-string line "\t"))
                           (tibetan (car parts))
                           (english (cadr parts)))
                      (when (and tibetan english (not (string-empty-p tibetan)))
                        (puthash tibetan english rangjung-yeshe-dictionary)
                        (setq count (1+ count))))))
                (forward-line 1)))
            (setq rangjung-yeshe-loaded t)
            (let ((elapsed (float-time (time-subtract (current-time) start-time))))
              (message "✓ Loaded %d entries in %.2f seconds" count elapsed)))))))

(defun lookup-rangjung-yeshe (word)
  "Look up WORD in Rangjung Yeshe dictionary."
  (unless rangjung-yeshe-loaded
    (load-rangjung-yeshe-dictionary))
  (gethash word rangjung-yeshe-dictionary))

;; Test segment 001 from Reading_1-bp.org
(message "\n" "═══════════════════════════════════════════════════════════════")
(message "VOCABULARY COVERAGE DEMONSTRATION - Segment 001")
(message "═══════════════════════════════════════════════════════════════\n")

(message "Segment text:")
(message "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ།\n")

;; Extract words from segment 001
(let* ((segment "བཅོམ་ལྡན་འདས་ནི་རྒྱུ་མེད་པར་བརྩེ་བའི་བདག་ཉིད་དེ")
       (words '("བཅོམ་ལྡན་འདས" "ནི" "རྒྱུ" "མེད་པ" "མེད་པར" "བརྩེ་བ"
                "བརྩེ་བའི" "བདག་ཉིད" "དེ"))
       (found 0)
       (total (length words)))

  (message "Word-by-word analysis with Rangjung Yeshe dictionary:\n")

  (dolist (word words)
    (let ((definition (lookup-rangjung-yeshe word)))
      (if definition
          (progn
            (setq found (1+ found))
            (message "✓ %s" word)
            (message "  → %s\n" (substring definition 0 (min 70 (length definition)))))
        (message "✗ %s → NOT FOUND\n" word))))

  (message "═══════════════════════════════════════════════════════════════")
  (message "COVERAGE STATISTICS:")
  (message "═══════════════════════════════════════════════════════════════")
  (message "Found: %d/%d words (%.1f%%)" found total (* 100.0 (/ (float found) total)))
  (message "\nNote: Before Rangjung Yeshe integration, བཅོམ་ལྡན་འདས (Bhagavan)")
  (message "      - one of the most important Buddha epithets - was NOT in")
  (message "      the vocabulary database at all!")
  (message "═══════════════════════════════════════════════════════════════\n"))
