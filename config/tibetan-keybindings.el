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

;; (global-set-key (kbd "C-c u +") 'add-to-tibetan-vocabulary)
  ;; Add new vocabulary entry.  Defined in data/tibetan-glossary-loader.el.
  ;; Enable by uncommenting the line above.

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

(global-set-key (kbd "C-c u r") 'tibetan-analysis-batch-reanalyze)
  ;; Batch re-analyze ALL analysis files in the analysis folder:
  ;; - Iterates over every seg-NNN*.org in analysis/ (in order)
  ;; - Regenerates each Auto-Analysis section
  ;; - PRESERVES My Notes, Working Translation, Footnotes
  ;; - PRESERVES existing *** Claude translation (unless you opt in
  ;;   to re-request, which will fan out N async Claude calls)
  ;; - Reports progress and summary when done

;; Paragraph analysis (`** §N' subtrees with `*** Tibetisch' child, the
;; Rgyan-comparative.org layout) is dispatched automatically from C-c u A
;; and C-c u R — they detect paragraph context and route to
;; `tibetan-open-paragraph-analysis' / `tibetan-reanalyze-paragraph'.
;; No separate prefix needed (C-c p collides with Projectile).

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
;; TRANSLATION COMPARISON - C-c u T
;; ============================================================================

(global-set-key (kbd "C-c u T") 'tibetan-translation-comparison-refresh)
  ;; Refresh the `* Translation Comparison' section of the current
  ;; par-NNN.org analysis file:
  ;; - Collects Lopez 2006 / Wangjié & Mulligan / DharmaMitra / etc.
  ;;   from `* Reference Translations' AND the user's own
  ;;   `* Working Translation' (if non-empty)
  ;; - Asks Claude for a pairwise similarity matrix (0 = essentially
  ;;   incomparable, 1.00 = identical) and a diagnostic explaining
  ;;   substantive divergences
  ;; - Writes the result back as an org-table + prose between
  ;;   Working Translation and Auto-Analysis
  ;; - Idempotent: existing Translation Comparison block is replaced
  ;; - Separate from C-c u R reanalyze (preserved on reanalyze)

;; ============================================================================
;; COMBINED DOCUMENT - C-c u C
;; ============================================================================

(global-set-key (kbd "C-c u C") 'tibetan-analysis-combine-document)
  ;; Stitch every seg-NNN*.org under analysis/ into one combined.org:
  ;; - Per-segment body: Tibetan Text + Wylie + Particle Map + Interlinear
  ;;   Gloss + Verb Classification + Claude Translation + Claude Grammar
  ;; - Appendix A: consolidated Grammatical Markers (deduped, back-refs)
  ;; - Appendix B: consolidated Detailed Dictionary (deduped, back-refs)
  ;; - Writes analysis/combined.org and opens it in a side window.
  ;; - Rebuild at any time; overwrites combined.org (edit the per-segment
  ;;   files, not this one).
  ;; - C-u prefix prompts for a different analysis folder.

;; ============================================================================
;; FIRE CLAUDE ON ALL PENDING PLACEHOLDERS - C-c u F
;; ============================================================================
;;
;; Moved 2026-04-24 (bug report: "Claude doesn't fly in").  Previously the
;; command `tibetan-auto-request-claude-translations' was bound to `C-c u C'
;; in `persist/tibetan-auto-analysis.el' (line 570), but this file's
;; `C-c u C' → combine-document binding loads later and silently clobbers
;; it.  The module-level binding is now removed and the command rebound
;; here with a distinct key.
;;
;; `F' for "Fire Claude" — scans the analysis folder for every file whose
;; `** Claude Translation' body is a `[Requesting translation...]' /
;; `[Claude unavailable...]' / `[Claude request failed...]' placeholder
;; (or empty) and queues a fresh Claude request for each.  Use after a
;; batch that partially OTPM'd out, or when you want to rescue segments
;; whose Claude never completed.

(global-set-key (kbd "C-c u F") 'tibetan-auto-request-claude-translations)
  ;; - No prefix: scans the analysis/ folder of the current source file.
  ;; - C-u prefix: force re-fire even for segments that already have a
  ;;   non-placeholder Claude Translation.
  ;; - Requests go through `tibetan-claude-queue' (rate-limit + retry).

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
;; THESAURUS - C-c u z (prefix)
;; ============================================================================
;;
;; Pass 5b (user-editable multilingual glossary at rank 1 of the
;; vocabulary pipeline) + Pass 5b.2 (create / edit entries from an
;; analysis buffer).  Thesaurus entries are org zettels carrying
;; Sanskrit · Wylie · English · German per term; edits propagate to
;; every analysis that references the Wylie key on next reanalysis.
;;
;; Bound under `C-c u z' (zettelkasten) — `t'/`T' are already taken
;; by CAT translation commands.

(defvar tibetan-thesaurus-prefix-map (make-sparse-keymap)
  "Keymap for thesaurus commands — prefix `C-c u z'.")

(define-key tibetan-thesaurus-prefix-map (kbd "e")
  'tibetan-thesaurus-edit-at-point)
  ;; Open the thesaurus zettel for the Wylie on the current line.
  ;; If no entry exists, offers to create one.  Falls back to
  ;; prompting for a Wylie when the line has no bracketed token.

(define-key tibetan-thesaurus-prefix-map (kbd "n")
  'tibetan-thesaurus-new-entry-interactively)
  ;; Create a new thesaurus zettel.  Prompts for the Wylie term;
  ;; defaults to the Wylie on the current line when available.

(define-key tibetan-thesaurus-prefix-map (kbd "r")
  'tibetan-thesaurus-reload)
  ;; Clear the cached thesaurus index — next lookup rebuilds from
  ;; disk.  Call after editing a zettel outside Emacs.

(define-key tibetan-thesaurus-prefix-map (kbd "i")
  'tibetan-thesaurus-initialize-from-kramer)
  ;; One-shot init: copy the 342 Kramer glossary zettels into the
  ;; configured `tibetan-thesaurus-directory'.  Idempotent — pre-
  ;; existing destination files are skipped.

(define-key tibetan-thesaurus-prefix-map (kbd "a")
  'tibetan-thesaurus-audit-folder-display)
  ;; Audit an analysis folder for stale segments — pop up a
  ;; `*Thesaurus Audit*' buffer listing analyses whose LAST_ANALYZED
  ;; date predates a thesaurus zettel's mtime for a term the segment
  ;; contains.  Helps the user see the surface area of a recent
  ;; thesaurus editing session before spending Claude API credits.

(define-key tibetan-thesaurus-prefix-map (kbd "g")
  'tibetan-thesaurus-translation-gaps-display)
  ;; Translation-gap report.  Open `*Thesaurus Gaps*' showing
  ;; thesaurus entries referenced by the analyses in a folder
  ;; whose bilingual DE / EN primary is still a placeholder.
  ;; Sorted by descending frequency — fill the top entries first
  ;; for maximum impact on the rendered document output.
  ;; Primary prep tool when starting a new German-target document.

(define-key tibetan-thesaurus-prefix-map (kbd "L")
  'tibetan-analysis-set-source-target-lang)
  ;; Set `#+TIBETAN_TARGET_LANG:' (de / en) on the current source
  ;; document.  When run from an analysis buffer, resolves the source
  ;; via the buffer's `#+SOURCE:' header; otherwise uses the current
  ;; buffer's file.  The change takes effect on next `C-c u R'.

(define-key tibetan-thesaurus-prefix-map (kbd "P")
  'tibetan-cat-toggle-source-mode-parallel)
  ;; Phase 5 of sanskrit-parallel-workflow (2026-04-27): toggle
  ;; `#+SOURCE_MODE: parallel-sanskrit' on the current source file.
  ;; Sibling of `C-c u z L' (target language) — both manage per-
  ;; document opt-in headers that change downstream rendering and
  ;; Claude prompting.  When ON: the next reanalyse emits a
  ;; `** Sanskrit Source' section above Wylie AND the Claude system
  ;; prompt instructs Sanskrit-primary translation with optional
  ;; `### Tibetan Divergence' notes.  Toggling OFF returns the
  ;; document to today's Tibetan-only behaviour.

(define-key tibetan-thesaurus-prefix-map (kbd "R")
  'tibetan-thesaurus-rerun-affected-by-zettel)
  ;; Re-analyse every segment under an analysis folder whose Tibetan
  ;; Text contains the Wylie key of a specific thesaurus zettel.
  ;; Preserves Claude sections (only the parser-side output is
  ;; refreshed).  Prompts for both the zettel path and the analysis
  ;; folder.

(define-key tibetan-thesaurus-prefix-map (kbd "B")
  'tibetan-zettel-auto-create-from-current-analysis)
  ;; Phase 3 of zettel-in-translation-workflow (2026-04-24): walk the
  ;; current analysis buffer's `*** Buddhist Terms' subsection and
  ;; offer to create a zettel for each term that doesn't already have
  ;; one.  `B' for Buddhist-term auto-create.  Gated by
  ;; `tibetan-zettel-auto-create-on-buddhist-term' (default `ask' —
  ;; per-term y-or-n-p prompt; set to `always' for silent creation).

(define-key tibetan-thesaurus-prefix-map (kbd "M")
  'tibetan-zettel-migrate-thesaurus)
  ;; Phase 6 of zettel-in-translation-workflow (2026-04-26): one-shot
  ;; migration of legacy Pass-5b Kramer-format zettels at
  ;; `~/Documents/tibetan-thesaurus/' into v2 zettels under
  ;; `~/buddhist-studies/knowledge/zettelkasten/'.  Idempotent —
  ;; subsequent runs skip already-migrated terms.  Pass C-u for
  ;; dry-run (reports what would migrate without writing).

(define-key tibetan-thesaurus-prefix-map (kbd "U")
  'tibetan-zettel-update-back-links-from-current-analysis)
  ;; Phase 7 of zettel-in-translation-workflow (2026-04-26): walk the
  ;; current analysis buffer's `[[id:ZETTEL-ID]]' Interlinear links
  ;; (Phase 2's ♦-marker output) and add a back-link to every
  ;; referenced zettel pointing at the current analysis's `:ID:'.
  ;; Idempotent — re-runs dedup against existing entries.  `U' for
  ;; "Update back-links".

(define-key tibetan-thesaurus-prefix-map (kbd "G")
  'tibetan-zettel-gc-back-links)
  ;; Phase 7 of zettel-in-translation-workflow (2026-04-26): GC-walk
  ;; every zettel's `* Back-links' section and prune entries whose
  ;; `[[id:...]]' target is no longer resolvable.  Manual / on-demand
  ;; only — back-link removal is irreversible without grep-bisecting
  ;; history, so we never auto-fire this.  `G' for Garbage-collect.

(global-set-key (kbd "C-c u z") tibetan-thesaurus-prefix-map)

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

;;;###autoload
(defun tibetan-increase-text-scale ()
  "Increase Tibetan text scale by 0.1."
  (interactive)
  (tibetan-set-text-scale (+ (or tibetan-text-scale-factor 1.4) 0.1)))

;;;###autoload
(defun tibetan-decrease-text-scale ()
  "Decrease Tibetan text scale by 0.1 (minimum 1.0)."
  (interactive)
  (tibetan-set-text-scale (max 1.0 (- (or tibetan-text-scale-factor 1.4) 0.1))))

;; ============================================================================
;; SENTENCE STRUCTURE - C-c s S / C-c s s / C-c s m
;; ============================================================================

(global-set-key (kbd "C-c s S") 'tibetan-add-sentence-structure)
  ;; Add sentence structure to document:
  ;; - Analyzes segment endings to detect sentence boundaries
  ;; - Inserts *** Sentence N headings above segments
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
;; PERSISTENT SENTENCE ANALYSIS - C-c s A / C-c s R / C-c s r
;; ============================================================================
;;
;; Sentence-level analogues of the segment-level C-c u A / C-c u R / C-c u r.
;; A "sentence" here groups one or more contiguous segments under a *** Sentence N
;; heading (created by C-c s S).  Each sentence gets its own analysis/sent-NNN.org
;; file holding the Roehrich (or other published) translation, a class translation,
;; the three Claude sections (Translation / Grammar / Context), and free-form
;; working translation, notes, footnotes.

(global-set-key (kbd "C-c s A") 'tibetan-sentence-open-analysis)
  ;; Open or create persistent analysis for the sentence at point:
  ;; - Walks up to the enclosing *** Sentence N heading
  ;; - Creates analysis/sent-NNN.org if missing (with #+SEGMENTS, #+TIBETAN_HASH)
  ;; - Opens in side window (right)
  ;; - Triggers initial Claude discourse-level analysis on first creation
  ;; - Warns if any child segment text changed since last analysis

(global-set-key (kbd "C-c s R") 'tibetan-sentence-reanalyze)
  ;; Re-analyze the current sentence:
  ;; - Regenerates Tibetan Text / Wylie / #+SEGMENTS / #+TIBETAN_HASH
  ;; - PRESERVES Roehrich, Class Translation, Working Translation, My Notes,
  ;;   Footnotes, and any existing Claude Translation/Grammar/Context
  ;; - With C-u prefix: also re-issues the Claude discourse-level request

(global-set-key (kbd "C-c s r") 'tibetan-sentence-batch-reanalyze)
  ;; Batch re-analyze ALL sent-NNN.org files in the analysis folder:
  ;; - Regenerates structural sections from the source file
  ;; - PRESERVES user content as in C-c s R
  ;; - With C-u: also re-issues Claude on every sentence (N async calls)
  ;; - Reports progress and a summary when done

;; ============================================================================
;; RE-SEGMENTATION WORKFLOW - C-c s Z / C-c s X / C-c s N / C-c s U
;; ============================================================================
;;
;; When the sentence boundary detector is upgraded (e.g. the dialogue-framing
;; step added on 2026-04-20) a source file whose structure was laid down by
;; an earlier pass may contain fewer/larger sentences than the new detector
;; would now produce.  Re-running `C-c s S' is a no-op in that state — the
;; sentence headings are already in place and the segment regex only matches
;; three-asterisk `*** Segment' headings, not the `**** Segment' they were
;; demoted to.  These four keys implement a safe archive-and-regenerate
;; workflow:

(global-set-key (kbd "C-c s Z") 'tibetan-sentence-resegment)
  ;; One-shot re-segmentation orchestrator:
  ;;   1. Archive existing sent-*.org into analysis/archive/<timestamp>/
  ;;   2. Reset source structure (remove *** Sentence, re-promote segments)
  ;;   3. Re-run the auto-segmenter (with the current detector)
  ;;   4. Create fresh sent-NNN.org for every new sentence
  ;; Single yes/no gate at the top; sub-command prompts are suppressed.

(global-set-key (kbd "C-c s X") 'tibetan-sentence-archive-analysis-folder)
  ;; Step 1 only: move every sent-*.org into analysis/archive/<timestamp>/.
  ;; seg-*.org and other files are left alone.

(global-set-key (kbd "C-c s U") 'tibetan-sentence-reset-structure)
  ;; Step 2 only: remove `*** Sentence N' headings and re-promote
  ;; `**** Segment M' back to `*** Segment M'.  Does not save — review first.

(global-set-key (kbd "C-c s N") 'tibetan-sentence-create-all)
  ;; Step 4 only: scaffold sent-NNN.org for every `*** Sentence N' heading
  ;; in the source buffer.  Existing files are skipped (not overwritten).

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
