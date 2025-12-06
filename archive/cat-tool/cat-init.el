;;; cat-init.el --- CAT tool initialization (load modules only) -*- lexical-binding: t -*-

;;; Commentary:
;; Minimal initialization file for the modular CAT tool.
;; This file ONLY:
;; - Sets up load paths
;; - Loads all CAT modules
;; - Sets up keybindings
;; - Runs tests at startup (optional)
;;
;; All functions are defined in their respective modules.

;;; Code:

;; ============================================================================
;; LOAD PATH SETUP
;; ============================================================================

(defvar cat-base-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Base directory of cat-tool installation.")

(defvar cat-root-dir
  (file-name-directory (directory-file-name cat-base-dir))
  "Root directory of emacs-tibetan-cat installation.")

(defvar cat-data-dir
  (expand-file-name "data" cat-root-dir)
  "Directory containing CAT data files (dictionaries, glossaries).")

;; Add module directories to load path
(add-to-list 'load-path cat-base-dir)
(add-to-list 'load-path (expand-file-name "core" cat-base-dir))
(add-to-list 'load-path (expand-file-name "display" cat-base-dir))
(add-to-list 'load-path (expand-file-name "persist" cat-base-dir))
(add-to-list 'load-path (expand-file-name "support" cat-base-dir))

;; ============================================================================
;; LOAD CORE MODULES
;; ============================================================================

(require 'cat-utils)
(require 'cat-grammar)
(require 'cat-parser)

;; ============================================================================
;; LOAD DISPLAY MODULE
;; ============================================================================

(require 'cat-display)

;; ============================================================================
;; LOAD PERSISTENCE MODULE
;; ============================================================================

(require 'cat-persist)

;; ============================================================================
;; LOAD SUPPORT MODULES
;; ============================================================================

(require 'cat-translation)

;; ============================================================================
;; LOAD MAIN MODE
;; ============================================================================

(require 'cat-mode)

;; ============================================================================
;; INITIALIZE PARSER DATA DIRECTORY
;; ============================================================================

(cat-parser-set-data-dir cat-data-dir)

;; ============================================================================
;; GLOBAL KEYBINDINGS
;; ============================================================================

;; Segment analysis (C-c u prefix)
(global-set-key (kbd "C-c u i") #'cat-mode-analyze-segment)
(global-set-key (kbd "C-c u I") #'cat-mode-analyze-segment-enhanced)
(global-set-key (kbd "C-c u A") #'cat-mode-save-segment-analysis)
(global-set-key (kbd "C-c u R") #'cat-mode-re-analyze-segment)
(global-set-key (kbd "C-c u E") #'cat-mode-open-segment-analysis)

;; Translation
(global-set-key (kbd "C-c u t") #'cat-mode-show-translation)

;; Grammar
(global-set-key (kbd "C-c u p") #'cat-mode-show-particles)

;; Wylie
(global-set-key (kbd "C-c u w") #'cat-mode-show-wylie)
(global-set-key (kbd "C-c u W") #'cat-mode-copy-wylie)

;; ============================================================================
;; COMPATIBILITY ALIASES (for existing keybindings)
;; ============================================================================

(defalias 'tibetan-segment-info #'cat-mode-analyze-segment)
(defalias 'tibetan-segment-info-enhanced #'cat-mode-analyze-segment-enhanced)
(defalias 'tibetan-analyze-and-save #'cat-mode-save-segment-analysis)
(defalias 'tibetan-re-analyze #'cat-mode-re-analyze-segment)

;; ============================================================================
;; STARTUP TEST CONFIGURATION
;; ============================================================================

(defvar cat-run-tests-at-startup nil
  "When non-nil, run CAT tests after Emacs initialization.
Set to t to enable, nil to disable.
Tests run in the background and report results in *Messages*.")

(defvar cat-test-dir
  (expand-file-name "test" cat-base-dir)
  "Directory containing CAT test files.")

;; Add test directory to load path
(add-to-list 'load-path cat-test-dir)

(defun cat-run-startup-tests ()
  "Run CAT tests and display summary in *Messages*.
Called automatically at startup if `cat-run-tests-at-startup' is non-nil."
  (require 'ert)
  (require 'run-tests)
  (message "")
  (message "========================================")
  (message "  CAT Tool Startup Test Suite")
  (message "========================================")
  (let* ((start-time (current-time))
         (results (ert-run-tests-batch t))
         (elapsed (float-time (time-subtract (current-time) start-time))))
    (message "")
    (message "CAT tests completed in %.2f seconds" elapsed)
    (message "========================================")
    results))

(when cat-run-tests-at-startup
  (add-hook 'emacs-startup-hook #'cat-run-startup-tests))

(provide 'cat-init)
;;; cat-init.el ends here
