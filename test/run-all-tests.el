;;; run-all-tests.el --- Run all Tibetan CAT tests -*- lexical-binding: t -*-

;;; Commentary:
;; Run all tests for the Tibetan CAT system.
;; Usage from command line:
;;   emacs -batch -l run-all-tests.el -f ert-run-tests-batch-and-exit
;;
;; Or interactively:
;;   M-x load-file RET run-all-tests.el RET
;;   M-x ert RET t RET

;;; Code:

;; Setup load path
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path base-dir)
  (add-to-list 'load-path (expand-file-name ".." base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir))
  (add-to-list 'load-path (expand-file-name "../workspace" base-dir))
  (add-to-list 'load-path (expand-file-name "../philology" base-dir))
  (add-to-list 'load-path (expand-file-name "../doc-prep" base-dir))
  (add-to-list 'load-path (expand-file-name "../config" base-dir)))

;; Required packages
(require 'ert)
(require 'org)

;; Load all test files
(require 'tibetan-utils-test)
(require 'tibetan-verb-classifier-test)
(require 'tibetan-translation-engine-test)
(require 'tibetan-doc-display-test)

;; Load additional test files if they exist
(condition-case nil (require 'tibetan-compound-analysis-test) (error nil))
(condition-case nil (require 'tibetan-doc-prep-test) (error nil))
(condition-case nil (require 'tibetan-org-structure-test) (error nil))
(condition-case nil (require 'tibetan-clause-analysis-test) (error nil))
(condition-case nil (require 'tibetan-sentence-detection-test) (error nil))
(condition-case nil (require 'tibetan-auto-analysis-test) (error nil))
(condition-case nil (require 'tibetan-structure-reorg-test) (error nil))
(condition-case nil (require 'tibetan-keybindings-test) (error nil))

(provide 'run-all-tests)
;;; run-all-tests.el ends here
