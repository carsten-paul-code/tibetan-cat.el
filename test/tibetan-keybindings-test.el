;;; tibetan-keybindings-test.el --- Tests for keybindings -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests to verify that keybindings are correctly set.

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir)))

;; Load modules that set keybindings
(require 'tibetan-org-structure nil t)
(require 'tibetan-auto-analysis nil t)
(require 'tibetan-structure-reorg nil t)

;; ============================================================================
;; DOCUMENT PREPARATION KEYBINDINGS
;; ============================================================================

(ert-deftest tibetan-keybinding-prepare-document ()
  "Test that C-c u P is bound to tibetan-prepare-document."
  (skip-unless (fboundp 'tibetan-prepare-document))
  (should (eq (key-binding (kbd "C-c u P")) 'tibetan-prepare-document)))

(ert-deftest tibetan-keybinding-auto-analyze ()
  "Test that C-c u B is bound to tibetan-auto-analyze-document."
  (skip-unless (fboundp 'tibetan-auto-analyze-document))
  (should (eq (key-binding (kbd "C-c u B")) 'tibetan-auto-analyze-document)))

(ert-deftest tibetan-keybinding-reorganize ()
  "Test that C-c u O is bound to tibetan-reorganize-analysis-files."
  (skip-unless (fboundp 'tibetan-reorganize-analysis-files))
  (should (eq (key-binding (kbd "C-c u O")) 'tibetan-reorganize-analysis-files)))

(ert-deftest tibetan-keybinding-preview-reorg ()
  "Test that C-c u U is bound to tibetan-preview-reorganization."
  (skip-unless (fboundp 'tibetan-preview-reorganization))
  (should (eq (key-binding (kbd "C-c u U")) 'tibetan-preview-reorganization)))

;; ============================================================================
;; FUNCTION EXISTENCE TESTS
;; ============================================================================

(ert-deftest tibetan-function-prepare-document-exists ()
  "Test that tibetan-prepare-document function exists."
  (should (fboundp 'tibetan-prepare-document)))

(ert-deftest tibetan-function-auto-analyze-exists ()
  "Test that tibetan-auto-analyze-document function exists."
  (should (fboundp 'tibetan-auto-analyze-document)))

(ert-deftest tibetan-function-reorganize-exists ()
  "Test that tibetan-reorganize-analysis-files function exists."
  (should (fboundp 'tibetan-reorganize-analysis-files)))

(ert-deftest tibetan-function-preview-reorg-exists ()
  "Test that tibetan-preview-reorganization function exists."
  (should (fboundp 'tibetan-preview-reorganization)))

;; ============================================================================
;; INTERACTIVE TESTS
;; ============================================================================

(ert-deftest tibetan-function-prepare-document-interactive ()
  "Test that tibetan-prepare-document is interactive."
  (skip-unless (fboundp 'tibetan-prepare-document))
  (should (commandp 'tibetan-prepare-document)))

(ert-deftest tibetan-function-auto-analyze-interactive ()
  "Test that tibetan-auto-analyze-document is interactive."
  (skip-unless (fboundp 'tibetan-auto-analyze-document))
  (should (commandp 'tibetan-auto-analyze-document)))

(ert-deftest tibetan-function-reorganize-interactive ()
  "Test that tibetan-reorganize-analysis-files is interactive."
  (skip-unless (fboundp 'tibetan-reorganize-analysis-files))
  (should (commandp 'tibetan-reorganize-analysis-files)))

(ert-deftest tibetan-function-preview-reorg-interactive ()
  "Test that tibetan-preview-reorganization is interactive."
  (skip-unless (fboundp 'tibetan-preview-reorganization))
  (should (commandp 'tibetan-preview-reorganization)))

;; ============================================================================
;; HELPER
;; ============================================================================

(defun tibetan-keybindings-run-tests ()
  "Run all keybinding tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-keybinding-\\|^tibetan-function-"))

(provide 'tibetan-keybindings-test)
;;; tibetan-keybindings-test.el ends here
