;;; test-rangjung-yeshe.el --- Test Rangjung Yeshe dictionary integration

;; Load configuration
(load-file "~/.emacs.d/init.el")

(message "\n=== TESTING RANGJUNG YESHE DICTIONARY ===\n")

;; Test 1: Dictionary should not be loaded yet (lazy loading)
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
                    ("ཤེས་རབ" . "wisdom"))))
  (dolist (pair test-words)
    (let* ((word (car pair))
           (expected (cdr pair))
           (result (lookup-rangjung-yeshe word)))
      (if result
          (message "  ✓ %s → %s" word (substring result 0 (min 50 (length result))))
        (message "  ✗ %s → NOT FOUND" word)))))

;; Test 6: Test the enhanced lookup cascade
(message "\nTest 6: Testing enhanced lookup cascade...")
(let ((result (tibetan-lookup-word-enhanced "བཅོམ་ལྡན་འདས")))
  (if (and result (not (string-match-p "Unknown" result)))
      (message "  ✓ PASSED: Enhanced lookup working")
    (message "  ✗ FAILED: Enhanced lookup not working")))

(message "\n=== TEST COMPLETE ===\n")
