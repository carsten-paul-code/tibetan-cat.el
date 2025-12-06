;;; run-tests.el --- Test runner for CAT tool -*- lexical-binding: t -*-

;;; Commentary:
;; Main test runner for all CAT module tests.
;;
;; Usage from command line:
;;   emacs -batch -l run-tests.el -f cat-run-all-tests
;;
;; Usage from Emacs:
;;   M-x load-file RET run-tests.el RET
;;   M-x cat-run-all-tests RET
;;
;; Or run individual test files:
;;   M-x ert RET test-cat-utils RET
;;   M-x ert RET test-cat-grammar RET

;;; Code:

(require 'ert)

;; ============================================================================
;; SETUP LOAD PATHS
;; ============================================================================

(defvar cat-test-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing test files.")

(defvar cat-tool-dir
  (file-name-directory (directory-file-name cat-test-dir))
  "Directory containing cat-tool modules.")

(defvar cat-root-dir
  (file-name-directory (directory-file-name cat-tool-dir))
  "Root directory of emacs-tibetan-cat.")

;; Add all necessary paths
(add-to-list 'load-path cat-test-dir)
(add-to-list 'load-path cat-tool-dir)
(add-to-list 'load-path (expand-file-name "core" cat-tool-dir))
(add-to-list 'load-path (expand-file-name "display" cat-tool-dir))
(add-to-list 'load-path (expand-file-name "persist" cat-tool-dir))
(add-to-list 'load-path (expand-file-name "support" cat-tool-dir))

;; Also add existing tibetan modules if needed
(add-to-list 'load-path cat-root-dir)
(add-to-list 'load-path (expand-file-name "core" cat-root-dir))

;; ============================================================================
;; LOAD MODULES
;; ============================================================================

(require 'cat-utils)
(require 'cat-grammar)
(require 'cat-parser)
(require 'cat-translation)

;; ============================================================================
;; LOAD TEST FILES
;; ============================================================================

(require 'test-cat-utils)
(require 'test-cat-grammar)
(require 'test-cat-parser)
(require 'test-cat-translation)

;; ============================================================================
;; TEST RUNNER
;; ============================================================================

(defun cat-run-all-tests ()
  "Run all CAT tool tests."
  (interactive)
  (message "")
  (message "========================================")
  (message "  CAT Tool Test Suite")
  (message "========================================")
  (message "")
  (ert-run-tests-interactively t))

(defun cat-run-tests-batch ()
  "Run all tests in batch mode (for CI)."
  (ert-run-tests-batch-and-exit t))

(defun cat-run-utils-tests ()
  "Run only cat-utils tests."
  (interactive)
  (ert-run-tests-interactively "test-cat-.*utils"))

(defun cat-run-grammar-tests ()
  "Run only cat-grammar tests."
  (interactive)
  (ert-run-tests-interactively "test-cat-grammar"))

(defun cat-run-parser-tests ()
  "Run only cat-parser tests."
  (interactive)
  (ert-run-tests-interactively "test-cat-parser"))

(defun cat-run-translation-tests ()
  "Run only cat-translation tests."
  (interactive)
  (ert-run-tests-interactively "test-cat-translation"))

;; ============================================================================
;; TEST SUMMARY
;; ============================================================================

(defun cat-count-tests ()
  "Count and display all available tests."
  (interactive)
  (let ((utils-count 0)
        (grammar-count 0)
        (parser-count 0)
        (translation-count 0))
    (mapatoms
     (lambda (sym)
       (when (ert-test-boundp sym)
         (let ((name (symbol-name sym)))
           (cond
            ((string-match-p "test-cat-.*utils" name) (cl-incf utils-count))
            ((string-match-p "test-cat-grammar" name) (cl-incf grammar-count))
            ((string-match-p "test-cat-parser" name) (cl-incf parser-count))
            ((string-match-p "test-cat-translation" name) (cl-incf translation-count)))))))
    (message "")
    (message "CAT Tool Test Summary:")
    (message "  cat-utils:       %d tests" utils-count)
    (message "  cat-grammar:     %d tests" grammar-count)
    (message "  cat-parser:      %d tests" parser-count)
    (message "  cat-translation: %d tests" translation-count)
    (message "  ─────────────────────────")
    (message "  TOTAL:           %d tests"
             (+ utils-count grammar-count parser-count translation-count))
    (message "")))

;; ============================================================================
;; BATCH MODE SUPPORT
;; ============================================================================

;; When run with -batch, execute tests
(when noninteractive
  (cat-run-tests-batch))

(provide 'run-tests)
;;; run-tests.el ends here
