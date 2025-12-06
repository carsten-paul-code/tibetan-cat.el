# Tibetan Document Preparation Pipeline

## Overview

A stepwise pipeline for preparing Tibetan documents for translation work in Emacs:

1. **OCR** - Extract text from images/PDFs via BDRC OCR
2. **Validate** - Check against local dictionaries (17,777+ entries)
3. **AI Correct** - Claude-based correction of flagged items
4. **Format** - Create org-mode document ready for CAT workflow

## Master Command

`C-c o o` → `tibetan-doc-prep-wizard`

Runs all steps interactively with prompts for options.

---

## Module Structure

```
emacs-tibetan-cat/doc-prep/
├── tibetan-doc-prep.el           ; Main wizard & orchestration
├── tibetan-ocr-runner.el         ; BDRC CLI integration
├── tibetan-ocr-validate.el       ; Dictionary validation
├── tibetan-ocr-correct.el        ; Claude AI correction (gptel)
└── tibetan-doc-format.el         ; Org document formatting
```

---

## Module 1: tibetan-doc-prep.el (Main Orchestration)

### Public Functions

```elisp
;; Interactive
(defun tibetan-doc-prep-wizard ()
  "Full interactive wizard for document preparation.")

;; Batch/programmatic
(defun tibetan-doc-prep-batch (source output &optional options)
  "Non-interactive batch processing with OPTIONS plist.")

;; Quick presets
(defun tibetan-doc-prep-quick-pecha (file)
  "Quick prep for pecha scans with sensible defaults.")

(defun tibetan-doc-prep-quick-verse (file)
  "Quick prep for verse texts.")
```

### Options Plist

```elisp
'(:ocr-model     pecha | modern | manuscript
  :line-break    shad | double-shad | preserve
  :segments      t | nil
  :folio-style   heading | inline | property
  :text-type     classical | madhyamaka-verse | sutra | commentary
  :ai-correct    t | nil | auto)
```

### Dependencies

- `tibetan-ocr-runner`
- `tibetan-ocr-validate`
- `tibetan-ocr-correct`
- `tibetan-doc-format`

---

## Module 2: tibetan-ocr-runner.el (BDRC OCR Integration)

### Prerequisites

- BDRC OCR App installed: https://github.com/buda-base/tibetan-ocr-app
- CLI available at known path

### Configuration

```elisp
(defcustom tibetan-ocr-cli-path
  (expand-file-name "~/Applications/bdrc-ocr/cli.py")
  "Path to BDRC OCR CLI script.")

(defcustom tibetan-ocr-models-dir
  (expand-file-name "~/Applications/bdrc-ocr/models/")
  "Path to OCR models directory.")

(defcustom tibetan-ocr-default-model 'pecha
  "Default OCR model to use.")
```

### Public Functions

```elisp
(defun tibetan-ocr-run (source &optional model)
  "Run OCR on SOURCE (file or directory).
MODEL is 'pecha, 'modern, or 'manuscript.
Returns alist: ((:text . \"...\") (:pages . ((1 . \"1a\") ...)))")

(defun tibetan-ocr-run-async (source callback &optional model)
  "Async version for large documents.")

(defun tibetan-ocr-available-p ()
  "Check if BDRC OCR is installed and available.")

(defun tibetan-ocr-list-models ()
  "List available OCR models.")
```

### Implementation Notes

```elisp
(defun tibetan-ocr--build-command (source model output-format)
  "Build CLI command for OCR."
  (format "python3 %s --input %s --model %s --format %s"
          tibetan-ocr-cli-path
          (shell-quote-argument source)
          (tibetan-ocr--model-name model)
          output-format))

(defun tibetan-ocr--parse-output (output)
  "Parse OCR output, extracting text and page markers.")

(defun tibetan-ocr--extract-folio-markers (text)
  "Extract folio numbers from OCR output (if present in margins).")
```

---

## Module 3: tibetan-ocr-validate.el (Dictionary Validation)

### Integration with Existing Resources

Uses these existing data sources:
- `tibetan-comprehensive-vocabulary` (hash-table, 17,777+ entries)
- `~/emacs-tibetan-cat/data/dictionaries/compounds.json` (3,000+ compounds)
- `~/emacs-tibetan-cat/data/dictionaries/proper_nouns.json`
- Particle patterns from `tibetan-particles-bialek.el`

### Public Functions

```elisp
(defun tibetan-ocr-validate-text (text)
  "Validate TEXT against all dictionaries.
Returns: ((:valid . (list)) (:unknown . (list)) (:suspicious . (list)))")

(defun tibetan-ocr-validate-syllable (syllable)
  "Validate single SYLLABLE.
Returns: (:status valid|unknown|suspicious
          :source \"Hopkins\"|\"compound\"|\"particle\"|nil
          :suggestions (list))")

(defun tibetan-ocr-validation-report (validation-result)
  "Generate human-readable report from validation result.")

(defun tibetan-ocr-suggest-corrections (syllable)
  "Suggest corrections for unknown SYLLABLE using edit distance.")
```

