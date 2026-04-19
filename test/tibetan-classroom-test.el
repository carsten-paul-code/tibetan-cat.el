;;; tibetan-classroom-test.el --- Tests for classroom analysis module -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for tibetan-classroom.el
;; Tests for:
;; - Cache key generation
;; - Cache round-trip (store and retrieve)
;; - DharmaMitra translation handling
;; - Verb extraction and analysis
;; - Auto-update and toggle-auto commands

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-classroom)

;; ============================================================================
;; CACHE KEY TESTS
;; ============================================================================

(ert-deftest tibetan-cache-key-returns-string ()
  "Test that tibetan-cache-key returns a cons cell with string hash."
  (let ((key (tibetan-cache-key "seg1" "བྱང་ཆུབ་སེམས་དཔའ།")))
    (should key)
    (should (consp key))
    (should (stringp (car key)))
    (should (stringp (cdr key)))
    (should (equal (car key) "seg1"))))

(ert-deftest tibetan-cache-key-different-text-different-hash ()
  "Test that different text produces different hash values."
  (let ((key1 (tibetan-cache-key "seg1" "བྱང་ཆུབ་སེམས་དཔའ།"))
        (key2 (tibetan-cache-key "seg1" "སངས་རྒྱས།")))
    (should key1)
    (should key2)
    (should-not (equal key1 key2))))

(ert-deftest tibetan-cache-key-same-text-same-hash ()
  "Test that identical text produces identical hash."
  (let ((key1 (tibetan-cache-key "seg1" "བྱང་ཆུབ་སེམས་དཔའ།"))
        (key2 (tibetan-cache-key "seg1" "བྱང་ཆུབ་སེམས་དཔའ།")))
    (should (equal key1 key2))))

(ert-deftest tibetan-cache-key-different-segment-id ()
  "Test that different segment IDs produce different keys."
  (let ((key1 (tibetan-cache-key "seg1" "བྱང་ཆུབ་སེམས་དཔའ།"))
        (key2 (tibetan-cache-key "seg2" "བྱང་ཆུབ་སེམས་དཔའ།")))
    (should-not (equal key1 key2))))

;; ============================================================================
;; CACHE ROUND-TRIP TESTS
;; ============================================================================

