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
;; BATCH SEGMENT ANALYSIS - C-c u B
;; ============================================================================

(global-set-key (kbd "C-c u B") 'tibetan-auto-analyze-document)
  ;; Analyze ALL segments in the current buffer:
  ;; - Finds all *** Segment N headings
  ;; - Creates analysis file for each (in analysis/ folder)
  ;; - Prompts: [n] new only, [r] re-analyze existing, [c] cancel
  ;; - Re-analyze preserves your notes, translation, footnotes
  ;; - Shows progress and summary when done
  ;; - Also available via Menu: Tibetan > Batch Analyze All Segments

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
;; CAT TRANSLATION - C-c u t / C-c u T / C-c u g
;; ============================================================================

(global-set-key (kbd "C-c u t") 'tibetan-cat-insert-translation)
  ;; Generate CAT-suggested translation:
  ;; - Uses vocabulary glosses + grammatical structure
  ;; - Reorders SOV → SVO for English word order
  ;; - Produces a "scholar's rough draft"
  ;; - Works in analysis buffers (C-c u A)

(global-set-key (kbd "C-c u g") 'tibetan-cat-insert-translation)
  ;; Alias for C-c u t - Generate translation
  ;; "u g" = "utilities: generate translation"

(global-set-key (kbd "C-c u T") 'tibetan-cat-translate-region)
  ;; Translate selected region:
  ;; - Select Tibetan text, then C-c u T
  ;; - Shows translation in minibuffer

;; ============================================================================
;; MITRA AI TRANSLATION - C-c u m / C-c u M
;; ============================================================================

(global-set-key (kbd "C-c u m") 'tibetan-mitra-translate-dwim)
  ;; Translate using Gemma-2-Mitra-E AI model:
  ;; - Region if active, else current segment
  ;; - Requires backend setup (Ollama, HuggingFace, or local server)
  ;; - Run M-x tibetan-mitra-setup-ollama for instructions

(global-set-key (kbd "C-c u M") 'tibetan-mitra-check-status)
  ;; Check Mitra backend status:
  ;; - Shows if backend is configured and available
  ;; - Helps debug connection issues

;; ============================================================================
;; DHARMAMITRA IN ANALYSIS FILES - C-c u D
;; ============================================================================

(global-set-key (kbd "C-c u D") 'tibetan-refresh-dharmamitra-translation)
  ;; Re-request DharmaMitra translation in an analysis file:
  ;; - Run from within analysis file (seg-XXX.org)
  ;; - Fetches fresh translation from DharmaMitra API
  ;; - Updates the "- DharmaMitra:" line
  ;; - Useful if original request failed or timed out

(global-set-key (kbd "C-c u W") 'tibetan-copy-dharmamitra-to-working)
  ;; Copy DharmaMitra translation to Working Translation section:
  ;; - Copies DharmaMitra suggestion to your working area
  ;; - Gives you a starting point for your own translation

;; ============================================================================
;; DISPLAY SETTINGS - C-c u +/- (font size)
;; ============================================================================

(global-set-key (kbd "C-c u +") 'tibetan-increase-text-scale)
  ;; Increase Tibetan text size

(global-set-key (kbd "C-c u -") 'tibetan-decrease-text-scale)
  ;; Decrease Tibetan text size

(global-set-key (kbd "C-c u =") 'tibetan-set-text-scale)
  ;; Set exact Tibetan text scale factor

(defun tibetan-increase-text-scale ()
  "Increase Tibetan text scale by 0.1."
  (interactive)
  (tibetan-set-text-scale (+ (or tibetan-text-scale-factor 1.4) 0.1)))

(defun tibetan-decrease-text-scale ()
  "Decrease Tibetan text scale by 0.1 (minimum 1.0)."
  (interactive)
  (tibetan-set-text-scale (max 1.0 (- (or tibetan-text-scale-factor 1.4) 0.1))))

;; ============================================================================
;; SENTENCE STRUCTURE - C-c s S / C-c s s
;; ============================================================================

(global-set-key (kbd "C-c s S") 'tibetan-add-sentence-structure)
  ;; Add sentence structure to document:
  ;; - Analyzes segment endings to detect sentence boundaries
  ;; - Inserts ** Sentence N headings above segments
  ;; - Modifies segment headings from *** to ****
  ;; - Works best with segments that end with sentence-final particles

(global-set-key (kbd "C-c s s") 'tibetan-detect-sentence-boundaries)
  ;; Preview where sentence boundaries would be:
  ;; - Non-destructive analysis
  ;; - Shows which segments would start new sentences
  ;; - Run before tibetan-add-sentence-structure to review

(global-set-key (kbd "C-c s m") 'tibetan-mark-sentence-start)
  ;; Manually mark current segment as sentence start:
  ;; - Use when automatic detection misses a boundary
  ;; - Inserts sentence heading and demotes segment

;; ============================================================================
;; DOCUMENT PREPARATION - C-c u P / C-c u Y
;; ============================================================================

(global-set-key (kbd "C-c u P") 'tibetan-prepare-document)
  ;; Prepare a new Tibetan document for translation:
  ;; - Paste raw Tibetan text into a buffer
  ;; - Run C-c u P to create org structure:
  ;;   ** Sentence N
  ;;   *** Segment N
  ;;   tibetan text...
  ;; - Automatically groups segments into sentences
  ;; - Then use C-c u B to batch-analyze all segments

(global-set-key (kbd "C-c u Y") 'tibetan-prepare-document)
  ;; Alias for C-c u P (mnemonic: "Y" = clean/Yes, prepare this)
  ;; Replaces old tibetan-clean-auto-segment function

;; ============================================================================
;; FUTURE KEYBINDINGS (commented out - not yet implemented in modular system)
;; ============================================================================

;; Navigation
;; (global-set-key (kbd "C-c u n") 'tibetan-next-segment)
;; (global-set-key (kbd "C-c u p") 'tibetan-previous-segment)

;; Segment manipulation
;; (global-set-key (kbd "C-c u d") 'tibetan-split-segment)

;; File operations
;; (global-set-key (kbd "C-c u x") 'extract-any-tibetan-text)
;; (global-set-key (kbd "C-c u o") 'open-tibetan-texts)

(provide 'tibetan-keybindings)
;;; tibetan-keybindings.el ends here
