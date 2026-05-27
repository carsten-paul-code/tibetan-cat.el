;;; tibetan-doc-prep-init.el --- Initialize document preparation module -*- lexical-binding: t -*-

;;; Commentary:
;; Loads all doc-prep modules and sets up keybindings.
;;
;; Usage in init.el:
;;   (add-to-list 'load-path "~/emacs-tibetan-cat/doc-prep/")
;;   (require 'tibetan-doc-prep-init)
;;
;; Or load individually:
;;   (require 'tibetan-doc-prep)  ; Just the wizard

;;; Code:

;; ============================================================================
;; LOAD PATH
;; ============================================================================

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path dir))

;; ============================================================================
;; LOAD MODULES
;; ============================================================================

;; Core modules (always needed)
(require 'tibetan-doc-format)
(require 'tibetan-ocr-validate)

;; Populated by the bundled glossary loader — declared so byte-compile
;; doesn't warn when we reach the status function below before the
;; glossary module has had a chance to define it.
(defvar tibetan-comprehensive-vocabulary)

;; AI correction (requires gptel)
(require 'tibetan-ocr-correct)

;; OCR runner (optional, requires BDRC OCR app)
(require 'tibetan-ocr-runner)

;; Main orchestration
(require 'tibetan-doc-prep)

;; §5.27 Phase 6/7:  unified Tibetan document-preparation wizard.
;; Autoload the wizard module + its dependencies (genre taxonomy,
;; async Claude pre-fill, Wylie ingest wrapper) so `C-c o d' fires
;; without an explicit require on the user's part.
(autoload 'tibetan-document-prep-wizard
  "tibetan-document-prep-wizard"
  "Unified Tibetan document-preparation wizard (§5.27)."
  t)
(autoload 'tibetan-document-prep-apply-claude-suggestions
  "tibetan-document-prep-claude"
  "Apply the cached Claude metadata suggestions to the current buffer."
  t)
(autoload 'tibetan-wylie-ingest-file
  "tibetan-wylie-ingest"
  "Convert a Wylie source file to Tibetan Unicode via pyewts."
  t)
(autoload 'tibetan-wylie-ingest-validate-input-interactive
  "tibetan-wylie-ingest"
  "Show paragraph/segment counts + character warnings for a Wylie source."
  t)

;; ============================================================================
;; STATUS MESSAGE
;; ============================================================================

(defun tibetan-doc-prep-init-status ()
  "Show status of doc-prep module components."
  (interactive)
  (let ((gptel-ok (and (featurep 'gptel)
                      (boundp 'gptel-api-key)
                      gptel-api-key))
        (ocr-ok (tibetan-ocr-available-p))
        (vocab-ok (and (boundp 'tibetan-comprehensive-vocabulary)
                      tibetan-comprehensive-vocabulary
                      (> (hash-table-count tibetan-comprehensive-vocabulary) 0))))

    (message "Tibetan Doc-Prep Status:
  Formatting:    OK
  Validation:    %s (%s vocabulary entries)
  AI Correction: %s
  BDRC OCR:      %s

Commands:
  C-c o d  Unified document wizard (§5.27 — Wylie/Tibetan/OCR + metadata)
  C-c o D  Apply cached Claude metadata suggestions
  C-c o y  Wylie ingest (C-u → in-place + relocate)
  C-c o Y  Wylie ingest — validate only
  C-c o o  OCR / Format wizard (legacy, subsumed by `d')
  C-c o v  Validate buffer
  C-c o c  AI correct buffer
  C-c o f  Format buffer to org"
             (if vocab-ok "OK" "Limited (load glossaries)")
             (if vocab-ok
                 (number-to-string (hash-table-count tibetan-comprehensive-vocabulary))
               "0")
             (if gptel-ok "OK" "Not configured (set up gptel)")
             (if ocr-ok "OK" "Not installed (optional)"))))

;; ============================================================================
;; AUTO-LOAD GLOSSARIES IF AVAILABLE
;; ============================================================================

(defun tibetan-doc-prep-init--load-glossaries ()
  "Load comprehensive glossaries if available."
  (let ((glossary-loader "~/buddhist-studies/translation-tools/load-comprehensive-glossaries.el"))
    (when (file-exists-p glossary-loader)
      (condition-case err
          (progn
            (load-file glossary-loader)
            (message "Doc-prep: Loaded comprehensive glossaries"))
        (error
         (message "Doc-prep: Could not load glossaries: %s" (error-message-string err)))))))

;; Load glossaries on init
(tibetan-doc-prep-init--load-glossaries)

;; ============================================================================
;; INITIALIZATION MESSAGE
;; ============================================================================

(message "Tibetan Doc-Prep loaded. Use C-c o d for the unified wizard \
(§5.27), C-c o o for the legacy OCR wizard, M-x tibetan-doc-prep-init-status \
for status.")

(provide 'tibetan-doc-prep-init)
;;; tibetan-doc-prep-init.el ends here