### Validation Logic

```elisp
(defun tibetan-ocr--validate-against-sources (syllable)
  "Check SYLLABLE against all sources in order of priority."
  (or
   ;; 1. Check comprehensive vocabulary
   (tibetan-ocr--check-vocabulary syllable)
   ;; 2. Check compounds (with context)
   (tibetan-ocr--check-compounds syllable)
   ;; 3. Check proper nouns
   (tibetan-ocr--check-proper-nouns syllable)
   ;; 4. Check if valid particle
   (tibetan-ocr--check-particle syllable)
   ;; 5. Check syllable structure validity
   (tibetan-ocr--check-structure syllable)))
```

### Common OCR Error Patterns

```elisp
(defvar tibetan-ocr-confusion-pairs
  '(;; Visually similar base letters
    ("ག" . "ད")    ; ga/da
    ("བ" . "པ")    ; ba/pa
    ("ང" . "ཅ")    ; nga/ca
    ("ཇ" . "ཉ")    ; ja/nya
    ("ཐ" . "ཕ")    ; tha/pha (rare)
    ;; Subscript confusions
    ("ྱ" . "ྲ")    ; ya-btags/ra-btags
    ("ྭ" . "ྲ")    ; wa-zur/ra-btags
    ;; Vowel issues
    ("ི" . "")     ; i-vowel dropped
    ("ུ" . "")     ; u-vowel dropped
    ("ེ" . "ི")    ; e/i confusion
    ("ོ" . "ེ")    ; o/e confusion
    ;; Stack splitting
    ("རྒ" . "ར་ག")
    ("སྒ" . "ས་ག")
    ("བསྒ" . "བས་ག"))
  "Common OCR confusion pairs for Tibetan.")

(defun tibetan-ocr--find-similar (syllable)
  "Find dictionary entries similar to SYLLABLE.
Uses edit distance and confusion pairs.")
```

---

## Module 4: tibetan-ocr-correct.el (Claude AI Correction)

### Integration with Existing Claude Setup

Uses `gptel` package already configured in `~/.emacs.d/claude-integration.el`.

### Public Functions

```elisp
(defun tibetan-ocr-correct (text validation-result)
  "Correct TEXT using Claude AI, informed by VALIDATION-RESULT.
Returns corrected text.")

(defun tibetan-ocr-correct-async (text validation-result callback)
  "Async version of correction.")

(defun tibetan-ocr-correct-interactive ()
  "Interactive correction of current buffer/region.")

(defun tibetan-ocr-show-diff (original corrected)
  "Show diff between ORIGINAL and CORRECTED text.")
```

### Prompt Construction

```elisp
(defun tibetan-ocr--build-correction-prompt (text flagged validation)
  "Build targeted Claude prompt."
  (format "You are correcting OCR output for Classical Tibetan text.

## Original Text
%s

## Validation Results
- Total syllables: %d
- Valid (in dictionary): %d
- Unknown (not found): %d
- Suspicious (possible errors): %d

## Flagged Syllables Requiring Review
%s

## Common Tibetan OCR Errors
- ག/ད confusion (visually similar)
- བ/པ confusion
- Missing vowel marks (ི, ུ, ེ, ོ)
- Split stacks (རྒ → ར་ག)
- ྱ/ྲ subscript confusion

## Dictionary Suggestions
%s

## Instructions
1. Review each flagged syllable in context
2. Correct obvious OCR errors
3. Keep valid syllables unchanged
4. Return the corrected text
5. After the text, list changes made with brief explanations

## Output Format
CORRECTED TEXT:
[corrected Tibetan text here]

CHANGES:
- [original] → [corrected]: [reason]
"
          text
          (plist-get validation :total)
          (length (plist-get validation :valid))
          (length (plist-get validation :unknown))
          (length (plist-get validation :suspicious))
          (tibetan-ocr--format-flagged flagged)
          (tibetan-ocr--format-suggestions validation)))
```

### Response Parsing

```elisp
(defun tibetan-ocr--parse-correction-response (response)
  "Parse Claude response into corrected text and change list."
  (let ((parts (split-string response "CHANGES:" t)))
    (list :text (string-trim (car parts))
          :changes (tibetan-ocr--parse-changes (cadr parts)))))
```

---

## Module 5: tibetan-doc-format.el (Org Document Formatting)

### Public Functions

```elisp
(defun tibetan-doc-format (text source-info &optional options)
  "Format TEXT into org document.
SOURCE-INFO contains folio markers, filename, etc.
OPTIONS controls formatting style.
Returns path to created file.")

(defun tibetan-doc-format-buffer ()
  "Format current buffer's Tibetan text into org structure.")
```

### Document Template

