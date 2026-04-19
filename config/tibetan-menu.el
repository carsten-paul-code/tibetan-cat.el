;;; tibetan-menu.el --- Menu bar entries for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Provides menu bar integration for the Tibetan Computer-Assisted Translation system.
;; All major functions are accessible via the "Tibetan" menu.

;;; Code:

(require 'easymenu)

;; ============================================================================
;; MAIN TIBETAN MENU
;; ============================================================================

(easy-menu-define tibetan-cat-menu global-map
  "Menu for Tibetan CAT (Computer-Assisted Translation) tools."
  '("Tibetan"
    ("Document Preparation"
     ["Preparation Wizard..." tibetan-doc-prep-wizard
      :help "Full pipeline: Source → OCR → Validation → Formatting"
      :active (fboundp 'tibetan-doc-prep-wizard)]
     "---"
     ["Format Buffer (Segment)" tibetan-doc-format-buffer
      :help "Split buffer text at shad boundaries into numbered segments"
      :active (fboundp 'tibetan-doc-format-buffer)]
     ["Format Region (Segment)" tibetan-doc-format-region
      :help "Split selected text at shad boundaries into numbered segments"
      :active (fboundp 'tibetan-doc-format-region)]
     "---"
     ["OCR from PDF/Image..." tibetan-doc-prep-ocr
      :help "Run OCR on a PDF or image file"
      :active (fboundp 'tibetan-doc-prep-ocr)]
     ["Validate Buffer" tibetan-doc-prep-validate
      :help "Validate current buffer against dictionaries"
      :active (fboundp 'tibetan-doc-prep-validate)]
     ["AI Correct Buffer" tibetan-doc-prep-correct
      :help "AI-assisted correction of OCR errors"
      :active (fboundp 'tibetan-doc-prep-correct)])
    "---"
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
     ["Batch Re-analyze Folder (C-c u r)" tibetan-analysis-batch-reanalyze
      :help "Re-run auto-analysis on every seg-NNN*.org, preserving notes, working translation, and Claude translation"]
     ["Batch Analyze All Segments (C-c u B)" tibetan-auto-analyze-document
      :help "Analyze all segments in buffer, with option to skip or regenerate existing"]
     ["Combine into One Document (C-c u C)" tibetan-analysis-combine-document
      :help "Stitch every seg-NNN*.org into analysis/combined.org with consolidated appendix"]
     "---"
     ["Refresh DharmaMitra (C-c u D)" tibetan-refresh-dharmamitra-translation
      :help "Re-request DharmaMitra translation (run in analysis file)"]
     ["Copy DharmaMitra to Working (C-c u W)" tibetan-copy-dharmamitra-to-working
      :help "Copy DharmaMitra translation to Working Translation section"])
    ("Persistent Sentence Analysis"
     ["Open/Create Sentence Analysis (C-c s A)" tibetan-sentence-open-analysis
      :help "Open or create persistent analysis file for the sentence at point"
      :active (fboundp 'tibetan-sentence-open-analysis)]
     ["Re-analyze Sentence (C-c s R)" tibetan-sentence-reanalyze
      :help "Regenerate sentence analysis while preserving your notes"
      :active (fboundp 'tibetan-sentence-reanalyze)]
     ["Batch Re-analyze Sentence Folder (C-c s r)" tibetan-sentence-batch-reanalyze
      :help "Re-run auto-analysis on every sent-NNN*.org, preserving notes and Claude sections"
      :active (fboundp 'tibetan-sentence-batch-reanalyze)]
     "---"
     ["Show Claude Queue Status" tibetan-claude-queue-show-status
      :help "Show how many Claude requests are pending / in-flight / done"
      :active (fboundp 'tibetan-claude-queue-show-status)]
     ["Cancel Pending Claude Requests" tibetan-claude-queue-cancel-pending
      :help "Drop queued Claude requests; in-flight requests still finish"
      :active (fboundp 'tibetan-claude-queue-cancel-pending)])
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
      :help "Preview where sentence boundaries would be detected"
      :active (fboundp 'tibetan-detect-sentence-boundaries)]
     ["Add Sentence Structure (C-c s S)" tibetan-add-sentence-structure
      :help "Add ** Sentence headings based on detected boundaries"
      :active (fboundp 'tibetan-add-sentence-structure)]
     ["Mark Sentence Start (C-c s m)" tibetan-mark-sentence-start
      :help "Manually mark current segment as starting a new sentence"
      :active (fboundp 'tibetan-mark-sentence-start)])
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
