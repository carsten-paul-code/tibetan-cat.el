;;; tibetan-menu.el --- Menu bar entries for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Provides menu bar integration for the Tibetan Computer-Assisted Translation system.
;; All major functions are accessible via the "Tibetan" menu.

;;; Code:

(require 'easymenu)

;; OCR correction functions (autoloaded from translation-tools)
(autoload 'tibetan-ocr-double-check "tibetan-ocr-correction"
  "Start an OCR double-check session with scan PDF." t)
(autoload 'tibetan-ocr-auto-correct "tibetan-ocr-correction"
  "Apply automatic OCR corrections to the current buffer." t)
(autoload 'tibetan-ocr-next-page "tibetan-ocr-correction"
  "Go to next page in the scan PDF." t)
(autoload 'tibetan-ocr-prev-page "tibetan-ocr-correction"
  "Go to previous page in the scan PDF." t)
(autoload 'tibetan-ocr-goto-page "tibetan-ocr-correction"
  "Go to a specific page in the scan PDF." t)
(autoload 'tibetan-ocr-finalize-corrections "tibetan-ocr-correction"
  "Compute diff and append correction log to file." t)
(autoload 'tibetan-ocr-quit "tibetan-ocr-correction"
  "Quit OCR correction mode." t)

;; ============================================================================
;; MAIN TIBETAN MENU
;; ============================================================================

(easy-menu-define tibetan-cat-menu global-map
  "Menu for Tibetan CAT (Computer-Assisted Translation) tools."
  '("Tibetan"
    ["Segment Info (C-c u i)" tibetan-segment-info
     :help "Show comprehensive segment analysis in side window"]
    ["Enhanced Segment Info (C-c u I)" tibetan-segment-info-enhanced
     :help "Show enhanced analysis with compound recognition"]
    "---"
    ("Persistent Analysis"
     ["Open/Create Analysis (C-c u A)" tibetan-open-segment-analysis
      :help "Open or create persistent analysis file for current segment"]
     ["Re-analyze Segment (C-c u R)" tibetan-reanalyze-segment
      :help "Regenerate analysis while preserving your notes"]
     ["Batch Analyze All Segments (C-c u B)" tibetan-auto-analyze-document
      :help "Analyze all segments in buffer, with option to skip or regenerate existing"]
     "---"
     ["Refresh DharmaMitra (C-c u D)" tibetan-refresh-dharmamitra-translation
      :help "Re-request DharmaMitra translation (run in analysis file)"]
     ["Copy DharmaMitra to Working (C-c u W)" tibetan-copy-dharmamitra-to-working
      :help "Copy DharmaMitra translation to Working Translation section"])
    ("Compound/Verse Analysis"
     ["Open Compound Analysis (C-c v A)" tibetan-open-compound-analysis
      :help "Analyze verse or multi-line compound at point"]
     ["Re-analyze Compound (C-c v R)" tibetan-reanalyze-compound
      :help "Regenerate compound analysis while preserving notes"]
     ["Analyze Current Verse (C-c v v)" tibetan-analyze-current-verse-interactive
      :help "Analyze verse block with meter validation"])
    "---"
    ("Translation"
     ["CAT Translation (C-c u t)" tibetan-cat-insert-translation
      :help "Generate CAT-suggested translation for current segment"]
     ["Translate Region (C-c u T)" tibetan-cat-translate-region
      :help "Generate translation for selected Tibetan text"]
     "---"
     ["Mitra AI Translate (C-c u m)" tibetan-mitra-translate-dwim
      :help "Translate using Gemma-2-Mitra-E AI model"]
     ["Check Mitra Status (C-c u M)" tibetan-mitra-check-status
      :help "Check if Mitra backend is available"])
    ("Sentence Structure"
     ["Prepare Sentence Workspace (C-c s w)" tibetan-prepare-sentence
      :help "Create sentence workspace with line-by-line analysis"]
     "---"
     ["Detect Sentence Boundaries (C-c s s)" tibetan-detect-sentence-boundaries
      :help "Preview where sentence boundaries would be detected"]
     ["Add Sentence Structure (C-c s S)" tibetan-add-sentence-structure
      :help "Add ** Sentence headings based on detected boundaries"]
     ["Mark Sentence Start (C-c s m)" tibetan-mark-sentence-start
      :help "Manually mark current segment as starting a new sentence"])
    "---"
    ["Toggle Auto-Analysis (C-c u E)" tibetan-toggle-auto
     :help "Toggle automatic analysis as cursor moves between segments"
     :style toggle
     :selected (bound-and-true-p tibetan-auto-analysis-mode)]
    "---"
    ("Display Settings"
     ["Increase Text Size (C-c u +)" tibetan-increase-text-scale
      :help "Make Tibetan text larger"]
     ["Decrease Text Size (C-c u -)" tibetan-decrease-text-scale
      :help "Make Tibetan text smaller"]
     ["Set Text Scale..." tibetan-set-text-scale
      :help "Set exact scale factor for Tibetan text"]
     "---"
     ["Toggle Display Mode" tibetan-doc-display-mode
      :help "Toggle enhanced display for Tibetan documents"
      :style toggle
      :selected (bound-and-true-p tibetan-doc-display-mode)])
    "---"
    ("OCR Correction"
     ["Double-Check with Scan (C-c o c)" tibetan-ocr-double-check
      :help "Open OCR file alongside scan PDF for side-by-side correction"]
     ["Auto-Correct Buffer (C-c o a)" tibetan-ocr-auto-correct
      :help "Apply known OCR error fixes to current buffer"]
     "---"
     ["Next Scan Page (C-c o n)" tibetan-ocr-next-page
      :help "Go to next page in the scan PDF"]
     ["Previous Scan Page (C-c o p)" tibetan-ocr-prev-page
      :help "Go to previous page in the scan PDF"]
     ["Go to Scan Page... (C-c o g)" tibetan-ocr-goto-page
      :help "Jump to specific page in the scan PDF"]
     "---"
     ["Finalize Corrections (C-c o f)" tibetan-ocr-finalize-corrections
      :help "Compute diff and append correction log to file"]
     ["Quit Correction Mode (C-c o q)" tibetan-ocr-quit
      :help "End OCR correction session"])
    "---"
    ["Reload All Glossaries" reload-all-glossaries
     :help "Reload Hopkins, Bialek, and other glossaries"]))

;; ============================================================================
;; CONTEXT MENU (right-click in Tibetan buffers)
;; ============================================================================

(defvar tibetan-cat-context-menu-map
  (let ((map (make-sparse-keymap "Tibetan")))
    (define-key map [segment-info] '(menu-item "Segment Info" tibetan-segment-info))
    (define-key map [open-analysis] '(menu-item "Open Analysis" tibetan-open-segment-analysis))
    (define-key map [translate] '(menu-item "CAT Translate" tibetan-cat-insert-translation))
    map)
  "Context menu for Tibetan CAT operations.")

(provide 'tibetan-menu)
;;; tibetan-menu.el ends here
