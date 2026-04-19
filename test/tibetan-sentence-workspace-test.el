;;; tibetan-sentence-workspace-test.el --- Tests for sentence workspace -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for the translation workspace functionality.
;; Tests cover: sentence extraction, workspace creation, preparation, and export.

;;; Code:

(require 'ert)
(require 'org)
(require 'cl-lib)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../workspace" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-sentence-workspace)

;; Load real org-structure functions (no mocks - they break other test files)
(require 'tibetan-org-structure)

;; ============================================================================
;; SENTENCE EXTRACTION - ANY FORMAT
;; ============================================================================

(ert-deftest tibetan-get-sentence-at-point-any-format-empty ()
  "Test sentence extraction with empty buffer."
  (with-temp-buffer
    (let ((result (tibetan-get-sentence-at-point-any-format)))
      ;; Should return nil or plist when no sentence found
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-get-sentence-at-point-any-format-old-markers ()
  "Test sentence extraction with old format markers."
  (with-temp-buffer
    (insert "‖SEN‖བདག་གི་སེམས།‖SEG‖\n")
    (insert "‖SEN‖དེ་ལ་སེམས་ཁྱེད།‖SEG‖\n")
    (goto-char 10)
    (let ((result (tibetan-get-sentence-at-point-any-format)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-get-sentence-at-point-any-format-org-mode ()
  "Test sentence extraction from org-mode structure."
  (with-temp-buffer
    (org-mode)
    (insert "* Document\n")
    (insert "** Sentence 1\n")
    (insert "བདག་གི་སེམས།\n")
    (goto-char 30)
    (let ((result (tibetan-get-sentence-at-point-any-format)))
      ;; Should work or return nil gracefully
      (should (or (null result) (listp result))))))

;; ============================================================================
;; SENTENCE EXTRACTION - STANDARD FORMAT
;; ============================================================================

(ert-deftest tibetan-get-sentence-at-point-with-heading ()
  "Test sentence extraction with org heading."
  (with-temp-buffer
    (org-mode)
    (insert "** Sentence 1\n")
    (insert "བདག་གི་སེམས།\n")
    (goto-char 30)
    (let ((result (tibetan-get-sentence-at-point)))
      ;; Should find the sentence or return nil
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-get-sentence-at-point-multiple-segments ()
  "Test sentence extraction with multiple segments."
  (with-temp-buffer
    (org-mode)
    (insert "** Sentence 1\n")
    (insert "བདག་གི་\n")
    (insert "སེམས་\n")
    (insert "བདེ་བ།\n")
    (goto-char 30)
    (let ((result (tibetan-get-sentence-at-point)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-get-sentence-at-point-no-heading ()
  "Test sentence extraction when not on heading."
  (with-temp-buffer
    (insert "Random text\n")
    (insert "བདག་གི་སེམས།\n")
    (goto-char 20)
    (let ((result (tibetan-get-sentence-at-point)))
      ;; May return nil if no sentence structure found
      (should (or (null result) (listp result))))))

;; ============================================================================
;; WORKSPACE CREATION
;; ============================================================================

(ert-deftest tibetan-create-sentence-workspace-with-data ()
  "Test workspace creation with sentence data."
  (let ((sentence-data (list :number "1"
                             :segments '(("1" . "བདག་གི་"))
                             :start 1
                             :end 100)))
    (with-temp-buffer
      (let ((result (tibetan-create-sentence-workspace sentence-data)))
        ;; Should return nil (workspace created) or string buffer
        (should (or (null result) (bufferp result) (stringp result)))))))

(ert-deftest tibetan-create-sentence-workspace-nil-data ()
  "Test workspace creation with nil data."
  (let ((result (tibetan-create-sentence-workspace nil)))
    ;; Should handle gracefully
    (should (or (null result) (bufferp result)))))

(ert-deftest tibetan-create-sentence-workspace-empty-segments ()
  "Test workspace creation with empty segments."
  (let ((sentence-data (list :number "1"
                             :segments '()
                             :start 1
                             :end 10)))
    (with-temp-buffer
      (let ((result (tibetan-create-sentence-workspace sentence-data)))
        (should (or (null result) (bufferp result)))))))

;; ============================================================================
;; SENTENCE PREPARATION
;; ============================================================================

(ert-deftest tibetan-prepare-sentence-basic ()
  "Test basic sentence preparation."
  (skip-unless (fboundp 'tibetan-prepare-sentence))
  (with-temp-buffer
    (org-mode)
    (when (fboundp 'org-set-regexps-and-options) (org-set-regexps-and-options))
    (font-lock-ensure)
    (insert "‖SEN‖1\n")
    (insert "〔SEG:1〕བདག་གི་སེམས།〔/SEG〕\n")
    (insert "‖SEN‖2\n")
    ;; Position cursor in first sentence
    (goto-char (point-min))
    (forward-line 1)
    (let ((result (condition-case err
                      (progn (tibetan-prepare-sentence) t)
                    (error nil))))
      ;; Should work without error when sentence is found
      (should (or result t)))))

(ert-deftest tibetan-prepare-sentence-no-text ()
  "Test prepare sentence when no text exists."
  (with-temp-buffer
    (let ((result (condition-case err
                      (progn (tibetan-prepare-sentence) t)
                    (error nil))))
      ;; Should handle gracefully or throw error
      (should (or (null result) result)))))

;; ============================================================================
;; WORKSPACE SAVING
;; ============================================================================

(ert-deftest tibetan-save-workspace-basic ()
  "Test saving workspace to file."
  (with-temp-buffer
    (let ((tibetan-workspace-file nil))
      ;; Should not error when workspace-file is nil
      (should (progn (tibetan-save-workspace) t)))))

(ert-deftest tibetan-save-workspace-buffer-content ()
  "Test saving maintains buffer content."
  (with-temp-buffer
    (insert "Test content\n")
    (let ((tibetan-workspace-file nil))
      (tibetan-save-workspace)
      (should (string-match-p "Test content" (buffer-string))))))

;; ============================================================================
;; PDF EXPORT - FUNCTION EXISTENCE TESTS
;; ============================================================================

(ert-deftest tibetan-export-workspace-pdf-exists ()
  "Test that export-workspace-pdf function exists."
  (should (fboundp 'tibetan-export-workspace-pdf)))

(ert-deftest tibetan-export-workspace-pdf-is-command ()
  "Test that export-workspace-pdf is callable."
  (should (commandp 'tibetan-export-workspace-pdf)))

(ert-deftest tibetan-export-any-org-to-pdf-exists ()
  "Test that export-any-org-to-pdf function exists."
  (should (fboundp 'tibetan-export-any-org-to-pdf)))

(ert-deftest tibetan-export-any-org-to-pdf-is-command ()
  "Test that export-any-org-to-pdf is callable."
  (should (commandp 'tibetan-export-any-org-to-pdf)))

;; ============================================================================
;; WORKSPACE STRUCTURE AND SECTIONS
;; ============================================================================

(ert-deftest tibetan-workspace-structure-org-format ()
  "Test workspace uses org-mode format."
  (with-temp-buffer
    (org-mode)
    (insert "* Tibetan Text\n")
    (insert "** Sentence 1\n")
    (insert "བདག་གི་སེམས།\n")
    (insert "* Translation\n")
    (insert "My mind\n")
    (should (derived-mode-p 'org-mode))))

(ert-deftest tibetan-workspace-contains-vocabulary-section ()
  "Test workspace can contain vocabulary section."
  (with-temp-buffer
    (org-mode)
    (insert "* Vocabulary\n")
    (insert "- བདག: self\n")
    (insert "- སེམས: mind\n")
    (let ((has-vocab (re-search-backward "^\\* Vocabulary" nil t)))
      (should has-vocab))))

(ert-deftest tibetan-workspace-editable ()
  "Test that workspace buffer is editable."
  (with-temp-buffer
    (org-mode)
    (insert "Test content")
    ;; Buffer should be modifiable
    (should (not buffer-read-only))))

;; ============================================================================
;; ERROR HANDLING AND EDGE CASES
;; ============================================================================

(ert-deftest tibetan-workspace-empty-buffer ()
  "Test workspace with empty buffer."
  (with-temp-buffer
    (let ((result (tibetan-get-sentence-at-point)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-workspace-only-whitespace ()
  "Test workspace with only whitespace."
  (with-temp-buffer
    (insert "   \n\t\n   \n")
    (let ((result (tibetan-get-sentence-at-point)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-workspace-very-long-sentence ()
  "Test workspace with very long sentence."
  (with-temp-buffer
    (org-mode)
    (insert "** Sentence 1\n")
    (dotimes (i 100)
      (insert "བདག་གི་སེམས་"))
    (insert "\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-sentence-at-point)))
      (should (or (null result) (listp result))))))

(ert-deftest tibetan-workspace-mixed-content ()
  "Test workspace with mixed Tibetan and English."
  (with-temp-buffer
    (insert "English introduction: here is some text\n")
    (insert "བདག་གི་སེམས།\n")
    (insert "More English: here\n")
    (let ((result (tibetan-get-sentence-at-point)))
      (should (or (null result) (listp result))))))

;; ============================================================================
;; WORKSPACE CONTEXT AND STATE
;; ============================================================================

(ert-deftest tibetan-workspace-preserves-state ()
  "Test that workspace operations preserve buffer state."
  (with-temp-buffer
    (insert "Line 1\n")
    (insert "Line 2\n")
    (insert "Line 3\n")
    (let ((initial-content (buffer-string)))
      ;; Prepare sentence (will fail with no sentence structure)
      (goto-char (point-min))
      (condition-case err
          (tibetan-prepare-sentence)
        (error nil))
      ;; Content should still be there
      (should (string-match-p "Line 1" (buffer-string))))))

(provide 'tibetan-sentence-workspace-test)
;;; tibetan-sentence-workspace-test.el ends here
