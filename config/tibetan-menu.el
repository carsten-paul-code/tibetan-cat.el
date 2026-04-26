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
      :active (fboundp 'tibetan-doc-prep-correct)]
     "---"
     ["Migrate 〔seg:N〕/〔trans:N〕 to Headings" tibetan-migrate-inline-segments-to-headings
      :help "Convert paired inline 〔seg:N〕…〔/seg〕 + 〔trans:N〕…〔/trans〕 markers to *** Segment / **** Working Translation"
      :active (fboundp 'tibetan-migrate-inline-segments-to-headings)]
     ["Migrate bare 〔seg:N〕 to Headings" tibetan-migrate-bare-segments-to-headings
      :help "Convert bare 〔seg:N〕…〔/seg〕 markers to *** Segment headings; flatten Tibetan-title headings to ** Section; hoist #+KEYWORD metadata to document header"
      :active (fboundp 'tibetan-migrate-bare-segments-to-headings)])
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
    ;; ========================================================================
    ;; Thesaurus / Zettelkasten — user-editable multilingual term glossary
    ;; (Pass 5b, 2026-04-22).  The Zettelkasten lives at
    ;; `~/buddhist-studies/knowledge/zettelkasten/' (moved there 2026-04-24
    ;; as part of the buddhist-studies reorg).  Each zettel is a Denote-
    ;; managed .org file with `:wylie:', `:script:', bilingual DE // EN
    ;; gloss, and — once the zettel-in-translation-workflow feature
    ;; ships (see docs/feature-zettel-workflow.org) — Claude-cached
    ;; explanations and 84000 Definitions excerpts.
    ;;
    ;; These entries mirror the `C-c u z' prefix map in
    ;; `config/tibetan-keybindings.el'; whichever affordance the user
    ;; reaches for first, the same command fires.
    ;; ========================================================================
    ("Zettelkasten / Thesaurus"
     ["Edit Zettel at Point (C-c u z e)" tibetan-thesaurus-edit-at-point
      :help "Open the zettel for the term under cursor — works in the Interlinear Gloss or Detailed Dictionary section of an analysis file"
      :active (fboundp 'tibetan-thesaurus-edit-at-point)]
     ["New Zettel from Point (C-c u z n)" tibetan-thesaurus-new-entry-interactively
      :help "Create a new zettel, pre-filling wylie + script from the term under cursor"
      :active (fboundp 'tibetan-thesaurus-new-entry-interactively)]
     "---"
     ["Reload Zettel Index (C-c u z r)" tibetan-thesaurus-reload
      :help "Force rebuild of the zettel lookup table (automatic after any edit; use when edits happened outside Emacs)"
      :active (fboundp 'tibetan-thesaurus-reload)]
     ["Initialize from Kramer Glossary (C-c u z i)" tibetan-thesaurus-initialize-from-kramer
      :help "One-time: import Kramer's printed glossary (*kramer-glossary*.org) into the zettelkasten as seed entries"
      :active (fboundp 'tibetan-thesaurus-initialize-from-kramer)]
     "---"
     ["Audit Folder Consistency (C-c u z a)" tibetan-thesaurus-audit-folder-display
      :help "Walk every seg-*.org in a folder; flag segments whose Interlinear gloss for a term doesn't match the zettel"
      :active (fboundp 'tibetan-thesaurus-audit-folder-display)]
     ["Rerun Segments Affected by Zettel (C-c u z R)" tibetan-thesaurus-rerun-affected-by-zettel
      :help "After editing a zettel, re-analyse only the segments that reference it — avoids a full `C-c u r' batch"
      :active (fboundp 'tibetan-thesaurus-rerun-affected-by-zettel)]
     ["Translation-Gaps Report (C-c u z g)" tibetan-thesaurus-translation-gaps-display
      :help "List every segment whose referenced zettel has `[to be researched]' or an empty target-lang gloss"
      :active (fboundp 'tibetan-thesaurus-translation-gaps-display)]
     "---"
     ["Set Source Target Language (C-c u z L)" tibetan-analysis-set-source-target-lang
      :help "Set the current source file's `#+TIBETAN_TARGET_LANG:' header (de / en) — drives which half of bilingual glosses surfaces"
      :active (fboundp 'tibetan-analysis-set-source-target-lang)]
     "---"
     ["Auto-Create Zettels for Buddhist Terms (C-c u z B)"
      tibetan-zettel-auto-create-from-current-analysis
      :help "Phase 3: walk the current analysis buffer's `*** Buddhist Terms' subsection; for every <term>-tagged token without a zettel, offer to create one seeded with the 84000 Definitions body"
      :active (fboundp 'tibetan-zettel-auto-create-from-current-analysis)]
     ["Migrate Pass-5b Thesaurus → Zettelkasten (C-c u z M)"
      tibetan-zettel-migrate-thesaurus
      :help "Phase 6: one-shot import of legacy Kramer-format zettels at ~/Documents/tibetan-thesaurus/ into v2 zettels under knowledge/zettelkasten/.  Idempotent — re-runs skip already-migrated terms.  C-u for dry-run."
      :active (fboundp 'tibetan-zettel-migrate-thesaurus)]
     "---"
     ["Open Zettelkasten Folder" (lambda () (interactive)
                                   (dired "~/buddhist-studies/knowledge/zettelkasten/"))
      :help "Jump into the zettelkasten directory (Denote-managed)"])
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
      :active (fboundp 'tibetan-mark-sentence-start)]
     "---"
     ["Re-segment Source (C-c s Z)" tibetan-sentence-resegment
      :help "Archive old sent-*.org, reset structure, re-run auto-segmenter, create fresh sent-NNN.org"
      :active (fboundp 'tibetan-sentence-resegment)]
     ["Archive sent-*.org (C-c s X)" tibetan-sentence-archive-analysis-folder
      :help "Move sent-*.org files into analysis/archive/<timestamp>/ (step 1 of resegment)"
      :active (fboundp 'tibetan-sentence-archive-analysis-folder)]
     ["Reset Sentence Structure (C-c s U)" tibetan-sentence-reset-structure
      :help "Remove `*** Sentence' headings and re-promote `**** Segment' (step 2 of resegment)"
      :active (fboundp 'tibetan-sentence-reset-structure)]
     ["Create All sent-NNN.org (C-c s N)" tibetan-sentence-create-all
      :help "Scaffold sent-NNN.org for every `*** Sentence N' heading (step 4 of resegment)"
      :active (fboundp 'tibetan-sentence-create-all)])
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