```elisp
(defun tibetan-doc--generate-org (text options source-info)
  "Generate org document content."
  (concat
   ;; Header
   (tibetan-doc--format-header source-info options)
   "\n\n"
   ;; Body with segments
   (tibetan-doc--format-body text options source-info)))

(defun tibetan-doc--format-header (source-info options)
  "Generate org header."
  (format "#+TITLE: %s
#+TIBETAN_TEXT_TYPE: %s
#+SOURCE: %s
#+DATE: %s
#+OPTIONS: toc:nil

* Document Info
:PROPERTIES:
:OCR_SOURCE: %s
:OCR_DATE: %s
:FOLIOS: %s
:END:
"
          (plist-get source-info :title)
          (plist-get options :text-type)
          (plist-get source-info :source-file)
          (format-time-string "%Y-%m-%d")
          (plist-get source-info :source-file)
          (format-time-string "%Y-%m-%d %H:%M")
          (plist-get source-info :folio-range)))
```

### Line Breaking Logic

```elisp
(defun tibetan-doc--split-at-shad (text)
  "Split TEXT at single shad (།), creating one line per segment."
  (split-string text "།" t))

(defun tibetan-doc--split-at-double-shad (text)
  "Split TEXT at double shad (༎), keeping single shad within lines."
  (split-string text "༎" t))

(defun tibetan-doc--add-segment-markers (lines &optional start-num)
  "Add 〔seg:N〕 markers to LINES."
  (let ((n (or start-num 1)))
    (mapcar (lambda (line)
              (prog1
                  (format "〔seg:%d〕%s〔/seg〕" n (string-trim line))
                (setq n (1+ n))))
            lines)))
```

### Folio Marker Styles

```elisp
;; Style 1: Org headings
(defun tibetan-doc--folio-as-heading (folio-num)
  (format "\n* Folio %s\n" folio-num))

;; Style 2: Inline markers
(defun tibetan-doc--folio-inline (folio-num)
  (format "[F:%s] " folio-num))

;; Style 3: Property drawer
(defun tibetan-doc--folio-as-property (folio-num content)
  (format ":PROPERTIES:
:FOLIO: %s
:END:
%s" folio-num content))
```

---

## Keybindings

```elisp
;; Add to tibetan-doc-prep.el

(defvar tibetan-doc-prep-map
  (let ((map (make-sparse-keymap)))
    ;; Full wizard
    (define-key map (kbd "o") #'tibetan-doc-prep-wizard)
    ;; Individual steps
    (define-key map (kbd "r") #'tibetan-doc-prep-ocr)
    (define-key map (kbd "v") #'tibetan-doc-prep-validate)
    (define-key map (kbd "c") #'tibetan-doc-prep-correct)
    (define-key map (kbd "f") #'tibetan-doc-prep-format)
    ;; Quick presets
    (define-key map (kbd "p") #'tibetan-doc-prep-quick-pecha)
    (define-key map (kbd "V") #'tibetan-doc-prep-quick-verse)
    map)
  "Keymap for document preparation commands.")

;; Bind under C-c o prefix
(define-key cat-mode-map (kbd "C-c o") tibetan-doc-prep-map)

;; Also make available globally for non-cat-mode buffers
(global-set-key (kbd "C-c o o") #'tibetan-doc-prep-wizard)
```

---

## Implementation Order

### Phase 1: Core Infrastructure
1. [ ] `tibetan-doc-prep.el` - Basic structure, wizard skeleton
2. [ ] `tibetan-doc-format.el` - Org formatting (no OCR dependency)

### Phase 2: Validation
3. [ ] `tibetan-ocr-validate.el` - Dictionary integration
4. [ ] Test validation with manual text input

### Phase 3: AI Correction
5. [ ] `tibetan-ocr-correct.el` - Claude/gptel integration
6. [ ] Test correction workflow

### Phase 4: OCR Integration
7. [ ] Install BDRC OCR App
8. [ ] `tibetan-ocr-runner.el` - CLI wrapper
9. [ ] Test full pipeline

### Phase 5: Polish
10. [ ] Error handling & edge cases
11. [ ] Progress indicators for long operations
12. [ ] Documentation & help

---

## Testing

### Test Files Needed
- Sample pecha scan (PDF or images)
- Sample modern print
- Pre-OCR'd text with known errors
- Clean text for validation testing

### Test Commands
```elisp
;; Test validation only
(tibetan-ocr-validate-text "བདག་གི་སེམས་ཀྱི་རང་བཞིན།")

;; Test formatting only
(tibetan-doc-format "བདག་གི་སེམས།སེམས་ཅན་ཐམས་ཅད།"
                    '(:source-file "test.pdf" :title "Test")
                    '(:line-break shad :segments t))

;; Test full wizard (interactive)
M-x tibetan-doc-prep-wizard
```

---

## Dependencies

### Required
- Emacs 27.1+
- `gptel` package (for Claude API)
- Existing CAT tool modules

### Optional
- BDRC OCR App (for OCR step)
- Python 3 (for BDRC CLI)

### Data Files
- `tibetan-comprehensive-vocabulary` (loaded via load-comprehensive-glossaries.el)
- `compounds.json`
- `proper_nouns.json`
