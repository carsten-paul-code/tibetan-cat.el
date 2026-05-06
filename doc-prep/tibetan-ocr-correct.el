;;; tibetan-ocr-correct.el --- Claude AI correction for Tibetan OCR -*- lexical-binding: t -*-

;;; Commentary:
;; Uses Claude AI (via gptel) to correct OCR errors in Tibetan text.
;; Integrates with tibetan-ocr-validate to provide targeted correction
;; of flagged syllables rather than processing entire text blindly.
;;
;; Usage:
;;   (tibetan-ocr-correct text validation-result)
;;   M-x tibetan-ocr-correct-buffer

;;; Code:

(require 'cl-lib)

(declare-function gptel-request "gptel" (prompt &rest args))
(declare-function tibetan-analysis--ensure-gptel-ready
                  "tibetan-analysis-claude" ())

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-ocr-correct nil
  "Claude AI correction for Tibetan OCR."
  :group 'tibetan-doc-prep
  :prefix "tibetan-ocr-correct-")

(defcustom tibetan-ocr-correct-model "claude-sonnet-4-20250514"
  "Claude model to use for OCR correction.
Sonnet is recommended for balance of speed and accuracy."
  :type 'string
  :group 'tibetan-ocr-correct)

(defcustom tibetan-ocr-correct-show-diff t
  "Whether to show diff of changes after correction."
  :type 'boolean
  :group 'tibetan-ocr-correct)

(defcustom tibetan-ocr-correct-auto-accept nil
  "If non-nil, automatically accept AI corrections without confirmation."
  :type 'boolean
  :group 'tibetan-ocr-correct)

;; ============================================================================
;; PROMPT CONSTRUCTION
;; ============================================================================

(defconst tibetan-ocr-correct--system-prompt
  "You are an expert in Classical Tibetan orthography, helping to correct OCR errors.
You have deep knowledge of:
- Tibetan syllable structure and valid character combinations
- Common OCR error patterns (ག/ད, བ/པ, vowel mark issues, stack splitting)
- Buddhist technical vocabulary and proper nouns
- Grammar particles and their correct forms

Your task is to correct OCR errors while preserving correct text.
Be conservative: only change syllables that are clearly erroneous."
  "System prompt for Claude OCR correction.")

(defun tibetan-ocr-correct--format-flagged (validation)
  "Format flagged items from VALIDATION for prompt."
  (let ((unknown (plist-get validation :unknown))
        (suspicious (plist-get validation :suspicious))
        (details (plist-get validation :details)))

    (concat
     (when unknown
       (concat "Unknown syllables (not in dictionary):\n"
               (mapconcat (lambda (syl)
                           (let* ((detail (seq-find (lambda (d)
                                                     (string= (plist-get d :syllable) syl))
                                                   details))
                                  (suggestions (plist-get detail :suggestions)))
                             (if suggestions
                                 (format "- %s (suggestions: %s)"
                                        syl (mapconcat #'identity suggestions ", "))
                               (format "- %s" syl))))
                         unknown "\n")
               "\n\n"))
     (when suspicious
       (concat "Suspicious syllables (possible OCR errors):\n"
               (mapconcat (lambda (syl)
                           (format "- %s" syl))
                         suspicious "\n")
               "\n")))))

(defun tibetan-ocr-correct--build-prompt (text validation)
  "Build correction prompt from TEXT and VALIDATION result."
  (let ((total (plist-get validation :total))
        (valid-count (length (plist-get validation :valid)))
        (unknown-count (length (plist-get validation :unknown)))
        (suspicious-count (length (plist-get validation :suspicious)))
        (flagged-text (tibetan-ocr-correct--format-flagged validation)))

    (format "Please correct any OCR errors in this Classical Tibetan text.

## Original Text
%s

## Validation Summary
- Total syllables: %d
- Valid (found in dictionary): %d
- Unknown (not in dictionary): %d
- Suspicious (possible errors): %d

## Flagged Syllables
%s

## Common Tibetan OCR Errors to Check
1. Letter confusion: ག/ད (ga/da), བ/པ (ba/pa), ང/ཅ (nga/ca)
2. Missing vowel marks: ི (i), ུ (u), ེ (e), ོ (o)
3. Subscript confusion: ྱ/ྲ (ya-btags/ra-btags)
4. Stack splitting: རྒ → ར་ག, སྒ → ས་ག
5. Extra or missing tsheg (་)

## Instructions
1. Review each flagged syllable in context
2. Correct clear OCR errors based on:
   - Valid Tibetan syllable structure
   - Context (surrounding words)
   - Common Buddhist vocabulary
   - Dictionary suggestions provided
3. Keep valid syllables unchanged
4. Be conservative - only change what is clearly wrong

## Required Output Format
Return your response in exactly this format:

CORRECTED_TEXT_START
[The complete corrected Tibetan text here]
CORRECTED_TEXT_END

CHANGES_START
[List each change, one per line, format: original → corrected: reason]
CHANGES_END"
            text
            total valid-count unknown-count suspicious-count
            flagged-text)))

;; ============================================================================
;; RESPONSE PARSING
;; ============================================================================

(defun tibetan-ocr-correct--parse-response (response)
  "Parse Claude RESPONSE into corrected text and changes list.
Returns plist: (:text \"...\" :changes (list of plists))"
  (let ((text nil)
        (changes nil))

    ;; Extract corrected text
    (when (string-match "CORRECTED_TEXT_START[[:space:]]*\\(\\(?:.\\|\n\\)*?\\)[[:space:]]*CORRECTED_TEXT_END" response)
      (setq text (string-trim (match-string 1 response))))

    ;; Extract changes
    (when (string-match "CHANGES_START[[:space:]]*\\(\\(?:.\\|\n\\)*?\\)[[:space:]]*CHANGES_END" response)
      (let ((changes-text (match-string 1 response)))
        (dolist (line (split-string changes-text "\n" t "[ \t]+"))
          (when (string-match "\\(.+?\\)[[:space:]]*→[[:space:]]*\\(.+?\\):[[:space:]]*\\(.*\\)" line)
            (push (list :original (string-trim (match-string 1 line))
                       :corrected (string-trim (match-string 2 line))
                       :reason (string-trim (match-string 3 line)))
                  changes)))))

    (list :text (or text response)  ; Fall back to full response if parsing fails
          :changes (nreverse changes))))

;; ============================================================================
;; GPTEL INTEGRATION
;; ============================================================================

(defun tibetan-ocr-correct--gptel-available-p ()
  "Check if gptel is available and configured.
Self-loads the API key from `~/.authinfo' (or `$ANTHROPIC_API_KEY')
via `tibetan-analysis--ensure-gptel-ready' if persist module is
loaded -- so a fresh Emacs session need not have run an analysis
command first.  Same pattern as
`tibetan-sanskrit-parallel-dharmamitra'."
  (when (fboundp 'tibetan-analysis--ensure-gptel-ready)
    (ignore-errors (tibetan-analysis--ensure-gptel-ready)))
  (and (featurep 'gptel)
       (boundp 'gptel-api-key)
       gptel-api-key))

(defun tibetan-ocr-correct--call-claude (prompt callback)
  "Call Claude with PROMPT, invoke CALLBACK with response."
  (unless (tibetan-ocr-correct--gptel-available-p)
    (user-error "gptel not configured. Please set up Claude API key"))

  (require 'gptel)

  (let ((_gptel-model tibetan-ocr-correct-model))
    (gptel-request prompt
      :system tibetan-ocr-correct--system-prompt
      :callback callback)))

;; ============================================================================
;; MAIN CORRECTION FUNCTIONS
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-correct (text validation)
  "Correct TEXT using Claude AI, informed by VALIDATION result.
Returns plist: (:text \"corrected\" :changes (list))"
  (unless (tibetan-ocr-correct--gptel-available-p)
    (user-error "gptel not configured for Claude API"))

  (let ((prompt (tibetan-ocr-correct--build-prompt text validation))
        (result nil)
        (done nil))

    ;; Show progress
    (message "Sending to Claude for OCR correction...")

    ;; Synchronous call using gptel
    (tibetan-ocr-correct--call-claude
     prompt
     (lambda (response info)
       (if (not response)
           (progn
             (message "Claude API error: %s" (plist-get info :status))
             (setq result (list :text text :changes nil :error t)))
         (setq result (tibetan-ocr-correct--parse-response response)))
       (setq done t)))

    ;; Wait for response (with timeout)
    (let ((timeout 120)  ; 2 minutes
          (waited 0))
      (while (and (not done) (< waited timeout))
        (sleep-for 0.5)
        (setq waited (+ waited 0.5))))

    (unless done
      (setq result (list :text text :changes nil :error "Timeout")))

    ;; Show diff if enabled and changes were made
    (when (and tibetan-ocr-correct-show-diff
               (plist-get result :changes))
      (tibetan-ocr-correct--show-diff text (plist-get result :text)
                                      (plist-get result :changes)))

    result))

;; ============================================================================
;; DIFF DISPLAY
;; ============================================================================

(defun tibetan-ocr-correct--show-diff (_original corrected changes)
  "Show diff between ORIGINAL and CORRECTED text with CHANGES list."
  (let ((buf (get-buffer-create "*Tibetan OCR Corrections*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "# OCR Correction Results\n\n")

      ;; Summary
      (insert (format "## Summary: %d changes made\n\n" (length changes)))

      ;; Changes list
      (when changes
        (insert "## Changes\n\n")
        (dolist (change changes)
          (insert (format "- **%s** → **%s**"
                         (plist-get change :original)
                         (plist-get change :corrected)))
          (when (plist-get change :reason)
            (insert (format ": %s" (plist-get change :reason))))
          (insert "\n"))
        (insert "\n"))

      ;; Corrected text
      (insert "## Corrected Text\n\n")
      (insert "```tibetan\n")
      (insert corrected)
      (insert "\n```\n")

      (goto-char (point-min))
      (when (fboundp 'org-mode)
        (org-mode)))

    (display-buffer buf)))

;; ============================================================================
;; INTERACTIVE COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-correct-buffer ()
  "Correct OCR errors in current buffer using Claude AI."
  (interactive)
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (validation (if (fboundp 'tibetan-ocr-validate-text)
                        (tibetan-ocr-validate-text text)
                      '(:unknown nil :suspicious nil)))
         (unknown-count (length (plist-get validation :unknown)))
         (suspicious-count (length (plist-get validation :suspicious))))

    (if (and (zerop unknown-count) (zerop suspicious-count))
        (message "No issues found - text appears clean!")

      (when (or tibetan-ocr-correct-auto-accept
               (yes-or-no-p (format "Found %d unknown, %d suspicious syllables. Correct with Claude? "
                                    unknown-count suspicious-count)))
        (let ((result (tibetan-ocr-correct text validation)))
          (if (plist-get result :error)
              (message "Correction failed: %s" (plist-get result :error))

            ;; Ask to apply changes
            (when (plist-get result :changes)
              (when (or tibetan-ocr-correct-auto-accept
                       (yes-or-no-p "Apply corrections to buffer? "))
                (erase-buffer)
                (insert (plist-get result :text))
                (message "Applied %d corrections" (length (plist-get result :changes)))))))))))

;;;###autoload
(defun tibetan-ocr-correct-region (start end)
  "Correct OCR errors in region between START and END."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (validation (if (fboundp 'tibetan-ocr-validate-text)
                        (tibetan-ocr-validate-text text)
                      '(:unknown nil :suspicious nil)))
         (result (tibetan-ocr-correct text validation)))

    (if (plist-get result :error)
        (message "Correction failed: %s" (plist-get result :error))
      (when (and (plist-get result :changes)
                (or tibetan-ocr-correct-auto-accept
                    (yes-or-no-p "Replace region with corrected text? ")))
        (delete-region start end)
        (insert (plist-get result :text))
        (message "Applied %d corrections" (length (plist-get result :changes)))))))

;; ============================================================================
;; STANDALONE CORRECTION (without validation)
;; ============================================================================

(provide 'tibetan-ocr-correct)
;;; tibetan-ocr-correct.el ends here
