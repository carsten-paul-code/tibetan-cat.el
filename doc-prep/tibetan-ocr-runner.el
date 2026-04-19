;;; tibetan-ocr-runner.el --- BDRC OCR integration -*- lexical-binding: t -*-

;;; Commentary:
;; Integrates BDRC Tibetan OCR application with Emacs.
;;
;; Prerequisites:
;; - BDRC OCR App: https://github.com/buda-base/tibetan-ocr-app
;; - macOS: /Applications/BDRC Tibetan OCR.app
;;
;; Available OCR models:
;; - Woodblock: Traditional woodblock prints (most common)
;; - Woodblock-Stacks: Woodblock with complex stacking
;; - Modern: Modern printed texts
;; - Ume_Druma: dbu-med cursive script
;; - Ume_Petsuk: dbu-med petsuk style
;;
;; The macOS app is GUI-based. This module provides:
;; 1. Launch the app with a file pre-loaded
;; 2. Import OCR results after processing
;; 3. Manual text input fallback
;;
;; Usage:
;;   M-x tibetan-ocr-open-app      ; Launch app
;;   M-x tibetan-ocr-import-result ; Import after OCR
;;   M-x tibetan-ocr-workflow      ; Guided workflow

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-ocr-runner nil
  "BDRC OCR runner settings."
  :group 'tibetan-doc-prep
  :prefix "tibetan-ocr-")

(defcustom tibetan-ocr-app-path "/Applications/BDRC Tibetan OCR.app"
  "Path to BDRC OCR application.
On macOS this is the .app bundle."
  :type 'file
  :group 'tibetan-ocr-runner)

;; ============================================================================
;; APP DETECTION
;; ============================================================================

(defconst tibetan-ocr--macos-app-paths
  '("/Applications/BDRC Tibetan OCR.app"
    "~/Applications/BDRC Tibetan OCR.app")
  "Common macOS app locations for BDRC OCR.")

(defun tibetan-ocr--find-app ()
  "Find BDRC OCR application."
  (or (and tibetan-ocr-app-path
           (file-exists-p tibetan-ocr-app-path)
           tibetan-ocr-app-path)
      (cl-loop for path in tibetan-ocr--macos-app-paths
               for expanded = (expand-file-name path)
               when (file-exists-p expanded)
               return expanded)))

(defun tibetan-ocr--get-models-dir ()
  "Get path to OCR models directory."
  (let ((app (tibetan-ocr--find-app)))
    (when app
      (expand-file-name "Contents/MacOS/OCRModels" app))))

;; ============================================================================
;; MODEL MAPPING
;; ============================================================================

(defconst tibetan-ocr--model-names
  '((woodblock . "Woodblock")
    (woodblock-stacks . "Woodblock-Stacks")
    (modern . "Modern")
    (ume-druma . "Ume_Druma")
    (ume-petsuk . "Ume_Petsuk")
    ;; Aliases
    (pecha . "Woodblock")
    (manuscript . "Ume_Druma")
    (dbumed . "Ume_Druma"))
  "Mapping of model symbols to BDRC OCR model directory names.")

(defun tibetan-ocr--model-name (model)
  "Get OCR model directory name for MODEL symbol."
  (or (cdr (assq model tibetan-ocr--model-names))
      "Woodblock"))

;; ============================================================================
;; STATUS CHECK
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-available-p ()
  "Check if BDRC OCR is installed and available."
  (not (null (tibetan-ocr--find-app))))

