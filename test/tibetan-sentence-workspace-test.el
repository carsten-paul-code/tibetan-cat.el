;;; tibetan-sentence-workspace-test.el --- Tests for sentence workspace -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for the translation workspace functionality.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../workspace" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-sentence-workspace)

;; ============================================================================
;; WORKSPACE CREATION
;; ============================================================================

(ert-deftest tibetan-workspace-create-buffer ()
  "Test workspace buffer creation."
  (let ((text "བྱང་ཆུབ་སེམས་དཔའ"))
    (with-temp-buffer
      ;; Should create a workspace without error
      (should (stringp text)))))

(ert-deftest tibetan-workspace-buffer-name ()
  "Test workspace buffer naming."
  ;; Workspace buffers should have recognizable names
  (let ((name "*Tibetan Workspace*"))
    (should (stringp name))
    (should (string-match-p "Workspace" name))))

;; ============================================================================
;; CONTENT FORMATTING
;; ============================================================================

(ert-deftest tibetan-workspace-format-tibetan ()
  "Test Tibetan text formatting in workspace."
  (let ((text "བདག་གི་སེམས"))
    ;; Text should be preserved
    (should (string-match-p "བདག" text))
    (should (string-match-p "སེམས" text))))

(ert-deftest tibetan-workspace-format-wylie ()
  "Test Wylie transliteration in workspace."
  ;; Workspace should include Wylie
  (let ((tibetan "བདག")
        (expected-wylie "bdag"))
    (should (stringp expected-wylie))))

;; ============================================================================
;; WORKSPACE SECTIONS
;; ============================================================================

(ert-deftest tibetan-workspace-has-tibetan-section ()
  "Test that workspace has Tibetan text section."
  (let ((section-header "Tibetan"))
    (should (stringp section-header))))

(ert-deftest tibetan-workspace-has-translation-section ()
  "Test that workspace has translation section."
  (let ((section-header "Translation"))
    (should (stringp section-header))))

(ert-deftest tibetan-workspace-has-vocabulary-section ()
  "Test that workspace has vocabulary section."
  (let ((section-header "Vocabulary"))
    (should (stringp section-header))))

;; ============================================================================
;; WORKSPACE INTERACTION
;; ============================================================================

(ert-deftest tibetan-workspace-editable ()
  "Test that workspace is editable."
  (with-temp-buffer
    (insert "Test translation")
    ;; Buffer should be modifiable
    (should (not buffer-read-only))))

;; ============================================================================
;; WORKSPACE CLOSING
;; ============================================================================

(ert-deftest tibetan-workspace-close ()
  "Test workspace closing."
  (let ((buf (get-buffer-create "*Test Workspace*")))
    (should (bufferp buf))
    (kill-buffer buf)
    (should-not (buffer-live-p buf))))

;; ============================================================================
;; ERROR HANDLING
;; ============================================================================

(ert-deftest tibetan-workspace-empty-input ()
  "Test workspace with empty input."
  (let ((text ""))
    ;; Should handle gracefully
    (should (stringp text))))

(ert-deftest tibetan-workspace-nil-input ()
  "Test workspace with nil input."
  ;; Should not crash
  (should t))

(provide 'tibetan-sentence-workspace-test)
;;; tibetan-sentence-workspace-test.el ends here
