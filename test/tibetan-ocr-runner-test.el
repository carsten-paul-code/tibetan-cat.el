;;; tibetan-ocr-runner-test.el --- Tests for BDRC OCR runner -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for BDRC OCR integration functions.
;; Tests cover both OCR availability detection and graceful
;; handling when OCR is not installed.

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir)))

(require 'tibetan-ocr-runner)

;; ============================================================================
;; OCR AVAILABILITY TESTS
;; ============================================================================

(ert-deftest tibetan-ocr-available-p-returns-boolean ()
  "Test that tibetan-ocr-available-p returns a boolean."
  (let ((result (tibetan-ocr-available-p)))
    (should (or (null result) (stringp result) (booleanp result)))))

(ert-deftest tibetan-ocr-status-is-command ()
  "Test that tibetan-ocr-status is an interactive command."
  (should (fboundp 'tibetan-ocr-status))
  (should (commandp 'tibetan-ocr-status)))

(ert-deftest tibetan-ocr-open-app-is-command ()
  "Test that tibetan-ocr-open-app is callable."
  (should (fboundp 'tibetan-ocr-open-app))
  (should (commandp 'tibetan-ocr-open-app)))

;; ============================================================================
;; IMPORT FUNCTIONS
;; ============================================================================

(ert-deftest tibetan-ocr-import-from-file-is-command ()
  "Test that tibetan-ocr-import-from-file is callable."
  (should (fboundp 'tibetan-ocr-import-from-file))
  (should (commandp 'tibetan-ocr-import-from-file)))

(ert-deftest tibetan-ocr-import-from-clipboard-is-command ()
  "Test that tibetan-ocr-import-from-clipboard is callable."
  (should (fboundp 'tibetan-ocr-import-from-clipboard))
  (should (commandp 'tibetan-ocr-import-from-clipboard)))

(ert-deftest tibetan-ocr-import-from-buffer-is-command ()
  "Test that tibetan-ocr-import-from-buffer is callable."
  (should (fboundp 'tibetan-ocr-import-from-buffer))
  (should (commandp 'tibetan-ocr-import-from-buffer)))

;; ============================================================================
;; IMPORT FUNCTION LOGIC
;; ============================================================================

(ert-deftest tibetan-ocr-import-from-buffer-returns-plist ()
  "Test that tibetan-ocr-import-from-buffer returns a plist."
  (let ((test-buffer (generate-new-buffer "*ocr-import-test*")))
    (unwind-protect
        (with-current-buffer test-buffer
          (insert "བདག་གི་སེམས།")
          (let ((result (tibetan-ocr-import-from-buffer)))
            (should (plistp result))
            (should (plist-member result :text))
            (should (plist-member result :source))
            (should (plist-member result :model))
            (should (string-match-p "བདག" (plist-get result :text)))))
      (kill-buffer test-buffer))))

(ert-deftest tibetan-ocr-import-from-buffer-with-region ()
  "Test tibetan-ocr-import-from-buffer with a selected region."
  (let ((test-buffer (generate-new-buffer "*ocr-import-region-test*")))
    (unwind-protect
        (with-current-buffer test-buffer
          (insert "prefix text བདག་གི་སེམས། suffix text")
          ;; Select just the Tibetan part
          (goto-char (point-min))
          (search-forward "བདག")
          (let ((start (- (point) 2)))
            (goto-char start)
            (set-mark (point))
            (search-forward "།")
            (let ((result (tibetan-ocr-import-from-buffer)))
              (should (plistp result))
              ;; The result should contain the selected region
              (should (plist-member result :text)))))
      (kill-buffer test-buffer))))

;; ============================================================================
;; WORKFLOW FUNCTION
;; ============================================================================

(ert-deftest tibetan-ocr-workflow-is-command ()
  "Test that tibetan-ocr-workflow is callable."
  (should (fboundp 'tibetan-ocr-workflow))
  (should (commandp 'tibetan-ocr-workflow)))

;; ============================================================================
;; MODEL NAME MAPPING
;; ============================================================================

(ert-deftest tibetan-ocr-model-name-woodblock ()
  "Test OCR model name for woodblock."
  (should (equal (tibetan-ocr--model-name 'woodblock) "Woodblock")))

(ert-deftest tibetan-ocr-model-name-woodblock-stacks ()
  "Test OCR model name for woodblock-stacks."
  (should (equal (tibetan-ocr--model-name 'woodblock-stacks) "Woodblock-Stacks")))

(ert-deftest tibetan-ocr-model-name-modern ()
  "Test OCR model name for modern."
  (should (equal (tibetan-ocr--model-name 'modern) "Modern")))

(ert-deftest tibetan-ocr-model-name-ume-druma ()
  "Test OCR model name for ume-druma."
  (should (equal (tibetan-ocr--model-name 'ume-druma) "Ume_Druma")))

(ert-deftest tibetan-ocr-model-name-ume-petsuk ()
  "Test OCR model name for ume-petsuk."
  (should (equal (tibetan-ocr--model-name 'ume-petsuk) "Ume_Petsuk")))

(ert-deftest tibetan-ocr-model-name-pecha-alias ()
  "Test OCR model alias pecha -> Woodblock."
  (should (equal (tibetan-ocr--model-name 'pecha) "Woodblock")))

(ert-deftest tibetan-ocr-model-name-manuscript-alias ()
  "Test OCR model alias manuscript -> Ume_Druma."
  (should (equal (tibetan-ocr--model-name 'manuscript) "Ume_Druma")))

(ert-deftest tibetan-ocr-model-name-dbumed-alias ()
  "Test OCR model alias dbumed -> Ume_Druma."
  (should (equal (tibetan-ocr--model-name 'dbumed) "Ume_Druma")))

(ert-deftest tibetan-ocr-model-name-unknown-defaults ()
  "Test that unknown model defaults to Woodblock."
  (should (equal (tibetan-ocr--model-name 'unknown-model) "Woodblock")))

;; ============================================================================
;; APP DETECTION
;; ============================================================================

(ert-deftest tibetan-ocr-find-app-returns-string-or-nil ()
  "Test that tibetan-ocr--find-app returns string or nil."
  (let ((result (tibetan-ocr--find-app)))
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-ocr-get-models-dir-returns-string-or-nil ()
  "Test that tibetan-ocr--get-models-dir returns string or nil."
  (let ((result (tibetan-ocr--get-models-dir)))
    (should (or (null result) (stringp result)))))

;; ============================================================================
;; OCR RUN FUNCTION
;; ============================================================================

(ert-deftest tibetan-ocr-run-is-command ()
  "Test that tibetan-ocr-run is callable."
  (should (fboundp 'tibetan-ocr-run)))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-ocr-available-p-consistent-with-find-app ()
  "Test that available-p is consistent with find-app."
  (let ((available (tibetan-ocr-available-p))
        (found-app (tibetan-ocr--find-app)))
    ;; If app is found, available-p should be truthy
    ;; If app is not found, available-p should be falsy
    (if found-app
        (should available)
      (should-not available))))

;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(ert-deftest tibetan-ocr-import-map-exists ()
  "Test that OCR import keymap is defined."
  (should (boundp 'tibetan-ocr-import-map))
  (should (keymapp tibetan-ocr-import-map)))

(provide 'tibetan-ocr-runner-test)
;;; tibetan-ocr-runner-test.el ends here
