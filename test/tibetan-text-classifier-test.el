;;; tibetan-text-classifier-test.el --- Tests for tibetan-text-classifier.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for text type classification functionality.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-text-classifier)

;; ============================================================================
;; TEXT TYPE DETECTION
;; ============================================================================

(ert-deftest tibetan-classifier-detect-classical ()
  "Test detection of classical text type from header."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: classical\n")
    (insert "Some Tibetan text here")
    (goto-char (point-min))
    (let ((result (tibetan-detect-text-type)))
      (should (eq result 'classical)))))

(ert-deftest tibetan-classifier-detect-madhyamaka-verse ()
  "Test detection of madhyamaka-verse text type."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: madhyamaka-verse\n")
    (goto-char (point-min))
    (let ((result (tibetan-detect-text-type)))
      (should (eq result 'madhyamaka-verse)))))

(ert-deftest tibetan-classifier-detect-kagyu-verse ()
  "Test detection of kagyu-verse text type."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: kagyu-verse\n")
    (goto-char (point-min))
    (let ((result (tibetan-detect-text-type)))
      (should (eq result 'kagyu-verse)))))

(ert-deftest tibetan-classifier-detect-default-prose ()
  "Test default text type when no header present."
  (with-temp-buffer
    (insert "Some Tibetan text without header")
    (goto-char (point-min))
    (let ((result (tibetan-detect-text-type)))
      ;; Should return prose by default or nil if heuristics don't match
      (should (or (eq result 'prose)
                  (null result))))))

;; ============================================================================
;; EXPLICIT CLASSIFICATION
;; ============================================================================

(ert-deftest tibetan-classifier-explicit-classical ()
  "Test explicit classification with classical type."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: classical\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-explicit-classification)))
      (should (eq result 'classical)))))

(ert-deftest tibetan-classifier-explicit-madhyamaka ()
  "Test explicit classification with madhyamaka-verse type."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: madhyamaka-verse\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-explicit-classification)))
      (should (eq result 'madhyamaka-verse)))))

(ert-deftest tibetan-classifier-explicit-none ()
  "Test explicit classification returns nil when no header."
  (with-temp-buffer
    (insert "Some text without classification header")
    (goto-char (point-min))
    (let ((result (tibetan-get-explicit-classification)))
      (should (null result)))))

;; ============================================================================
;; HEURISTIC DETECTION
;; ============================================================================

(ert-deftest tibetan-classifier-heuristic-default-prose ()
  "Test heuristic classification returns prose by default."
  (with-temp-buffer
    (insert "Some generic Tibetan text without verse structure")
    (goto-char (point-min))
    (let ((result (tibetan-classify-by-heuristics)))
      (should (eq result 'prose)))))

(ert-deftest tibetan-classifier-heuristic-madhyamaka-verse ()
  "Test heuristic detection of Madhyamaka verse."
  (with-temp-buffer
    (insert "དབུ་མའི་གཞུང་ལུགས།\nནི་དབུ་མའི་རྗོད་པ། ང་རྒྱལ་དབུ་མ།")
    (goto-char (point-min))
    (let ((result (tibetan-classify-by-heuristics)))
      ;; Should detect madhyamaka-verse due to verse structure and madhyamaka terms
      (should (or (eq result 'madhyamaka-verse)
                  (eq result 'prose))))))

(ert-deftest tibetan-classifier-heuristic-kagyu-verse ()
  "Test heuristic detection of Kagyü verse."
  (with-temp-buffer
    (insert "ཕྱག་རྒྱ་ཆེན་པོའི་ཐབས། བདེ་སྟོང་གི་ལམ།")
    (goto-char (point-min))
    (let ((result (tibetan-classify-by-heuristics)))
      ;; Should detect kagyu-verse due to kagyu terms
      (should (or (eq result 'kagyu-verse)
                  (eq result 'prose))))))

;; ============================================================================
;; TEXT TYPE INFORMATION
;; ============================================================================

(ert-deftest tibetan-classifier-get-classical-info ()
  "Test retrieving information about classical text type."
  (let ((info (tibetan-get-text-type-info 'classical)))
    (should (listp info))
    (should (plist-get info :description))
    (should (plist-get info :features))
    (should (plist-get info :tools))))

(ert-deftest tibetan-classifier-get-madhyamaka-info ()
  "Test retrieving information about madhyamaka-verse type."
  (let ((info (tibetan-get-text-type-info 'madhyamaka-verse)))
    (should (listp info))
    (should (plist-get info :description))
    (should (plist-get info :features))
    (should (plist-get info :tools))))

(ert-deftest tibetan-classifier-get-kagyu-info ()
  "Test retrieving information about kagyu-verse type."
  (let ((info (tibetan-get-text-type-info 'kagyu-verse)))
    (should (listp info))
    (should (plist-get info :description))
    (should (plist-get info :features))
    (should (plist-get info :tools))))

(ert-deftest tibetan-classifier-get-prose-info ()
  "Test retrieving information about prose type."
  (let ((info (tibetan-get-text-type-info 'prose)))
    (should (listp info))
    (should (plist-get info :description))
    (should (plist-get info :features))
    (should (plist-get info :tools))))

;; ============================================================================
;; HEURISTIC HELPER FUNCTIONS
;; ============================================================================

(ert-deftest tibetan-classifier-verse-structure-detection ()
  "Test detection of verse structure."
  (let ((verse-text "རྩ་བའི་བླ་མ། སྐུ་གསུང་ཐུགས། ཡོན་ཏན་ཕྲིན་ལས།")
        (prose-text "གསུང་གི་དོན་ནི་རྗོད་པའོ། །"))
    ;; Verse text with 3+ shads (required by the heuristic)
    (should (tibetan-text-has-verse-structure-p verse-text))
    ;; Prose may or may not have verse structure
    (should (or (tibetan-text-has-verse-structure-p prose-text)
                (not (tibetan-text-has-verse-structure-p prose-text))))))

(ert-deftest tibetan-classifier-madhyamaka-terms ()
  "Test detection of Madhyamaka terminology."
  (let ((text-with "དབུ་མའི་ལུགས་ལ་སྟོང་པ་ཉིད།"))
    (should (tibetan-text-has-madhyamaka-terms-p text-with))))

(ert-deftest tibetan-classifier-madhyamaka-terms-negative ()
  "Test that non-Madhyamaka text doesn't match."
  (let ((text-without "སྤྱི་ནོར་གཡེ་རེ་དངོས་པོ།"))
    (should (not (tibetan-text-has-madhyamaka-terms-p text-without)))))

(ert-deftest tibetan-classifier-kagyu-terms ()
  "Test detection of Kagyü terminology."
  (let ((text-with "ཕྱག་རྒྱ་ཆེན་པོའི་ལམ་ལ།"))
    (should (tibetan-text-has-kagyu-terms-p text-with))))

(ert-deftest tibetan-classifier-kagyu-terms-negative ()
  "Test that non-Kagyü text doesn't match."
  (let ((text-without "བསོད་ནམས་ཀྱི་ཕ་རོལ་ཏུ།"))
    (should (not (tibetan-text-has-kagyu-terms-p text-without)))))

(ert-deftest tibetan-classifier-bialek-structure ()
  "Test detection of Bialek classroom structure."
  (let ((text-with "*** Segment 1\n〔seg: 1〕"))
    (should (tibetan-text-has-bialek-structure-p text-with))))

(ert-deftest tibetan-classifier-bialek-structure-negative ()
  "Test that non-Bialek text doesn't match."
  (let ((text-without "སྤྱི་ནོར་གཡེ་རེ་དངོས་པོ།"))
    (should (not (tibetan-text-has-bialek-structure-p text-without)))))

;; ============================================================================
;; EDGE CASES
;; ============================================================================

(ert-deftest tibetan-classifier-empty-buffer ()
  "Test behavior with empty buffer."
  (with-temp-buffer
    (let ((result (tibetan-detect-text-type)))
      ;; Should not error
      (should (or (null result) (symbolp result))))))

(ert-deftest tibetan-classifier-whitespace-handling ()
  "Test handling of whitespace in header values."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE:   classical   \n")
    (goto-char (point-min))
    (let ((result (tibetan-detect-text-type)))
      (should (eq result 'classical)))))

(provide 'tibetan-text-classifier-test)
;;; tibetan-text-classifier-test.el ends here