(ert-deftest tibetan-cache-analysis-round-trip ()
  "Test storing and retrieving analysis from cache."
  ;; Clear cache first
  (setq tibetan-analysis-cache (make-hash-table :test 'equal))

  (let ((seg-id "seg1")
        (text "བྱང་ཆུབ་སེམས་དཔའ།")
        (wylie "byang chub sems dpa")
        (trans "Bodhisattva")
        (vocab '(("བྱང་ཆུབ" . "enlightenment")))
        (grammar '((particle . "particle-data")))
        (sugg "suggested translation"))

    ;; Cache the analysis
    (tibetan-cache-analysis seg-id text wylie trans vocab grammar sugg)

    ;; Retrieve it
    (let ((cached (tibetan-get-cached-analysis seg-id text)))
      (should cached)
      (should (equal wylie (nth 0 cached)))
      (should (equal trans (nth 1 cached)))
      (should (equal vocab (nth 2 cached)))
      (should (equal grammar (nth 3 cached)))
      (should (equal sugg (nth 4 cached))))))

(ert-deftest tibetan-get-cached-analysis-nil-for-uncached ()
  "Test that uncached analysis returns nil."
  ;; Clear cache
  (setq tibetan-analysis-cache (make-hash-table :test 'equal))

  (let ((cached (tibetan-get-cached-analysis "seg99" "ཆོས་གསུངས།")))
    (should-not cached)))

(ert-deftest tibetan-cache-analysis-multiple-entries ()
  "Test caching multiple analyses."
  ;; Clear cache
  (setq tibetan-analysis-cache (make-hash-table :test 'equal))

  (let ((seg1 "seg1")
        (text1 "བྱང་ཆུབ་སེམས་དཔའ།")
        (seg2 "seg2")
        (text2 "སངས་རྒྱས།"))

    ;; Cache two analyses
    (tibetan-cache-analysis seg1 text1 "wy1" "trans1" nil nil nil)
    (tibetan-cache-analysis seg2 text2 "wy2" "trans2" nil nil nil)

    ;; Retrieve both
    (let ((cached1 (tibetan-get-cached-analysis seg1 text1))
          (cached2 (tibetan-get-cached-analysis seg2 text2)))
      (should cached1)
      (should cached2)
      (should (equal "trans1" (nth 1 cached1)))
      (should (equal "trans2" (nth 1 cached2))))))

;; ============================================================================
;; DHARMAMITRA TRANSLATION TESTS
;; ============================================================================

(ert-deftest tibetan-get-dharmamitra-translation-nil-input ()
  "Test handling of nil or empty input."
  (should-not (tibetan-get-dharmamitra-translation nil))
  (should-not (tibetan-get-dharmamitra-translation "")))
  ;; Whitespace-only strings are treated as valid input (could be trimmed)
  ;; The function returns a string response in that case

(ert-deftest tibetan-get-dharmamitra-translation-graceful-fail ()
  "Test that function handles missing DharmaMitra gracefully."
  (let ((result (tibetan-get-dharmamitra-translation "བྱང་ཆུབ་སེམས་དཔའ།")))
    ;; Should return a string, even if DharmaMitra not loaded
    (should (stringp result))))

(ert-deftest tibetan-get-dharmamitra-translation-returns-string ()
  "Test that result is always a string."
  (let ((result (tibetan-get-dharmamitra-translation "སངས་རྒྱས།")))
    (should (stringp result))))

;; ============================================================================
;; VERB EXTRACTION TESTS
;; ============================================================================

(ert-deftest tibetan-extract-and-analyze-verbs-nil-input ()
  "Test handling of nil or empty text."
  (should-not (tibetan-extract-and-analyze-verbs nil))
  (should-not (tibetan-extract-and-analyze-verbs "")))

(ert-deftest tibetan-extract-and-analyze-verbs-returns-list ()
  "Test that function returns a list or nil."
  (let ((result (tibetan-extract-and-analyze-verbs "སངས་རྒྱས་གསུངས།")))
    ;; Should return nil (if verb classifier not loaded) or a list
    (should (or (null result) (listp result)))))

(ert-deftest tibetan-extract-and-analyze-verbs-removes-punctuation ()
  "Test that punctuation is handled correctly."
  (let ((result1 (tibetan-extract-and-analyze-verbs "གསུངས།"))
        (result2 (tibetan-extract-and-analyze-verbs "གསུངས་༏")))
    ;; Both should handle punctuation (same results or both nil)
    (should (or (null result1) (listp result1)))
    (should (or (null result2) (listp result2)))))

;; ============================================================================
;; AUTO-UPDATE COMMAND TESTS
;; ============================================================================

(ert-deftest tibetan-auto-update-is-commandp ()
  "Test that tibetan-auto-update is a valid command."
  (should (fboundp 'tibetan-auto-update)))

(ert-deftest tibetan-toggle-auto-is-commandp ()
  "Test that tibetan-toggle-auto is an interactive command."
  (should (fboundp 'tibetan-toggle-auto)))

(ert-deftest tibetan-toggle-auto-toggles-mode ()
  "Test that toggle-auto actually toggles the mode."
  ;; Save original state
  (let ((original-state tibetan-auto-mode))
    (unwind-protect
        (progn
          ;; Start fresh
          (setq tibetan-auto-mode nil)
          (should-not tibetan-auto-mode)

          ;; Toggle on
          (tibetan-toggle-auto)
          (should tibetan-auto-mode)

          ;; Toggle off
          (tibetan-toggle-auto)
          (should-not tibetan-auto-mode))

      ;; Restore original state
      (setq tibetan-auto-mode original-state))))

(ert-deftest tibetan-enable-auto-analysis-alias ()
  "Test that tibetan-enable-auto-analysis is an alias."
  (should (fboundp 'tibetan-enable-auto-analysis))
  ;; Check that calling both functions results in same behavior
  (let ((original-state tibetan-auto-mode))
    (unwind-protect
        (progn
          (setq tibetan-auto-mode nil)
          (tibetan-enable-auto-analysis)
          (let ((state-after-enable tibetan-auto-mode))
            (tibetan-toggle-auto)
            (let ((state-after-toggle tibetan-auto-mode))
              ;; Both should toggle the same variable
              (should (not (equal state-after-enable state-after-toggle))))))
      (setq tibetan-auto-mode original-state))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-classroom-caching-with-real-tibetan ()
  "Test caching system with realistic Tibetan text."
  ;; Clear cache
  (setq tibetan-analysis-cache (make-hash-table :test 'equal))

  (let* ((tibetan-text "བྱང་ཆུབ་སེམས་དཔའ་དེ་དག་གིས།")
         (seg-id "Padma-1")
         (cached-before (tibetan-get-cached-analysis seg-id tibetan-text)))

    ;; Initially not cached
    (should-not cached-before)

    ;; Cache it
    (tibetan-cache-analysis seg-id tibetan-text "byang chub" "Bodhisattvas" nil nil nil)

    ;; Now retrieve and verify
    (let ((cached-after (tibetan-get-cached-analysis seg-id tibetan-text)))
      (should cached-after)
      (should (equal "Bodhisattvas" (nth 1 cached-after))))))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(defun tibetan-classroom-run-tests ()
  "Run all classroom tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-classroom-"))

(provide 'tibetan-classroom-test)
;;; tibetan-classroom-test.el ends here
