;;; test-rangjung-yeshe-minimal.el --- Minimal test of Rangjung Yeshe dictionary

;; Define the dictionary hash table
(defvar rangjung-yeshe-dictionary (make-hash-table :test 'equal :size 170000)
  "Hash table for Rangjung Yeshe Tibetan-English dictionary.")

(defvar rangjung-yeshe-loaded nil
  "Flag indicating whether Rangjung Yeshe dictionary has been loaded.")

;; Load function (copied from init.el)
(defun load-rangjung-yeshe-dictionary ()
  "Load the Rangjung Yeshe dictionary into memory."
  (unless rangjung-yeshe-loaded
    (let ((dict-file (expand-file-name
                      "~/buddhist-studies/translation-tools/rangjung-yeshe-tibetan.txt"))
          (start-time (current-time))
          (count 0))

      (if (file-exists-p dict-file)
          (progn
            (message "Loading Rangjung Yeshe Dictionary (162K entries)...")
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
              (message "✓ Loaded %d Rangjung Yeshe entries in %.2f seconds" count elapsed)))

        (message "⚠ Rangjung Yeshe dictionary not found at: %s" dict-file)))))

(defun lookup-rangjung-yeshe (word)
  "Look up WORD in Rangjung Yeshe dictionary."
  (unless rangjung-yeshe-loaded
    (load-rangjung-yeshe-dictionary))
  (gethash word rangjung-yeshe-dictionary))

;; Run tests
(message "\n=== TESTING RANGJUNG YESHE DICTIONARY ===\n")

;; Test 1: Dictionary should not be loaded yet
(message "Test 1: Checking lazy loading...")
(if rangjung-yeshe-loaded
    (message "  ✗ FAILED: Dictionary should not be loaded yet")
  (message "  ✓ PASSED: Dictionary not loaded (lazy loading working)"))

;; Test 2: Perform a lookup (should trigger loading)
(message "\nTest 2: Testing dictionary loading and lookup...")
(message "Looking up བཅོམ་ལྡན་འདས (Bhagavan)...")
(let ((result (lookup-rangjung-yeshe "བཅོམ་ལྡན་འདས")))
  (if result
      (progn
        (message "  ✓ PASSED: Found definition")
        (message "  Definition: %s" (substring result 0 (min 100 (length result)))))
    (message "  ✗ FAILED: Definition not found")))

;; Test 3: Dictionary should now be loaded
(message "\nTest 3: Checking dictionary loaded flag...")
(if rangjung-yeshe-loaded
    (message "  ✓ PASSED: Dictionary now loaded")
  (message "  ✗ FAILED: Dictionary should be loaded after lookup"))

;; Test 4: Test hash table size
(message "\nTest 4: Checking dictionary size...")
(let ((size (hash-table-count rangjung-yeshe-dictionary)))
  (message "  Dictionary contains %d entries" size)
  (if (> size 160000)
      (message "  ✓ PASSED: Expected ~162,728 entries")
    (message "  ✗ FAILED: Too few entries (expected ~162,728)")))

;; Test 5: Test several critical terms
(message "\nTest 5: Testing critical Buddhist terms...")
(let ((test-words '(("སེམས་ཅན" . "sentient being")
                    ("ཆོས" . "dharma")
                    ("སངས་རྒྱས" . "buddha")
                    ("ཤེས་རབ" . "wisdom")
                    ("བྱང་ཆུབ་སེམས་དཔའ" . "bodhisattva"))))
  (dolist (pair test-words)
    (let* ((word (car pair))
           (expected (cdr pair))
           (result (lookup-rangjung-yeshe word)))
      (if result
          (message "  ✓ %s → %s" word (substring result 0 (min 60 (length result))))
        (message "  ✗ %s → NOT FOUND" word)))))

;; Test 6: Test a word that should definitely be in Rangjung Yeshe
(message "\nTest 6: Testing specific Rangjung Yeshe coverage...")
(let ((test-result (lookup-rangjung-yeshe "རྒྱལ་བ"))) ;; "victorious one"
  (if test-result
      (message "  ✓ རྒྱལ་བ found: %s" (substring test-result 0 (min 50 (length test-result))))
    (message "  ✗ རྒྱལ་བ NOT FOUND")))

(message "\n=== TEST COMPLETE ===\n")
