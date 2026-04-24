;;; tibetan-keybindings-test.el --- Tests for keybindings -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests to verify that keybindings are correctly set.

;;; Code:

(require 'ert)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../config" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

;; Load modules that set keybindings
(require 'tibetan-org-structure nil t)
(require 'tibetan-auto-analysis nil t)
(require 'tibetan-structure-reorg nil t)
;; Central binding surface (moved 2026-04-24 — needed for the
;; `no-uc-clash' / `claude-fire' / `combine-stays' tests below).
(require 'tibetan-analysis-persist nil t)
(require 'tibetan-analysis-combine nil t)
(require 'tibetan-keybindings nil t)

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

(ert-deftest tibetan-keybinding-batch-reanalyze ()
  "Test that C-c u r is bound to tibetan-analysis-batch-reanalyze."
  (require 'tibetan-analysis-persist nil t)
  (require 'tibetan-keybindings nil t)
  (skip-unless (fboundp 'tibetan-analysis-batch-reanalyze))
  (should (eq (key-binding (kbd "C-c u r"))
              'tibetan-analysis-batch-reanalyze)))

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
;; TEXT SCALE ADJUSTMENT TESTS
;; ============================================================================

(ert-deftest tibetan-increase-text-scale-increments-correctly ()
  "Test that tibetan-increase-text-scale increments the scale factor by 0.1."
  (skip-unless (fboundp 'tibetan-increase-text-scale))
  (skip-unless (fboundp 'tibetan-set-text-scale))
  ;; Set initial scale factor
  (let ((initial-scale 1.4))
    ;; Save original scale
    (let ((original (or tibetan-text-scale-factor 1.4)))
      (tibetan-set-text-scale initial-scale)
      (tibetan-increase-text-scale)
      ;; After increase, scale should be initial + 0.1
      (should (and tibetan-text-scale-factor
                   (>= tibetan-text-scale-factor (+ initial-scale 0.08))))
      (should (and tibetan-text-scale-factor
                   (<= tibetan-text-scale-factor (+ initial-scale 0.12))))
      ;; Restore
      (tibetan-set-text-scale original))))

(ert-deftest tibetan-decrease-text-scale-decrements-correctly ()
  "Test that tibetan-decrease-text-scale decrements scale factor by 0.1 with min 1.0."
  (skip-unless (fboundp 'tibetan-decrease-text-scale))
  (skip-unless (fboundp 'tibetan-set-text-scale))
  ;; Test normal decrement
  (let ((initial-scale 1.5))
    (let ((original (or tibetan-text-scale-factor 1.4)))
      (tibetan-set-text-scale initial-scale)
      (tibetan-decrease-text-scale)
      ;; After decrease, scale should be initial - 0.1
      (should (and tibetan-text-scale-factor
                   (>= tibetan-text-scale-factor (- initial-scale 0.12))))
      (should (and tibetan-text-scale-factor
                   (<= tibetan-text-scale-factor (- initial-scale 0.08))))
      ;; Test minimum boundary (at 1.0)
      (tibetan-set-text-scale 1.05)
      (tibetan-decrease-text-scale)
      ;; Should not go below 1.0
      (should (and tibetan-text-scale-factor
                   (>= tibetan-text-scale-factor 1.0)))
      ;; Restore
      (tibetan-set-text-scale original))))

;; ============================================================================
;; HELPER
;; ============================================================================

;; ============================================================================
;; Binding placement (2026-04-24)
;;
;; `tibetan-auto-request-claude-translations' was silently un-bound in
;; practice because its module-level `(global-set-key "C-c u C" ...)'
;; was clobbered by `config/tibetan-keybindings.el's `C-c u C' →
;; `tibetan-analysis-combine-document' (loaded later).  Surfaced by
;; Carsten on 2026-04-24 when Claude didn't fly in on seg-016.  The
;; module-level binding was removed and the command rebound to
;; `C-c u F' in the central config.  These tests pin the result:
;;   - `C-c u F' fires Claude for placeholders.
;;   - `C-c u C' builds the combined document.
;;   - No two `C-c u X' slots share a command (anti-clobber).
;; ============================================================================

(ert-deftest tibetan-keybinding-claude-fire-bound-to-F ()
  "`C-c u F' must invoke `tibetan-auto-request-claude-translations'."
  (should (eq (key-binding (kbd "C-c u F"))
              'tibetan-auto-request-claude-translations)))

(ert-deftest tibetan-keybinding-combine-stays-on-C ()
  "`C-c u C' must invoke `tibetan-analysis-combine-document'.  If this
flips back to claude-request-translations, the module-level
`global-set-key' has crept back into a module file — check and
remove it."
  (should (eq (key-binding (kbd "C-c u C"))
              'tibetan-analysis-combine-document)))

;; Note: no runtime test can detect binding CLOBBERS — `key-binding'
;; returns only the final winner.  The original bug (`C-c u C' set by
;; two modules, one clobbering the other) is best guarded by keeping
;; all `global-set-key' calls in `config/tibetan-keybindings.el' (the
;; single central surface) and doing grep-scans during code review.
;; The two specific assertions above catch the observed regression:
;; if either Claude-fire or combine flips to `nil' / the wrong command,
;; something has rebound it behind the config file's back.

(defun tibetan-keybindings-run-tests ()
  "Run all keybinding tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-keybinding-\\|^tibetan-function-\\|^tibetan-increase-\\|^tibetan-decrease-"))

(provide 'tibetan-keybindings-test)
;;; tibetan-keybindings-test.el ends here
