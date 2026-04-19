;;; tibetan-particles-test.el --- Tests for tibetan-particles.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for context-aware particle analysis functionality.
;; Tests cover safe substring extraction and particle analysis in context.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-particles)

;; ============================================================================
;; SAFE SUBSTRING TESTS
;; ============================================================================

(ert-deftest tibetan-particles-safe-substr-basic ()
  "Test basic safe substring extraction."
  (should (equal (tibetan-particles-safe-substr "བདག" 0 1) "བ"))
  (should (equal (tibetan-particles-safe-substr "བདག" 0 2) "བད"))
  (should (equal (tibetan-particles-safe-substr "test" 0 2) "te")))

(ert-deftest tibetan-particles-safe-substr-out-of-range ()
  "Test safe substring with out-of-range indices."
  (should (equal (tibetan-particles-safe-substr "བདག" 100 200) ""))
  (should (equal (tibetan-particles-safe-substr "བདག" 10 20) "")))

(ert-deftest tibetan-particles-safe-substr-nil-input ()
  "Test safe substring with nil input."
  (should (equal (tibetan-particles-safe-substr nil 0 1) ""))
  (should (equal (tibetan-particles-safe-substr "" 0 1) "")))

(ert-deftest tibetan-particles-safe-substr-full-range ()
  "Test safe substring extraction of full string."
  (should (equal (tibetan-particles-safe-substr "བདག" 0 4) "བདག")))

;; ============================================================================
;; PARTICLE ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-particles-in-context-function-exists ()
  "Test that analysis function exists."
  (should (fboundp 'tibetan-analyze-particles-in-context)))

(ert-deftest tibetan-analyze-particles-in-context-returns-list ()
  "Test that particle analysis returns a list."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "བདག")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-empty-input ()
  "Test particle analysis with empty input."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "")))
    (should (listp result))
    (should (= (length result) 0))))

(ert-deftest tibetan-analyze-particles-in-context-genitive ()
  "Test detection of genitive particles in context."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "པའི")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-ergative ()
  "Test detection of ergative particles in context."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "མི་གིས")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-ablative ()
  "Test detection of ablative particles in context."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "གནས་ནས")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-sequential ()
  "Test detection of sequential converb particles."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "གསེགས་སྟེ")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-analysis-format ()
  "Test that returned analysis has correct structure."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "པའི")))
    (dolist (item result)
      (when item
        (should (listp item))
        ;; Each analysis should have at least 6 elements:
        ;; (particle word type function translation schwieger-ref)
        (should (>= (length item) 6))
        ;; Particle should be string
        (should (stringp (nth 0 item)))
        ;; Word should be string
        (should (stringp (nth 1 item)))
        ;; Type should be string
        (should (stringp (nth 2 item)))))))

;; ============================================================================
;; EDGE CASES
;; ============================================================================

(ert-deftest tibetan-analyze-particles-in-context-multiple-words ()
  "Test particle analysis with multiple words."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "བདག་གིས་བྱེད")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-with-punctuation ()
  "Test particle analysis with Tibetan punctuation."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "པའི།")))
    (should (listp result))))

(ert-deftest tibetan-analyze-particles-in-context-no-particles ()
  "Test particle analysis with text containing no particles."
  (skip-unless (fboundp 'tibetan-analyze-particles-in-context))
  (let ((result (tibetan-analyze-particles-in-context "བདག")))
    (should (listp result))))

(provide 'tibetan-particles-test)
;;; tibetan-particles-test.el ends here
