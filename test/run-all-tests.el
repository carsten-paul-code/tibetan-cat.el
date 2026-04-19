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

;; Skip slow external glossary loading during tests
(defvar tibetan-skip-external-glossaries t
  "When non-nil, skip loading external glossaries during tests.")

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
(condition-case nil (require 'tibetan-menu-test) (error nil))
(condition-case nil (require 'tibetan-vocabulary-test) (error nil))
(condition-case nil (require 'tibetan-analysis-persist-test) (error nil))

;; New tests added for open source release
(condition-case nil (require 'tibetan-wylie-test) (error nil))
(condition-case nil (require 'tibetan-text-classifier-test) (error nil))
(condition-case nil (require 'tibetan-sentence-workspace-test) (error nil))
(condition-case nil (require 'tibetan-verse-philology-test) (error nil))
(condition-case nil (require 'tibetan-madhyamaka-terms-test) (error nil))

;; Doc-prep module tests
(condition-case nil (require 'tibetan-doc-format-test) (error nil))
(condition-case nil (require 'tibetan-ocr-runner-test) (error nil))
(condition-case nil (require 'tibetan-ocr-correct-test) (error nil))

;; New test files for untested public functions
(condition-case nil (require 'tibetan-particles-bialek-test) (error nil))
(condition-case nil (require 'tibetan-enhanced-display-test) (error nil))
(condition-case nil (require 'tibetan-vocabulary-detailed-test) (error nil))
(condition-case nil (require 'tibetan-sentence-structure-test) (error nil))
(condition-case nil (require 'tibetan-particles-test) (error nil))
(condition-case nil (require 'tibetan-translation-suggest-test) (error nil))

;; Analysis module tests for untested public functions
(condition-case nil (require 'tibetan-classroom-test) (error nil))
(condition-case nil (require 'tibetan-enhanced-parser-test) (error nil))
(condition-case nil (require 'tibetan-mitra-translation-test) (error nil))

;; Round-1 regression suite for verb extraction (seg-007/011/012/013)
(condition-case nil (require 'tibetan-round1-verb-extraction-test) (error nil))

;; Round-2 regression suite for clause segmentation / NP chunking /
;; argument structure
(condition-case nil (require 'tibetan-round2-clause-segmenter-test) (error nil))

;; Batch reanalysis (preserves user notes + Claude translation)
(condition-case nil (require 'tibetan-batch-reanalyze-test) (error nil))

;; Steinert SQLite dictionary integration (tests auto-skip if DB missing)
(condition-case nil (require 'tibetan-steinert-test) (error nil))

;; Multi-source Detailed Dictionary rendering
(condition-case nil (require 'tibetan-vocab-multisource-test) (error nil))

;; Source-aware Claude prompt (reads #+TIBETAN_CLAUDE_CONTEXT: and friends)
(condition-case nil (require 'tibetan-analysis-claude-prompt-test) (error nil))

;; Three-section Claude integration (Translation / Grammar / Context)
(condition-case nil (require 'tibetan-analysis-claude-sections-test) (error nil))

;; Inline segment → Org heading migration
(condition-case nil (require 'tibetan-segment-migrate-test) (error nil))

;; Interlinear gloss + particle overview
(condition-case nil (require 'tibetan-interlinear-test) (error nil))

;; Throttled Claude request queue (concurrency cap + 429 retry)
(condition-case nil (require 'tibetan-claude-queue-test) (error nil))

;; Persistent sentence-level analysis (C-c s A / C-c s R / C-c s r)
(condition-case nil (require 'tibetan-sentence-persist-test) (error nil))

;; Tigress-story regressions (MWU over-match, non-final terminative ר)
(condition-case nil (require 'tibetan-tigress-regressions-test) (error nil))

(provide 'run-all-tests)
;;; run-all-tests.el ends here
