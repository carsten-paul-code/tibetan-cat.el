;;; tibetan-doc-prep.el --- Document preparation pipeline for Tibetan texts -*- lexical-binding: t -*-

;;; Commentary:
;; Master orchestration module for Tibetan document preparation.
;; Provides a wizard that guides through:
;;   1. OCR (via BDRC OCR)
;;   2. Dictionary validation
;;   3. AI correction (via Claude/gptel)
;;   4. Document formatting (org-mode)
;;
;; Usage:
;;   M-x tibetan-doc-prep-wizard    ; Full interactive wizard
;;   C-c o o                        ; Same (when cat-mode active)
;;
;; Individual steps available via C-c o prefix.

;;; Code:

(require 'cl-lib)
(require 'tibetan-document-genres)  ; §5.27 Phase 3:  canonical genre list

;; External variable from cat-mode
(defvar cat-mode-map nil "Keymap for cat-mode (declared for byte-compiler).")

;; Declare external OCR functions
(declare-function tibetan-ocr-open-app "tibetan-ocr-runner" (&optional file))
(declare-function tibetan-ocr-workflow "tibetan-ocr-runner" (&optional source-file))
(declare-function tibetan-ocr-status "tibetan-ocr-runner" ())
(declare-function tibetan-ocr-import-from-clipboard "tibetan-ocr-runner" ())
(declare-function tibetan-ocr-import-from-file "tibetan-ocr-runner" (file))
(declare-function tibetan-ocr-import-from-buffer "tibetan-ocr-runner" ())

;; §5.27 Phase 7:  autoloaded wizard + Wylie ingest commands bound
;; into `tibetan-doc-prep-map' under `C-c o d/D/y/Y'.  Registered as
;; `autoload's (not `declare-function's) so `fboundp' returns t and
;; the menu's `:active' predicate accepts them BEFORE the user
;; touches any wizard command — `tibetan-doc-prep' is loaded by
;; `tibetan-cat.el', so anything wired here is reachable.
(autoload 'tibetan-document-prep-wizard
  "tibetan-document-prep-wizard"
  "Unified Tibetan document-preparation wizard (§5.27)." t)
(autoload 'tibetan-document-prep-apply-claude-suggestions
  "tibetan-document-prep-claude"
  "Apply the cached Claude metadata suggestions to the current buffer." t)
(autoload 'tibetan-wylie-ingest-file
  "tibetan-wylie-ingest"
  "Convert a Wylie source file to Tibetan Unicode via pyewts." t)
(autoload 'tibetan-wylie-ingest-validate-input-interactive
  "tibetan-wylie-ingest"
  "Show paragraph/segment counts + character warnings for a Wylie source."
  t)

;; ============================================================================
;; CUSTOMIZATION
;; ============================================================================

(defgroup tibetan-doc-prep nil
  "Tibetan document preparation pipeline."
  :group 'tibetan-cat
  :prefix "tibetan-doc-prep-")

(defcustom tibetan-doc-prep-default-line-break 'shad
  "Default line break style for document formatting.
Options: `shad' (།), `double-shad' (༎), `preserve' (keep original)."
  :type '(choice (const :tag "Break at single shad (།)" shad)
                 (const :tag "Break at double shad (༎)" double-shad)
                 (const :tag "Preserve original breaks" preserve))
  :group 'tibetan-doc-prep)

(defcustom tibetan-doc-prep-default-segments t
  "Whether to add segment markers by default."
  :type 'boolean
  :group 'tibetan-doc-prep)

(defcustom tibetan-doc-prep-default-folio-style 'heading
  "Default style for folio markers.
Options: `heading' (* Folio 1a), `inline' ([F:1a]), `property' (drawer)."
  :type '(choice (const :tag "Org headings" heading)
                 (const :tag "Inline markers" inline)
                 (const :tag "Property drawers" property))
  :group 'tibetan-doc-prep)

(defcustom tibetan-doc-prep-default-text-type 'classical
  "Default text type for new documents."
  :type '(choice (const :tag "Classical prose" classical)
                 (const :tag "Madhyamaka verse" madhyamaka-verse)
                 (const :tag "Sutra" sutra)
                 (const :tag "Commentary" commentary))
  :group 'tibetan-doc-prep)

(defcustom tibetan-doc-prep-output-directory nil
  "Default output directory for prepared documents.
If nil, uses same directory as source file."
  :type '(choice (const :tag "Same as source" nil)
                 (directory :tag "Specific directory"))
  :group 'tibetan-doc-prep)

(defcustom tibetan-doc-prep-work-in-progress-folder "work in progress"
  "Sibling folder name that receives a freshly prepared source file.

§5.27 Phase 2 follow-up (2026-05-27):  after ingest (Wylie
conversion / OCR import / paste-in) the prepared `.org' file is
relocated UP one level into a sibling folder of this name so the
buddhist-studies workflow folders mirror the established Milarepa
pattern:

  <semester>/<class>/<raw-input>/foo.org       ←  source (ingest input)
  <semester>/<class>/work in progress/foo.org  ←  prepared file
  <semester>/<class>/work in progress/analysis/seg-NNN-foo.org

Set to nil to disable the post-ingest move entirely (the prepared
file then stays in its source directory).  An absolute path is
also accepted — when provided, the prepared file lands there
unconditionally instead of in a relative sibling of the source."
  :type '(choice (const :tag "Disabled — stay in source directory" nil)
                 (string :tag "Sibling folder name (relative)")
                 (directory :tag "Absolute target directory"))
  :group 'tibetan-doc-prep)

;; ============================================================================
;; PATH RELOCATION
;; ============================================================================

(defun tibetan-doc-prep--resolve-work-in-progress-target (source-path)
  "Return the absolute target path for SOURCE-PATH after relocation.

Consults `tibetan-doc-prep-work-in-progress-folder':
  · nil          → returns SOURCE-PATH unchanged (no move).
  · relative     → resolved as a sibling of the source's parent
                   directory:  `.../parent/<folder>/<basename>'.
  · absolute     → used directly as the destination directory.

The returned path is always absolute.  Does not create the
destination directory — the move helper does that."
  (let* ((source-abs (expand-file-name source-path))
         (basename (file-name-nondirectory source-abs))
         (folder tibetan-doc-prep-work-in-progress-folder))
    (cond
     ((null folder) source-abs)
     ((file-name-absolute-p folder)
      (expand-file-name basename folder))
     (t
      (let* ((src-dir (directory-file-name
                       (file-name-directory source-abs)))
             (parent (file-name-directory src-dir))
             (dest-dir (expand-file-name folder parent)))
        (expand-file-name basename dest-dir))))))

(defun tibetan-doc-prep-move-to-work-in-progress (source-path)
  "Relocate SOURCE-PATH into the configured work-in-progress folder.

Resolves the destination via
`tibetan-doc-prep--resolve-work-in-progress-target', creates the
destination directory if absent, and renames the file across.
Returns the new absolute path.

Idempotent:  when SOURCE-PATH already resides at the resolved
destination (or
`tibetan-doc-prep-work-in-progress-folder' is nil), the function
is a no-op and returns SOURCE-PATH unchanged.

Existing destination files are overwritten — callers (the wizard,
the Wylie ingest wrapper) confirm with the user before invoking."
  (unless (and source-path (file-exists-p source-path))
    (user-error "Source file not found:  %s" source-path))
  (let* ((source-abs (expand-file-name source-path))
         (target (tibetan-doc-prep--resolve-work-in-progress-target
                  source-abs)))
    (cond
     ;; No-op:  feature disabled or source already at target.
     ((or (null tibetan-doc-prep-work-in-progress-folder)
          (equal source-abs target))
      source-abs)
     (t
      (let ((dest-dir (file-name-directory target)))
        (unless (file-directory-p dest-dir)
          (make-directory dest-dir t))
        (rename-file source-abs target t)
        target)))))

;; ============================================================================
;; INTERNAL STATE
;; ============================================================================

(defvar tibetan-doc-prep--current-source nil
  "Current source file/text being processed.")

(defvar tibetan-doc-prep--raw-text nil
  "Raw OCR/input text.")

(defvar tibetan-doc-prep--validation-result nil
  "Result of dictionary validation.")

(defvar tibetan-doc-prep--corrected-text nil
  "AI-corrected text.")

;; ============================================================================
;; UTILITY FUNCTIONS
;; ============================================================================

(defun tibetan-doc-prep--select-from-list (prompt choices)
  "Display PROMPT and let user select from CHOICES.
CHOICES is alist of (display-string . value).
Returns selected value."
  (let* ((choice-strings (mapcar #'car choices))
         (selected (completing-read prompt choice-strings nil t)))
    (cdr (assoc selected choices))))

(defun tibetan-doc-prep--yes-or-no (prompt)
  "Ask yes/no question with PROMPT."
  (yes-or-no-p prompt))


;; ============================================================================
;; STEP 1: SOURCE SELECTION
;; ============================================================================

(defun tibetan-doc-prep--select-source ()
  "Interactive source selection.
Returns plist with :type and :path or :text."
  (let ((source-type
         (tibetan-doc-prep--select-from-list
          "Select source: "
          '(("PDF file" . pdf)
            ("Image file(s)" . image)
            ("Directory of images" . directory)
            ("Paste text / current buffer" . text)))))
    (pcase source-type
      ('pdf
       (list :type 'pdf
             :path (read-file-name "Select PDF: " nil nil t nil
                                   (lambda (f) (or (file-directory-p f)
                                                  (string-suffix-p ".pdf" f t))))))
      ('image
       (list :type 'image
             :path (read-file-name "Select image: " nil nil t)))
      ('directory
       (list :type 'directory
             :path (read-directory-name "Select directory: " nil nil t)))
      ('text
       (let ((use-buffer (tibetan-doc-prep--yes-or-no "Use current buffer/region? ")))
         (if use-buffer
             (list :type 'text
                   :text (if (use-region-p)
                            (buffer-substring-no-properties (region-beginning) (region-end))
                          (buffer-substring-no-properties (point-min) (point-max)))
                   :source-name (or buffer-file-name "buffer"))
           (list :type 'text
                 :text (read-string "Paste Tibetan text: ")
                 :source-name "pasted")))))))

;; ============================================================================
;; STEP 2: OCR
;; ============================================================================

(defun tibetan-doc-prep--get-ocr-text (source)
  "Get OCR text from SOURCE.
If source is already text, return it.
Otherwise, run BDRC OCR."
  (if (eq (plist-get source :type) 'text)
      ;; Already have text
      (progn
        (setq tibetan-doc-prep--raw-text (plist-get source :text))
        tibetan-doc-prep--raw-text)
    ;; Need to run OCR
    (if (fboundp 'tibetan-ocr-run)
        (let* ((model (tibetan-doc-prep--select-from-list
                       "Select OCR model: "
                       '(("Pecha (traditional woodblock)" . pecha)
                         ("Modern print" . modern)
                         ("Manuscript (dbu-med)" . manuscript))))
               (result (tibetan-ocr-run (plist-get source :path) model)))
          (setq tibetan-doc-prep--raw-text (plist-get result :text))
          tibetan-doc-prep--raw-text)
      ;; OCR module not loaded
      (if (tibetan-doc-prep--yes-or-no
           "OCR module not available. Paste text manually? ")
          (let ((text (read-string "Paste OCR'd text: ")))
            (setq tibetan-doc-prep--raw-text text)
            text)
        (user-error "OCR module (tibetan-ocr-runner) not loaded")))))

;; ============================================================================
;; STEP 3: VALIDATION
;; ============================================================================

(defun tibetan-doc-prep--validate-text (text)
  "Validate TEXT against dictionaries.
Returns validation result plist."
  (if (fboundp 'tibetan-ocr-validate-text)
      (let ((result (tibetan-ocr-validate-text text)))
        (setq tibetan-doc-prep--validation-result result)
        result)
    ;; Validation module not loaded - skip
    (message "Validation module not loaded, skipping...")
    (setq tibetan-doc-prep--validation-result
          '(:valid nil :unknown nil :suspicious nil :total 0 :skipped t))
    tibetan-doc-prep--validation-result))

;; ============================================================================
;; STEP 4: AI CORRECTION
;; ============================================================================

(defun tibetan-doc-prep--ai-correct (text validation)
  "Correct TEXT using Claude AI, informed by VALIDATION.
Returns corrected text."
  (let* ((unknown-count (length (plist-get validation :unknown)))
         (suspicious-count (length (plist-get validation :suspicious)))
         (total-issues (+ unknown-count suspicious-count)))

    (if (zerop total-issues)
        ;; No issues found
        (progn
          (message "No issues found - text appears clean!")
          (setq tibetan-doc-prep--corrected-text text)
          text)

      ;; Issues found - ask user
      (let ((action (tibetan-doc-prep--select-from-list
                     (format "Found %d unknown, %d suspicious syllables. Action: "
                             unknown-count suspicious-count)
                     '(("Auto-correct with Claude AI" . correct)
                       ("Review flagged items first" . review)
                       ("Skip AI correction" . skip)))))
        (pcase action
          ('correct
           (if (fboundp 'tibetan-ocr-correct)
               (let ((result (tibetan-ocr-correct text validation)))
                 (setq tibetan-doc-prep--corrected-text (plist-get result :text))
                 ;; Show diff if changes were made
                 (when (plist-get result :changes)
                   (tibetan-doc-prep--show-changes (plist-get result :changes)))
                 tibetan-doc-prep--corrected-text)
             (message "AI correction module not loaded, skipping...")
             (setq tibetan-doc-prep--corrected-text text)
             text))
          ('review
           (tibetan-doc-prep--review-flagged validation)
           ;; After review, ask again
           (tibetan-doc-prep--ai-correct text validation))
          ('skip
           (setq tibetan-doc-prep--corrected-text text)
           text))))))

(defun tibetan-doc-prep--review-flagged (validation)
  "Display flagged items from VALIDATION for review."
  (let ((buf (get-buffer-create "*Tibetan OCR Review*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "# Flagged Syllables for Review\n\n")
      (insert "## Unknown (not in dictionary)\n")
      (dolist (item (plist-get validation :unknown))
        (insert (format "- %s\n" item)))
      (insert "\n## Suspicious (possible OCR errors)\n")
      (dolist (item (plist-get validation :suspicious))
        (insert (format "- %s\n" item)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buf)
    (read-string "Press Enter when done reviewing...")))

(defun tibetan-doc-prep--show-changes (changes)
  "Display CHANGES made by AI correction."
  (let ((buf (get-buffer-create "*Tibetan OCR Changes*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "# AI Correction Changes\n\n")
      (dolist (change changes)
        (insert (format "- %s → %s: %s\n"
                       (plist-get change :original)
                       (plist-get change :corrected)
                       (or (plist-get change :reason) ""))))
      (goto-char (point-min))
      (org-mode))
    (display-buffer buf)))

;; ============================================================================
;; STEP 5: FORMAT DOCUMENT
;; ============================================================================

(defun tibetan-doc-prep--select-format-options ()
  "Interactive selection of formatting options.
Returns options plist."
  (list
   :line-break (tibetan-doc-prep--select-from-list
                "Line breaks at: "
                '(("Single shad (།) - for verse/short segments" . shad)
                  ("Double shad (༎) - for prose sentences" . double-shad)
                  ("Preserve original line breaks" . preserve)))

   :segments (tibetan-doc-prep--yes-or-no "Add segment markers (〔seg:N〕)? ")

   :folio-style (tibetan-doc-prep--select-from-list
                 "Folio marker style: "
                 '(("Org headings (* Folio 1a)" . heading)
                   ("Inline markers ([F:1a])" . inline)
                   ("Property drawers" . property)))

   ;; §5.27 Phase 3:  read from the canonical 14-entry genre taxonomy
   ;; \(`tibetan-document-genres-read') so the wizard's selectbox and
   ;; this format dialog share one source of truth.
   :text-type (tibetan-document-genres-read 'classical
                                            "Text type / genre: ")))

(defun tibetan-doc-prep--format-document (text source)
  "Format TEXT into org document.
SOURCE contains source info.
Returns path to created file."
  (let* ((options (tibetan-doc-prep--select-format-options))
         (source-name (or (plist-get source :source-name)
                         (file-name-base (or (plist-get source :path) "document"))))
         (output-dir (or tibetan-doc-prep-output-directory
                        (when (plist-get source :path)
                          (file-name-directory (plist-get source :path)))
                        default-directory))
         (output-file (expand-file-name
                       (concat source-name "-prepared.org")
                       output-dir)))

    (if (fboundp 'tibetan-doc-format)
        (tibetan-doc-format text
                           (list :source-file (plist-get source :path)
                                 :title source-name)
                           options)
      ;; Fallback: basic formatting
      (tibetan-doc-prep--basic-format text output-file options source-name))))

(defun tibetan-doc-prep--basic-format (text output-file options title)
  "Basic document formatting fallback.
Formats TEXT to OUTPUT-FILE with OPTIONS and TITLE."
  (let* ((line-break (plist-get options :line-break))
         (add-segments (plist-get options :segments))
         (text-type (plist-get options :text-type))
         (lines (pcase line-break
                  ('shad (split-string text "།" t "[ \t\n]+"))
                  ('double-shad (split-string text "༎" t "[ \t\n]+"))
                  ('preserve (split-string text "\n" t))))
         (seg-num 1))

    (with-temp-file output-file
      ;; Header
      (insert (format "#+TITLE: %s\n" title))
      (insert (format "#+TIBETAN_TEXT_TYPE: %s\n" text-type))
      (insert (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d")))
      (insert "#+OPTIONS: toc:nil\n\n")

      ;; Body
      (insert "* Text\n\n")
      (dolist (line lines)
        (let ((trimmed (string-trim line)))
          (when (not (string-empty-p trimmed))
            (if add-segments
                (progn
                  (insert (format "〔seg:%d〕%s〔/seg〕\n" seg-num trimmed))
                  (setq seg-num (1+ seg-num)))
              (insert trimmed)
              (insert "།\n"))))))

    output-file))

;; ============================================================================
;; STEP 6: SUMMARY
;; ============================================================================

(defun tibetan-doc-prep--show-summary (source validation output-file)
  "Show summary of document preparation.
SOURCE is the input source, VALIDATION is the validation result,
OUTPUT-FILE is the created file path."
  (message "Document prepared: %s" output-file)
  (message "  Source: %s"
           (or (plist-get source :path)
               (plist-get source :source-name)
               "text input"))
  (unless (plist-get validation :skipped)
    (message "  Validation: %d valid, %d unknown, %d suspicious"
             (length (plist-get validation :valid))
             (length (plist-get validation :unknown))
             (length (plist-get validation :suspicious)))))

;; ============================================================================
;; MAIN WIZARD
;; ============================================================================

;;;###autoload
(defun tibetan-doc-prep-wizard ()
  "Interactive wizard for complete Tibetan document preparation.
Guides through: Source → OCR → Validation → AI Correction → Formatting."
  (interactive)
  (message "Starting Tibetan Document Preparation Wizard...")

  ;; Step 1: Source selection
  (let* ((source (tibetan-doc-prep--select-source))
         (_ (setq tibetan-doc-prep--current-source source))

         ;; Step 2: Get OCR text
         (raw-text (tibetan-doc-prep--get-ocr-text source))

         ;; Step 3: Validate
         (validation (tibetan-doc-prep--validate-text raw-text))

         ;; Step 4: AI correction
         (corrected (tibetan-doc-prep--ai-correct raw-text validation))

         ;; Step 5: Format document
         (output-file (tibetan-doc-prep--format-document corrected source)))

    ;; Step 6: Open and show summary
    (find-file output-file)
    (when (fboundp 'cat-mode)
      (cat-mode 1))
    (tibetan-doc-prep--show-summary source validation output-file)))

;; ============================================================================
;; INDIVIDUAL STEP COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-doc-prep-ocr (source-file)
  "Run OCR on SOURCE-FILE only."
  (interactive "fSelect PDF or image: ")
  (let ((source (list :type (if (string-suffix-p ".pdf" source-file t) 'pdf 'image)
                      :path source-file)))
    (tibetan-doc-prep--get-ocr-text source)
    (let ((buf (get-buffer-create "*Tibetan OCR Output*")))
      (with-current-buffer buf
        (erase-buffer)
        (insert tibetan-doc-prep--raw-text)
        (goto-char (point-min)))
      (pop-to-buffer buf))))

;;;###autoload
(defun tibetan-doc-prep-validate ()
  "Validate current buffer or region against dictionaries."
  (interactive)
  (let* ((text (if (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (buffer-substring-no-properties (point-min) (point-max))))
         (validation (tibetan-doc-prep--validate-text text)))
    (if (plist-get validation :skipped)
        (message "Validation module not available")
      (tibetan-doc-prep--review-flagged validation))))

;;;###autoload
(defun tibetan-doc-prep-correct ()
  "AI-correct current buffer or region."
  (interactive)
  (let* ((text (if (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (buffer-substring-no-properties (point-min) (point-max))))
         (validation (tibetan-doc-prep--validate-text text))
         (corrected (tibetan-doc-prep--ai-correct text validation)))
    (let ((buf (get-buffer-create "*Tibetan Corrected*")))
      (with-current-buffer buf
        (erase-buffer)
        (insert corrected)
        (goto-char (point-min)))
      (pop-to-buffer buf))))

;;;###autoload
(defun tibetan-doc-prep-format ()
  "Format current buffer into org document."
  (interactive)
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (source (list :type 'text
                       :text text
                       :source-name (or (file-name-base buffer-file-name) "formatted")))
         (output-file (tibetan-doc-prep--format-document text source)))
    (find-file output-file)))

;; ============================================================================
;; QUICK PRESETS
;; ============================================================================

;;;###autoload
(defun tibetan-doc-prep-quick-pecha (_file)
  "Quick preparation for pecha scans with defaults.
FILE is the PDF or image to process."
  (interactive "fSelect pecha PDF/image: ")
  (let ((tibetan-doc-prep-default-line-break 'shad)
        (tibetan-doc-prep-default-segments t)
        (tibetan-doc-prep-default-folio-style 'heading)
        (tibetan-doc-prep-default-text-type 'classical))
    (tibetan-doc-prep-wizard)))

;;;###autoload
(defun tibetan-doc-prep-quick-verse (_file)
  "Quick preparation for verse texts.
FILE is the PDF or image to process."
  (interactive "fSelect verse PDF/image: ")
  (let ((tibetan-doc-prep-default-line-break 'shad)
        (tibetan-doc-prep-default-segments t)
        (tibetan-doc-prep-default-folio-style 'heading)
        (tibetan-doc-prep-default-text-type 'madhyamaka-verse))
    (tibetan-doc-prep-wizard)))

;; ============================================================================
;; BATCH PROCESSING
;; ============================================================================


;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(defvar tibetan-doc-prep-map
  (let ((map (make-sparse-keymap)))
    ;; §5.27 Phase 6:  unified document-prep wizard (top-of-map).
    (define-key map (kbd "d")
      (lambda () (interactive)
        (require 'tibetan-document-prep-wizard)
        (call-interactively #'tibetan-document-prep-wizard)))
    (define-key map (kbd "D")
      (lambda () (interactive)
        (require 'tibetan-document-prep-claude)
        (call-interactively #'tibetan-document-prep-apply-claude-suggestions)))
    ;; Legacy OCR wizard kept at `o' for backwards compatibility.
    (define-key map (kbd "o") #'tibetan-doc-prep-wizard)

    ;; §5.27 Phase 2:  Wylie ingest building blocks.
    (define-key map (kbd "y")
      (lambda () (interactive)
        (require 'tibetan-wylie-ingest)
        (call-interactively #'tibetan-wylie-ingest-file)))
    (define-key map (kbd "Y")
      (lambda () (interactive)
        (require 'tibetan-wylie-ingest)
        (call-interactively
         #'tibetan-wylie-ingest-validate-input-interactive)))

    ;; Individual steps
    (define-key map (kbd "r") #'tibetan-doc-prep-ocr)
    (define-key map (kbd "v") #'tibetan-doc-prep-validate)
    (define-key map (kbd "c") #'tibetan-doc-prep-correct)
    (define-key map (kbd "f") #'tibetan-doc-prep-format)

    ;; Quick presets
    (define-key map (kbd "p") #'tibetan-doc-prep-quick-pecha)
    (define-key map (kbd "V") #'tibetan-doc-prep-quick-verse)

    ;; OCR app commands
    (define-key map (kbd "a") #'tibetan-ocr-open-app)
    (define-key map (kbd "w") #'tibetan-ocr-workflow)
    (define-key map (kbd "s") #'tibetan-ocr-status)

    ;; Import submenu (C-c o i prefix)
    (define-key map (kbd "i") (let ((imap (make-sparse-keymap "Import")))
                               (define-key imap (kbd "c") #'tibetan-ocr-import-from-clipboard)
                               (define-key imap (kbd "f") #'tibetan-ocr-import-from-file)
                               (define-key imap (kbd "b") #'tibetan-ocr-import-from-buffer)
                               imap))
    map)
  "Keymap for document preparation commands.

Key bindings:
  d   Unified document-prep wizard (§5.27 — Wylie / Tibetan-script /
      existing / OCR + metadata + analysis kickoff in one flow)
  D   Apply cached Claude metadata suggestions to current buffer
  y   Wylie ingest (validate + convert);  C-u → in-place + relocate
  Y   Wylie ingest — validate only (no conversion)
  o   Legacy OCR / Format wizard (subsumed by `d' for new prep)
  r   OCR step only
  v   Validate buffer
  c   AI correct buffer
  f   Format to org
  p   Quick pecha preset
  V   Quick verse preset
  a   Open BDRC OCR app
  w   OCR workflow (guided)
  s   Show OCR status
  i c Import from clipboard
  i f Import from file
  i b Import from buffer")

;; Global binding for wizard
(global-set-key (kbd "C-c o o") #'tibetan-doc-prep-wizard)
(global-set-key (kbd "C-c o") tibetan-doc-prep-map)

;; Integrate with cat-mode if available
(with-eval-after-load 'cat-mode
  (define-key cat-mode-map (kbd "C-c o") tibetan-doc-prep-map))

(with-eval-after-load 'tibetan-cat
  (define-key (current-global-map) (kbd "C-c o") tibetan-doc-prep-map))

(provide 'tibetan-doc-prep)
;;; tibetan-doc-prep.el ends here