;;;###autoload
(defun tibetan-ocr-status ()
  "Show BDRC OCR installation status."
  (interactive)
  (let ((app-path (tibetan-ocr--find-app))
        (models-dir (tibetan-ocr--get-models-dir)))
    (if app-path
        (let ((models (when (and models-dir (file-directory-p models-dir))
                       (directory-files models-dir nil "^[^.]"))))
          (message "BDRC OCR found:
  App: %s
  Models: %s
  Available: %s"
                   app-path
                   (or models-dir "not found")
                   (if models (mapconcat #'identity models ", ") "none")))
      (message "BDRC OCR not found. Please install from:
https://github.com/buda-base/tibetan-ocr-app/releases"))))

;; ============================================================================
;; LAUNCH APP
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-open-app (&optional file)
  "Open BDRC Tibetan OCR app, optionally with FILE.
If FILE is provided, the app opens with that file ready for OCR."
  (interactive
   (list (when current-prefix-arg
           (read-file-name "Open with file: " nil nil t))))
  (let ((app (tibetan-ocr--find-app)))
    (unless app
      (user-error "BDRC OCR app not found. Install from: https://github.com/buda-base/tibetan-ocr-app/releases"))
    (if file
        (shell-command (format "open -a %s %s"
                              (shell-quote-argument app)
                              (shell-quote-argument (expand-file-name file))))
      (shell-command (format "open -a %s" (shell-quote-argument app))))
    (message "BDRC Tibetan OCR app launched%s"
             (if file (format " with %s" (file-name-nondirectory file)) ""))))

;; ============================================================================
;; IMPORT RESULTS
;; ============================================================================

(defvar tibetan-ocr--last-source nil
  "Last source file processed.")

;;;###autoload
(defun tibetan-ocr-import-from-file (file)
  "Import OCR results from FILE (text file exported from BDRC OCR)."
  (interactive "fSelect OCR output file: ")
  (let ((text (with-temp-buffer
               (insert-file-contents file)
               (buffer-string))))
    (list :text text
          :source file
          :model 'imported)))

;;;###autoload
(defun tibetan-ocr-import-from-clipboard ()
  "Import OCR results from clipboard.
Use this after copying text from BDRC OCR app."
  (interactive)
  (let ((text (gui-get-selection 'CLIPBOARD 'STRING)))
    (if (and text (not (string-empty-p text)))
        (progn
          (with-current-buffer (get-buffer-create "*Tibetan OCR Import*")
            (erase-buffer)
            (insert "# Imported OCR Text\n\n")
            (insert text)
            (goto-char (point-min))
            (when (fboundp 'org-mode)
              (org-mode)))
          (pop-to-buffer "*Tibetan OCR Import*")
          (list :text text
                :source "clipboard"
                :model 'imported))
      (user-error "No text in clipboard"))))

;;;###autoload
(defun tibetan-ocr-import-from-buffer ()
  "Import OCR text from current buffer or region."
  (interactive)
  (let ((text (if (use-region-p)
                 (buffer-substring-no-properties (region-beginning) (region-end))
               (buffer-substring-no-properties (point-min) (point-max)))))
    (list :text text
          :source (or buffer-file-name "buffer")
          :model 'imported)))

;; ============================================================================
;; GUIDED WORKFLOW
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-workflow (&optional source-file)
  "Guided workflow for OCR processing.
1. Opens BDRC OCR app with SOURCE-FILE
2. Waits for user to process in app
3. Imports results

Returns OCR result plist."
  (interactive
   (list (read-file-name "Select PDF or image for OCR: " nil nil t)))

  (let ((app (tibetan-ocr--find-app)))
    (unless app
      (user-error "BDRC OCR app not found"))

    ;; Store source for reference
    (setq tibetan-ocr--last-source source-file)

    ;; Open app with file
    (tibetan-ocr-open-app source-file)

    ;; Show instructions
    (with-current-buffer (get-buffer-create "*Tibetan OCR Workflow*")
      (erase-buffer)
      (insert "# Tibetan OCR Workflow\n\n")
      (insert (format "Source: %s\n\n" source-file))
      (insert "## Instructions\n\n")
      (insert "1. The BDRC Tibetan OCR app has been opened\n")
      (insert "2. Select the appropriate OCR model:\n")
      (insert "   - Woodblock: for traditional woodblock prints\n")
      (insert "   - Woodblock-Stacks: for complex stacking\n")
      (insert "   - Modern: for modern printed texts\n")
      (insert "   - Ume_Druma/Ume_Petsuk: for dbu-med manuscripts\n")
      (insert "3. Run OCR in the app\n")
      (insert "4. Copy the result text (Cmd+A, Cmd+C)\n")
      (insert "5. Return here and run one of:\n\n")
      (insert "   M-x tibetan-ocr-import-from-clipboard\n")
      (insert "   M-x tibetan-ocr-import-from-file\n")
      (insert "\n## Quick Keys\n\n")
      (insert "After OCR, press:\n")
      (insert "  C-c o i c  - Import from clipboard\n")
      (insert "  C-c o i f  - Import from file\n")
      (goto-char (point-min))
      (when (fboundp 'org-mode)
        (org-mode)))
    (pop-to-buffer "*Tibetan OCR Workflow*")

    ;; Return nil for now - user will call import function
    nil))

;; ============================================================================
;; COMBINED RUN FUNCTION (for doc-prep integration)
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-run (source &optional _model)
  "Process SOURCE through BDRC OCR.
MODEL is currently ignored (user selects in GUI app).
For GUI app, this launches the workflow and prompts for import.
Returns plist: (:text \"...\" :source \"...\" :model ...)"
  (interactive
   (list (read-file-name "Select PDF or image: " nil nil t)
         nil))

  (unless (tibetan-ocr-available-p)
    (user-error "BDRC OCR not installed. See M-x tibetan-ocr-status"))

  ;; Open app with file
  (tibetan-ocr-open-app source)
  (setq tibetan-ocr--last-source source)

  ;; Prompt user to process and import
  (let ((action (completing-read
                "After OCR completes, import from: "
                '("clipboard (copy from app first)"
                  "file (export from app first)"
                  "cancel")
                nil t)))
    (cond
     ((string-prefix-p "clipboard" action)
      (read-string "Press Enter after copying OCR result from app...")
      (tibetan-ocr-import-from-clipboard))
     ((string-prefix-p "file" action)
      (let ((file (read-file-name "Select exported OCR file: ")))
        (tibetan-ocr-import-from-file file)))
     (t
      (user-error "OCR cancelled")))))

;; ============================================================================
;; FALLBACK: MANUAL TEXT INPUT
;; ============================================================================

;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(defvar tibetan-ocr-import-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'tibetan-ocr-import-from-clipboard)
    (define-key map (kbd "f") #'tibetan-ocr-import-from-file)
    (define-key map (kbd "b") #'tibetan-ocr-import-from-buffer)
    map)
  "Keymap for OCR import commands (C-c o i prefix).")

;; These will be integrated into tibetan-doc-prep-map
;; C-c o r - OCR run/workflow
;; C-c o a - Open app
;; C-c o i - Import prefix

(provide 'tibetan-ocr-runner)
;;; tibetan-ocr-runner.el ends here
