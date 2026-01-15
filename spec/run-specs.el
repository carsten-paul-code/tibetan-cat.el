;;; run-specs.el --- Load and run all BDD specs -*- lexical-binding: t -*-

;;; Commentary:
;; Loads all spec suites and runs them.
;; Called by run-specs.sh for command-line execution.

;;; Code:

;; Add paths and set data directory
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir))
  (add-to-list 'load-path (expand-file-name "../config" base-dir))
  (add-to-list 'load-path base-dir)
  (add-to-list 'load-path (expand-file-name "suites" base-dir))

  ;; Set data directory before loading modules that need it
  (setq tibetan-cat-data-dir (expand-file-name ".." base-dir)))

;; Define variable if not already defined
(defvar tibetan-cat-data-dir nil
  "Directory containing Tibetan CAT data files.")

;; Load core modules (only those needed for specs)
(require 'tibetan-wylie nil t)
(require 'tibetan-utils nil t)
(require 'tibetan-vocabulary nil t)
(require 'tibetan-verb-classifier nil t)
(require 'tibetan-enhanced-parser nil t)  ; For compound recognition
(require 'tibetan-particles-bialek nil t) ; For Bialek particle analysis
(require 'tibetan-org-structure nil t)    ; For document preparation
;; Skip heavy modules - test via individual functions
(require 'tibetan-analysis-persist nil t)
(require 'tibetan-compound-analysis nil t)
(require 'tibetan-translation-engine nil t)
(require 'tibetan-classroom nil t)  ; For auto-analysis mode
(require 'tibetan-mitra-translation nil t)  ; For Mitra AI translation
(require 'tibetan-clause-analysis nil t)    ; For clause analysis
(require 'tibetan-auto-analysis nil t)       ; For auto-analysis batch processing
(require 'tibetan-structure-reorg nil t)     ; For structure reorganization

;; Load BDD framework
(require 'tibetan-bdd)

;; Load all spec suites
(require 'verb-detection-spec)
(require 'particle-analysis-spec)
(require 'segment-analysis-spec)
(require 'cat-translation-spec)
(require 'compound-analysis-spec)
(require 'tigress-story-spec)
(require 'custom-vocab-spec)
(require 'mitra-translation-spec)
(require 'document-prep-spec)
(require 'clause-analysis-spec)
(require 'sentence-detection-spec)
(require 'auto-analysis-spec)
(require 'structure-reorg-spec)

;; Run specs when loaded in batch mode
(when noninteractive
  (setq debug-on-error t)
  (let ((results (tibetan-bdd-run-all)))
    (kill-emacs (tibetan-bdd-report results))))

(provide 'run-specs)
;;; run-specs.el ends here
