;;; test-analysis-output.el --- Test analysis output for segments -*- lexical-binding: t -*-

;;; Code:

;; Setup paths
(let ((base-dir "/Users/cp/emacs-tibetan-cat"))
  (add-to-list 'load-path base-dir)
  (add-to-list 'load-path (expand-file-name "core" base-dir))
  (add-to-list 'load-path (expand-file-name "analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "persist" base-dir))
  (setq tibetan-cat-data-dir base-dir))

;; Load modules (in order)
(require 'tibetan-wylie)
(require 'tibetan-utils)
(require 'tibetan-vocabulary)
(require 'tibetan-verb-classifier)
(require 'tibetan-enhanced-parser)
(require 'tibetan-particles-bialek)
(require 'tibetan-enhanced-display)
(require 'tibetan-analysis-persist)

;; Test with seg-032
(defvar test-text "སྔོན་འདས་པའི་དུས་བསྐལ་པ་གྲངས་མེད་པའི་ཕ་རོལ་ན།"
  "Seg-032 text.")

(when noninteractive
  (message "=== Analysis Test ===")
  (message "Loaded: compounds=%d, proper_nouns=%d"
           (hash-table-count tibetan-compounds-dict)
           (hash-table-count tibetan-proper-nouns-dict))

  (message "\n--- Testing seg-032 ---")
  (message "Input: %s" test-text)

  (let ((result (tibetan-analysis-generate-content test-text)))
    (message "\n--- Generated Content ---\n%s" result)))

(provide 'test-analysis-output)
;;; test-analysis-output.el ends here
