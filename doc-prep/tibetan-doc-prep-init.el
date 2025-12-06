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

;; AI correction (requires gptel)
(require 'tibetan-ocr-correct)

;; OCR runner (optional, requires BDRC OCR app)
(require 'tibetan-ocr-runner)

;; Main orchestration
(require 'tibetan-doc-prep)

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
  C-c o o  Full wizard
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

(message "Tibetan Doc-Prep loaded. Use C-c o o for wizard, M-x tibetan-doc-prep-init-status for status.")

(provide 'tibetan-doc-prep-init)
;;; tibetan-doc-prep-init.el ends here
