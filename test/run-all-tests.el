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

;; Hermetic test run — no live network.  Several file-creating tests
;; reach analysis create/open paths that auto-fire a DharmaMitra
;; translation, and the mitra check-status test probes a local Ollama
;; server; both issued real HTTP requests during `make test-quick'
;; (violating "tests run without side effects" — the mitra test even
;; claims "no network call" in its docstring).  Override the synchronous
;; fetch with a stub that returns a minimal empty-body HTTP buffer, so
;; every code path that reaches the network is fed a benign response.
;; This sits BELOW --http-post / --url-retrieve, so those real functions
;; (and their gnutls-verify-error bindings) still run; the TLS-
;; enforcement specs override url-retrieve-synchronously via cl-letf,
;; which shadows this advice cleanly.  The tibetan-auto-fire-*-on-create
;; defcustom DEFAULTS are deliberately left at t (dedicated tests assert
;; that), since gating here is at the transport layer instead.
(advice-add 'url-retrieve-synchronously :override
            (lambda (&rest _)
              (let ((buf (generate-new-buffer " *tibetan-test-no-network*")))
                (with-current-buffer buf (insert "HTTP/1.1 200 OK\n\n"))
                buf))
            '((name . tibetan-test-no-network)))

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
(condition-case nil (require 'tibetan-phonetics-test) (error nil))
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

;; Thesaurus (Pass 5b) — Kramer-seeded user-editable glossary at rank 1
(condition-case nil (require 'tibetan-thesaurus-test) (error nil))

;; Zettel-in-translation-workflow (Phase 1, 2026-04-24) — index +
;; reader over the post-reorg knowledge/zettelkasten/.  Succeeds
;; `tibetan-thesaurus-test'; they coexist through Phase 6's
;; migration and then the thesaurus tests retire.
(condition-case nil (require 'tibetan-zettel-test) (error nil))

;; Sanskrit-parallel reading workflow (Phase 1, 2026-04-27) — walker
;; that extracts the `**** Sanskrit' sibling next to a `**** Segment',
;; plus the `#+SOURCE_MODE: parallel-sanskrit' source-mode predicate.
;; Read-only foundation for the Yogācārabhūmi parallel reading
;; workflow (Sanskrit primary, Tibetan secondary).
(condition-case nil (require 'tibetan-sanskrit-parallel-test) (error nil))

;; DharmaMitra HTTP client (Phase 1 of dharmamitra-realign workflow,
;; 2026-04-27): SSE parser, request builders, in-memory cache, error
;; handling.  Stubs HTTP so tests run without network.
(condition-case nil (require 'tibetan-dharmamitra-api-test) (error nil))

;; DharmaMitra alignment orchestrator (Phase 2, 2026-04-27): per-segment
;; candidate lookup via translate → search.  Stubs both API functions.
(condition-case nil (require 'tibetan-sanskrit-parallel-dharmamitra-test) (error nil))

;; DharmaMitra as a translator alongside Claude (Phase A.1 of
;; multi-translator-parallel-reading, 2026-04-30): per-segment
;; `** DharmaMitra Translation (Tibetan)' section in analysis files.
(condition-case nil (require 'tibetan-dharmamitra-translation-test) (error nil))

;; Source-aware Claude prompt (reads #+TIBETAN_CLAUDE_CONTEXT: and friends)
(condition-case nil (require 'tibetan-analysis-claude-prompt-test) (error nil))

;; Three-section Claude integration (Translation / Grammar / Context)
(condition-case nil (require 'tibetan-analysis-claude-sections-test) (error nil))

;; Sanskrit-side Claude pipeline (Phase 2 of two-language-parallel-analysis)
(condition-case nil (require 'tibetan-analysis-sanskrit-test) (error nil))

;; Combined-synthesis Claude pipeline (Phase 4 of two-language-parallel-analysis)
(condition-case nil (require 'tibetan-analysis-combined-test) (error nil))

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

;; Glossary loader (data/ directory — canonical bundled module)
(condition-case nil (require 'tibetan-glossary-loader-test) (error nil))

;; Input-text filter (drops English descriptions / # comments / blank
;; lines before Wylie conversion and parser tokenisation).
(condition-case nil (require 'tibetan-analysis-filter-test) (error nil))

;; Auto-content reorder (priority section order + Claude Grammar promotion)
(condition-case nil (require 'tibetan-analysis-reorder-test) (error nil))

;; Combined document builder (C-c u C) — per-segment blocks + dedup appendix
(condition-case nil (require 'tibetan-analysis-combine-test) (error nil))

;; CAT → Zettel bridge: open the zettel for the word at point, optionally
;; routed via emacsclient to the research Emacs instance.
(condition-case nil (require 'tibetan-cat-zettel-bridge-test) (error nil))

;; §5.27 Phase 2:  Wylie ingest wrapper around `tibetan-ybh-prep.py'.
(condition-case nil (require 'tibetan-wylie-ingest-test) (error nil))

;; §5.27 Phase 3:  canonical Tibetan-text genre taxonomy + reader.
(condition-case nil (require 'tibetan-document-genres-test) (error nil))

;; §5.27 Phase 4:  async Claude metadata pre-fill for the wizard.
(condition-case nil (require 'tibetan-document-prep-claude-test) (error nil))

;; §5.27 Phase 6:  unified document-preparation wizard orchestrator.
(condition-case nil (require 'tibetan-document-prep-wizard-test) (error nil))

;; ---------------------------------------------------------------------------
;; Visibility guard for the silent `(condition-case nil … (error nil))'
;; pattern above.  That pattern lets a test file that fails to compile /
;; load drop out INVISIBLY while the suite still reports green (and a
;; file on disk that nobody `require'd never runs at all).  Re-attempt
;; every `*-test.el' in this directory that is not yet a loaded feature
;; and LOG loudly why it didn't load, so a broken / unwired test file is
;; visible in batch output instead of silently vanishing.
(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (dolist (f (directory-files test-dir nil "-test\\.el\\'"))
    (let ((feature (intern (file-name-sans-extension f))))
      (unless (featurep feature)
        (condition-case err
            (require feature)
          (error
           (message "WARNING: test file %s did not load (tests SKIPPED): %s"
                    f (error-message-string err))))))))

(provide 'run-all-tests)
;;; run-all-tests.el ends here
