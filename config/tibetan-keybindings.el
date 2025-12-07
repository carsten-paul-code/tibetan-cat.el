;;; tibetan-keybindings.el --- All Tibetan CAT keybindings in one place -*- lexical-binding: t -*-

;;; Commentary:
;; Centralized keybindings for Tibetan Computer-Assisted Translation system
;; All keybindings use the C-c u (Tibetan utilities) and C-c s (sentence) prefixes

;;; Code:

;; ============================================================================
;; SEGMENT ANALYSIS - C-c u i / C-c u I / C-c u E
;; ============================================================================

(global-set-key (kbd "C-c u i") 'tibetan-segment-info)
  ;; Show comprehensive segment analysis in RIGHT window:
  ;; - Tibetan text
  ;; - Wylie transliteration
  ;; - DharmaMitra translation
  ;; - Vocabulary with meanings
  ;; - Context-aware grammatical analysis
  ;; - Verb classification (Hill 2010)

(global-set-key (kbd "C-c u I") 'tibetan-segment-info-enhanced)
  ;; Show ENHANCED segment analysis with improved parsing:
  ;; - Multi-word compound recognition (གླེང་གཞི = nidāna)
  ;; - Proper noun identification (མཉན་ཡོད = Śrāvastī)
  ;; - Accurate particle detection (only at word boundaries)
  ;; - Context-filtered verb analysis (no false positives)
  ;; - Clearer output format
  ;;
  ;; Use this for better accuracy on complex texts!

(global-set-key (kbd "C-c u E") 'tibetan-toggle-auto)
  ;; Toggle auto-analysis mode
  ;; When enabled, analysis updates automatically as you navigate

(global-set-key (kbd "C-c u e") 'tibetan-toggle-auto)
  ;; Alias for C-c u E (lowercase e also works)

;; ============================================================================
;; SENTENCE WORKSPACE - C-c s w
;; ============================================================================

(global-set-key (kbd "C-c s w") 'tibetan-prepare-sentence)
  ;; Create sentence workspace in BELOW window:
  ;; - Line-by-line Tibetan/Wylie/Vocabulary
  ;; - Context-aware grammatical analysis per segment
  ;; - Translation and notes sections

;; ============================================================================
;; WORKSPACE EDITING (active in workspace buffers)
;; ============================================================================

;; Note: These are typically bound via local keymaps within workspace mode
;; (global-set-key (kbd "C-c C-c") 'tibetan-save-workspace)
;; (global-set-key (kbd "C-c e p") 'tibetan-export-workspace-pdf)

;; ============================================================================
;; VOCABULARY - C-c u v / C-c u +
;; ============================================================================

(global-set-key (kbd "C-c u v") 'reload-all-glossaries)
  ;; Reload all glossaries including Hopkins, Bialek, and others

;; (global-set-key (kbd "C-c u +") 'add-tibetan-vocabulary)
  ;; Add new vocabulary entry (if function exists)

;; ============================================================================
;; VERSE ANALYSIS - C-c v v
;; ============================================================================

(global-set-key (kbd "C-c v v") 'tibetan-analyze-current-verse-interactive)
  ;; Analyze entire verse block at point:
  ;; - Syllable counting and meter validation (7-syllable)
  ;; - Metrical filler detection
  ;; - Vocabulary for all lines
  ;; - Madhyamaka terminology identification
  ;; - Translation workspace
  ;;
  ;; Works with verse structure:
  ;;   〔verse:NNN〕
  ;;   〔seg:...〕line 1〔/seg〕
  ;;   〔seg:...〕line 2〔/seg〕
  ;;   ...

;; ============================================================================
;; PERSISTENT SEGMENT ANALYSIS - C-c u A / C-c u R
;; ============================================================================

(global-set-key (kbd "C-c u A") 'tibetan-open-segment-analysis)
  ;; Open or create persistent analysis for current segment:
  ;; - Opens in side window (right)
  ;; - Creates analysis/ folder if needed
  ;; - Generates auto-analysis on first open
  ;; - Warns if source text changed since last analysis
  ;; - Analysis file has sections for your notes, translation, footnotes

(global-set-key (kbd "C-c u R") 'tibetan-reanalyze-segment)
  ;; Re-analyze current segment:
  ;; - Regenerates Auto-Analysis section
  ;; - PRESERVES your notes, translation, and footnotes
  ;; - Updates hash and last-analyzed date

;; ============================================================================
;; PERSISTENT COMPOUND ANALYSIS - C-c v A / C-c v R
;; ============================================================================

(global-set-key (kbd "C-c v A") 'tibetan-open-compound-analysis)
  ;; Open or create persistent COMPOUND (verse/sentence) analysis:
  ;; - Detects compound boundaries automatically (verse numbers, double shad, meter)
  ;; - Or use with active region to analyze selected lines
  ;; - Aggregates line-by-line analysis
  ;; - Inter-line grammar (how lines connect: converbs, conjunctions)
  ;; - Topic/subject flow across lines
  ;; - Context-aware (set #+TIBETAN_CONTEXT: bhutan-kagyu-madhyamaka)
  ;; - Madhyamaka terminology identification
  ;; - Sections for: working translation, notes, commentary, footnotes

(global-set-key (kbd "C-c v R") 'tibetan-reanalyze-compound)
  ;; Re-analyze current compound:
  ;; - Must be called from within a compound analysis buffer
  ;; - Regenerates Auto-Analysis section
  ;; - PRESERVES your translation, notes, commentary, footnotes
  ;; - Updates hash and last-analyzed date

;; ============================================================================
;; CAT TRANSLATION - C-c t g
;; ============================================================================

(global-set-key (kbd "C-c t g") 'tibetan-cat-insert-translation)
  ;; Generate CAT-suggested translation:
  ;; - Uses vocabulary glosses + grammatical structure
  ;; - Reorders SOV → SVO for English word order
  ;; - Produces a "scholar's rough draft"
  ;; - Works in analysis buffers (C-c u A)

(global-set-key (kbd "C-c t r") 'tibetan-cat-translate-region)
  ;; Translate selected region:
  ;; - Select Tibetan text, then C-c t r
  ;; - Shows translation in minibuffer

;; ============================================================================
;; FUTURE KEYBINDINGS (commented out - not yet implemented in modular system)
;; ============================================================================

;; Navigation
;; (global-set-key (kbd "C-c u n") 'tibetan-next-segment)
;; (global-set-key (kbd "C-c u p") 'tibetan-previous-segment)

;; Segment manipulation
;; (global-set-key (kbd "C-c u m") 'tibetan-merge-segments)
;; (global-set-key (kbd "C-c u d") 'tibetan-split-segment)

;; Translation
;; (global-set-key (kbd "C-c u t") 'tibetan-translate-segment)

;; File operations
;; (global-set-key (kbd "C-c u x") 'extract-any-tibetan-text)
;; (global-set-key (kbd "C-c u o") 'open-tibetan-texts)

(provide 'tibetan-keybindings)
;;; tibetan-keybindings.el ends here
