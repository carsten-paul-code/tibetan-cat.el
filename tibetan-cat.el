;;; tibetan-cat.el --- Tibetan Computer-Assisted Translation System -*- lexical-binding: t -*-

;; Author: Carsten Paul <post@carstenpaul.de>
;; Maintainer: Carsten Paul <post@carstenpaul.de>
;; URL: https://github.com/carsten-paul-code/tibetan-cat.el
;; Version: 2.1.0
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Keywords: languages, tibetan, translation, tools, buddhism

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Main entry point for Emacs Tibetan CAT tools
;; Provides segment analysis, grammatical analysis, translation workspace, and philology tools
;;
;; Features:
;; - Segment analysis (C-c u i) - Comprehensive analysis in side window
;; - Sentence workspace (C-c s w) - Editable translation workspace
;; - Auto-analysis mode (C-c u E) - Automatically update analysis
;; - Vocabulary lookup with DharmaMitra fallback
;; - Bialek grammar analysis (Tibetisch III classroom focus)
;; - Translation suggestions based on vocabulary + grammar
;; - Verse philology tools (7-syllable meter, metrical fillers)
;; - Madhyamaka terminology database (90+ terms)
;; - Text classification (classical, madhyamaka-verse, kagyu-verse, etc.)
;; - Wylie transliteration for reading aloud
;;
;; Text Classification:
;; Add header to document: #+TIBETAN_TEXT_TYPE: classical | madhyamaka-verse
;; - classical: Uses Bialek grammar for prose texts
;; - madhyamaka-verse: Uses philology tools for verse texts
;;
;; Installation:
;;   (add-to-list 'load-path "~/emacs-tibetan-cat/")
;;   (require 'tibetan-cat)
;;
;; Dependencies:
;; - DharmaMitra API (optional, for vocabulary fallback)
;; - Comprehensive glossaries (17,777 entries)

;;; Code:

;; ============================================================================
;; LOAD PATH SETUP
;; ============================================================================

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  ;; Add base dir and all subdirectories to load path
  (add-to-list 'load-path base-dir)
  (add-to-list 'load-path (expand-file-name "core" base-dir))
  (add-to-list 'load-path (expand-file-name "analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "persist" base-dir))    ; Persistent analysis
  (add-to-list 'load-path (expand-file-name "workspace" base-dir))
  (add-to-list 'load-path (expand-file-name "philology" base-dir))
  (add-to-list 'load-path (expand-file-name "doc-prep" base-dir))   ; Document preparation
  (add-to-list 'load-path (expand-file-name "config" base-dir))
  (add-to-list 'load-path (expand-file-name "setup" base-dir))      ; Setup & installer
  (add-to-list 'load-path (expand-file-name "data" base-dir))       ; Bundled glossary loader

  ;; Set data directory for glossaries
  (defvar tibetan-cat-data-dir (expand-file-name "data" base-dir)
    "Directory containing Tibetan CAT data files (glossaries, etc.)")

  ;; Load bundled glossaries (self-contained, no external paths needed)
  (require 'tibetan-glossary-loader))

;; ============================================================================
;; LOAD CORE MODULES
;; ============================================================================

(require 'tibetan-utils)          ; Utility functions
(require 'tibetan-wylie)          ; Wylie transliteration
(require 'tibetan-vocabulary)     ; Vocabulary lookup with DharmaMitra
(require 'tibetan-vocabulary-detailed nil t) ; Detailed dictionary entries
(require 'tibetan-org-structure)  ; Org-mode structure support (new format)
(require 'tibetan-text-classifier) ; Text type classification (NEW)

;; DharmaMitra HTTP client (Phase 1 of dharmamitra-realign workflow,
;; 2026-04-27).  Provides chat-translate (SSE-streaming) and primary
;; semantic search.  Soft-required — missing module does not break
;; loading.  Used by the upcoming realign command which corrects the
;; rough daṇḍa-split alignment of Sanskrit-Tibetan parallels in
;; gotrapatala.org and similar parallel-mode documents.
(require 'tibetan-dharmamitra-api nil t)

;; DharmaMitra alignment orchestrator (Phase 2 of dharmamitra-realign,
;; 2026-04-27).  Per-segment translate → search pipeline that returns
;; ranked Sanskrit candidates for a Tibetan segment.  Soft-required;
;; depends on `tibetan-dharmamitra-api' (also soft).
(require 'tibetan-sanskrit-parallel-dharmamitra nil t)

;; DharmaMitra as a translator alongside Claude (Phase A.1 of
;; multi-translator-parallel-reading, 2026-04-30).  Adds a
;; `* DharmaMitra Translation (Tibetan)' section to each per-segment
;; analysis file, fired from the same `C-c u A' / `C-c u B' /
;; `C-c u r' paths as Claude.  Soft-required.
(require 'tibetan-dharmamitra-translation nil t)

;; Sanskrit-parallel reading bridge (Phase 1, 2026-04-27).  Read-only
;; primitives: walker for `**** Sanskrit' siblings + source-mode
;; predicate (`#+SOURCE_MODE: parallel-sanskrit').  Soft-required —
;; missing module does not break loading; the analysis pipeline
;; treats the document as Tibetan-only.  Future Sanskrit CAT will
;; consume the same primitives.
(require 'tibetan-sanskrit-parallel nil t)

;; ============================================================================
;; LOAD ANALYSIS MODULES
;; ============================================================================

;; Verb classification (Hill 2010)
(require 'tibetan-verb-classifier)      ; Verb stems, transitivity, case frames
(require 'tibetan-translation-engine)   ; CAT-suggested translation generation

;; Bialek grammar system (for classical prose)
(require 'tibetan-particles-bialek)    ; Bialek-based grammar analysis
(require 'tibetan-translation-suggest)  ; Translation suggestion engine
(require 'tibetan-classroom)            ; Segment analysis (main classroom tool)

;; Enhanced parsing (Phase 1 improvements)
(require 'tibetan-enhanced-parser)      ; Multi-word units, accurate particle detection
(require 'tibetan-enhanced-display)     ; Enhanced analysis display
(require 'tibetan-clause-segmenter)     ; Round-2: clauses + NPs + argument structure

;; Interlinear gloss + Particle Overview (Bialek Portfolio integration)
(require 'tibetan-interlinear nil t)    ; Interlinear Wylie with glosses + particle overview

;; AI Translation (optional - soft load)
(require 'tibetan-mitra-translation nil t)  ; Gemma-2-Mitra-E integration (Ollama/HuggingFace)

;; Philology modules (for verse texts)
(require 'tibetan-verse-philology)      ; Verse meter, metrical fillers
(require 'tibetan-madhyamaka-terms)     ; Madhyamaka vocabulary

;; ============================================================================
;; LOAD WORKSPACE MODULES
;; ============================================================================

(require 'tibetan-sentence-workspace)  ; Sentence workspace generation

;; ============================================================================
;; LOAD PERSISTENCE MODULES
;; ============================================================================

(require 'tibetan-claude-queue)        ; Throttled Claude request queue (concurrency cap + 429 retry)
(require 'tibetan-analysis-persist)    ; Persistent segment analysis (C-c u A / C-c u R)
(require 'tibetan-analysis-sanskrit nil t)  ; Sanskrit-side Claude pipeline (Phase 2)
(require 'tibetan-analysis-combined nil t)  ; Combined-synthesis Claude pipeline (Phase 4)
(require 'tibetan-analysis-combine)    ; Combined per-document analysis (C-c u C)
(require 'tibetan-sentence-persist)    ; Persistent sentence analysis (C-c s A / C-c s R / C-c s r)
(require 'tibetan-compound-analysis)   ; Persistent compound analysis (C-c v A / C-c v R)
(require 'tibetan-clause-analysis)     ; Clause analysis (converbs, main verbs)
(require 'tibetan-auto-analysis)       ; Auto-analyze document (C-c u B)
(require 'tibetan-structure-reorg)     ; Reorganize analysis files (C-c u O / C-c u U)

;; ============================================================================
;; LOAD DOCUMENT DISPLAY & PREPARATION MODULES
;; ============================================================================

(require 'tibetan-doc-display)         ; Display settings for prepared documents
(require 'tibetan-doc-format nil t)    ; Document formatting (segmentation at shad)
(require 'tibetan-ocr-validate nil t)  ; OCR syllable validator (depends on data/dictionaries)
(require 'tibetan-ocr-correct nil t)   ; Claude-driven OCR correction
(condition-case err
    (require 'tibetan-doc-prep)        ; Document preparation wizard (OCR, validate, format)
  (error (message "⚠ tibetan-doc-prep failed: %s" (error-message-string err))))
(require 'tibetan-sentence-structure)      ; Sentence structure tools

;; ============================================================================
;; CONFIGURATION — BIALEK PORTFOLIO
;; ============================================================================

;; Path to the Bialek Portfolio org file for Particle Overview generation.
;; The interlinear gloss works without it (using inline Bialek data), but
;; the Particle Overview section gains Portfolio excerpts when this is set.
(when (boundp 'tibetan-interlinear-portfolio-file)
  (setq tibetan-interlinear-portfolio-file
        (expand-file-name
         "~/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/WS25-26/Hausarbeiten/Tibetisch III/Hausarbeit_Tibetisch_III.org")))

;; ============================================================================
;; CONFIGURATION — THESAURUS (Pass 5b)
;; ============================================================================

;; The thesaurus is a user-editable multilingual glossary — Sanskrit,
;; Wylie, English, German — stored as one org-zettel per term.  Lookup
;; during vocabulary analysis surfaces thesaurus entries at rank 1
;; (above Resources / corpus-specific / Hopkins / RY / everything else)
;; so the student's chosen translation stays consistent across every
;; analysis in a document AND across related documents.
;;
;; To seed from Kramer's glossary on first use:
;;   M-x tibetan-thesaurus-initialize-from-kramer
;; Subsequent edits to thesaurus zettels are the user's own.
(when (boundp 'tibetan-thesaurus-directory)
  (setq tibetan-thesaurus-directory
        (expand-file-name
         "~/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/thesaurus/")))

(when (boundp 'tibetan-thesaurus-kramer-source-directory)
  (setq tibetan-thesaurus-kramer-source-directory
        (expand-file-name
         ;; Moved 2026-04-24 under `knowledge/' as part of the buddhist-
         ;; studies tree reorganisation that pulls notes out from the
         ;; root.  Old path `.../buddhist-studies/zettelkasten/' — the
         ;; directory itself was `git mv'd, IDs/Denote filenames
         ;; unchanged, so existing thesaurus zettels keep working.
         "~/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/knowledge/zettelkasten/")))

;; Thesaurus init is more specific than `*.org' in the Kramer source
;; directory (the zettelkasten holds many non-Kramer files too).  The
;; default Thesaurus-directory file pattern is `*.org' because after
;; `initialize-from-kramer' copies only the Kramer files, every org
;; file in the thesaurus dir is by construction a thesaurus entry.

;; ============================================================================
;; LOAD KEYBINDINGS
;; ============================================================================

(require 'tibetan-keybindings)

;; ============================================================================
;; LOAD MENU
;; ============================================================================

(require 'tibetan-menu)

;; ============================================================================
;; INITIALIZATION
;; ============================================================================

;; Forward declaration so the byte-compiler sees `tibetan-cat-version' at
;; the point it's referenced below.  The authoritative defconst lives
;; further down under ";; VERSION INFO".
(defvar tibetan-cat-version)

;;;###autoload
(defun tibetan-cat-setup ()
  "Setup Tibetan CAT system.
Loads glossaries and prepares the system for use."
  (interactive)
  (let ((buf (get-buffer-create "*Tibetan CAT*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "═══════════════════════════════════════════════════════════════════\n")
      (insert (format "  Tibetan CAT v%s - Computer-Assisted Translation System\n" tibetan-cat-version))
      (insert "═══════════════════════════════════════════════════════════════════\n\n")

      (insert "SEGMENT (line) ANALYSIS:\n")
      (insert "  C-c u i   Segment analysis (Bialek grammar + verb stems)\n")
      (insert "  C-c u I   Enhanced segment analysis (improved parsing)\n")
      (insert "  C-c u A   Persistent segment analysis (with notes, footnotes)\n")
      (insert "  C-c u R   Re-analyze segment (preserves your notes)\n")
      (insert "\n")

      (insert "SENTENCE ANALYSIS (groups multiple segments):\n")
      (insert "  C-c s A   Persistent sentence analysis (Roehrich + Claude discourse)\n")
      (insert "  C-c s R   Re-analyze sentence (preserves your notes; C-u re-runs Claude)\n")
      (insert "  C-c s r   Batch re-analyze all sentences\n")
      (insert "\n")

      (insert "COMPOUND (verse/sentence) ANALYSIS:\n")
      (insert "  C-c v v   Quick verse analysis (meter + vocab)\n")
      (insert "  C-c v A   Persistent compound analysis (verse/sentence)\n")
      (insert "  C-c v R   Re-analyze compound (preserves your notes)\n")
      (insert "\n")

      (insert "CAT TRANSLATION:\n")
      (insert "  C-c u t   Generate CAT translation (in analysis buffer)\n")
      (insert "  C-c u T   Translate selected region\n")
      (insert "\n")

      (insert "MITRA AI TRANSLATION:\n")
      (insert "  C-c u m   Mitra AI translate (region or segment)\n")
      (insert "  C-c u M   Check Mitra backend status\n")
      (insert "\n")

      (insert "DOCUMENT PREPARATION:\n")
      (insert "  C-c u P   Prepare document (create segments + sentences structure)\n")
      (insert "  C-c u B   Batch auto-analyze all segments and sentences\n")
      (insert "  C-c u O   Reorganize analysis files (after structure changes)\n")
      (insert "  C-c u U   Preview reorganization (dry run)\n")
      (insert "  M-x tibetan-doc-prep   3-step workflow (OCR → AI correct → format)\n")
      (insert "\n")

      (insert "WORKSPACE & NAVIGATION:\n")
      (insert "  C-c s w   Sentence workspace (editable translation workspace)\n")
      (insert "  C-c u E   Toggle auto-analysis mode (or C-c u e)\n")
      (insert "  C-c u v   Reload all glossaries\n")
      (insert "\n")

      (insert "CLAUDE REQUEST QUEUE (throttling + 429 retry):\n")
      (insert "  M-x tibetan-claude-queue-show-status     Show pending/in-flight\n")
      (insert "  M-x tibetan-claude-queue-cancel-pending  Drop queued requests\n")
      (insert "  M-x tibetan-claude-queue-reset-stats     Zero lifetime counters\n")
      (insert "\n")

      (insert "───────────────────────────────────────────────────────────────────\n")
      (insert "DOCUMENT CONTEXT (add to header):\n")
      (insert "  #+TIBETAN_TEXT_TYPE: classical | madhyamaka-verse | kagyu-verse\n")
      (insert "  #+TIBETAN_CONTEXT: bhutan-kagyu-madhyamaka | gelug-madhyamaka\n")
      (insert "───────────────────────────────────────────────────────────────────\n")
      (insert "\n")
      (insert "All functions also available via the 'Tibetan' menu in the menu bar.\n")

      (goto-char (point-min))
      (read-only-mode 1)
      (special-mode))
    (display-buffer buf '(display-buffer-pop-up-window))
    (message "Tibetan CAT v%s initialized. See *Tibetan CAT* buffer for keybindings." tibetan-cat-version)))

;; To see keybinding summary, run: M-x tibetan-cat-setup
;; (tibetan-cat-setup)  ; Disabled - run manually if needed

;; ============================================================================
;; VERSION INFO
;; ============================================================================

(defconst tibetan-cat-version "2.1.0"
  "Version of Tibetan CAT system.")

;;;###autoload
(defun tibetan-cat-version ()
  "Display Tibetan CAT version and feature summary."
  (interactive)
  (message "Tibetan CAT v%s - Classroom & Philology Edition" tibetan-cat-version)
  (message "Features:")
  (message "  - Segment analysis (Bialek grammar)")
  (message "  - Translation suggestions")
  (message "  - Verse philology tools (7-syllable meter)")
  (message "  - Madhyamaka terminology (90+ terms)")
  (message "  - Text classification (classical, verse, etc.)")
  (message "Authors: Developed for Buddhist Studies classroom use"))

(provide 'tibetan-cat)
;;; tibetan-cat.el ends here
