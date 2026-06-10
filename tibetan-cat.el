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
;; SHARED PATHS (canonical zettelkasten path constants)
;; ============================================================================

;; The buddhist-studies project ships a `shared-paths.el' file at
;; ~/buddhist-studies/scripts/zettelkasten/ (via the emacs-zettelkasten
;; submodule).  When available it defines `zk/zettelkasten-directory',
;; `zk/thesaurus-directory', etc. as the single source of truth shared
;; across the main Emacs, the research Emacs, and this CAT tool.
;;
;; Soft-load: if the file is missing (workshop demo on a fresh machine,
;; CI environment, etc.) the configuration blocks below fall back to
;; their pre-shared-paths literal values, so the tool still loads.
(condition-case nil
    (load (expand-file-name
           "~/buddhist-studies/scripts/zettelkasten/shared-paths.el")
          nil t)
  (error nil))

;; ============================================================================
;; LOAD CORE MODULES
;; ============================================================================

(require 'tibetan-utils)          ; Utility functions
(require 'tibetan-wylie)          ; Wylie transliteration
(require 'tibetan-phonetics)      ; Wylie → THL phonetic (class-reading aid)
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
;; §5.21 Commit 4/7 (2026-05-20):  Bialek 2022 published-textbook
;; section refs on per-particle bullets in the merged `***
;; Particles' section.  Soft-required so the analysis file degrades
;; to Portfolio-only refs if the table is missing.
(require 'tibetan-bialek-textbook-refs nil t)
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
(require 'tibetan-sentence-persist)
(require 'tibetan-sentence-claude nil t)   ; §5.40 sentence-level Claude/DM calls    ; Persistent sentence analysis (C-c s A / C-c s R / C-c s r)
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
(require 'tibetan-ocr-runner nil t)    ; OCR pipeline runner (image → text)
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
;;
;; Course-specific path (Tibetisch III, WS25-26).  Not a structural part
;; of the zettelkasten infrastructure, so doesn't get its own constant in
;; shared-paths.el — but we build it off `zk/buddhist-studies-root' when
;; available to localise the only iCloud-prefix string.
(when (boundp 'tibetan-interlinear-portfolio-file)
  (setq tibetan-interlinear-portfolio-file
        (expand-file-name
         "WS25-26/Hausarbeiten/Tibetisch III/Hausarbeit_Tibetisch_III.org"
         (if (boundp 'zk/buddhist-studies-root)
             zk/buddhist-studies-root
           "~/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/"))))

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
        (if (boundp 'zk/thesaurus-directory)
            zk/thesaurus-directory
          (expand-file-name
           "~/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/thesaurus/"))))

(when (boundp 'tibetan-thesaurus-kramer-source-directory)
  (setq tibetan-thesaurus-kramer-source-directory
        ;; Lives under `knowledge/' since 2026-04-24 (buddhist-studies
        ;; tree reorganisation).  Denote IDs unchanged, so existing
        ;; thesaurus zettels keep resolving.  Path comes from
        ;; `zk/zettelkasten-directory' (the canonical constant) when
        ;; shared-paths.el is loaded; otherwise the literal iCloud path.
        (if (boundp 'zk/zettelkasten-directory)
            zk/zettelkasten-directory
          (expand-file-name
           "~/Library/Mobile Documents/com~apple~CloudDocs/buddhist-studies/knowledge/zettelkasten/"))))

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

;; ============================================================================
;; CAT → ZETTEL BRIDGE
;; ============================================================================
;;
;; Open the zettelkasten entry for the Tibetan word under the cursor.
;; When the research Emacs instance is running (separate Emacs process
;; with a server matching `tibetan-cat-zettel-target-server'), the zettel
;; opens THERE via emacsclient — so a dual-monitor workflow can keep CAT
;; translation focus on one screen and zettel-arbeit on the other.
;; Otherwise the zettel opens locally in the CAT Emacs.

(defcustom tibetan-cat-zettel-target-server "research-emacs"
  "Emacs server name of the Research instance for zettel lookups.

When this server is running, `tibetan-cat-open-zettel-for-word-at-point'
routes opens via emacsclient -s <server> so the zettel appears in the
research instance instead of the CAT instance.  Configure the research
instance to start the server with the matching name:

  (require \='server)
  (setq server-name \"research-emacs\")
  (unless (server-running-p) (server-start))

Empty string disables remote routing entirely."
  :type 'string
  :group 'tibetan-cat)

;; Owned by server.el (required at runtime below); declare it special so
;; the byte-compiler doesn't flag it as a free variable.
(defvar server-socket-dir)

(defun tibetan-cat--server-socket-path (server-name)
  "Return the socket path for SERVER-NAME if it exists, else nil.
Uses the `server-socket-dir' variable to resolve the path, then
checks for existence (the file is created by `server-start' and
removed when the server is stopped)."
  (require 'server)
  (when (and server-name (not (string-empty-p server-name)))
    (let ((path (expand-file-name server-name server-socket-dir)))
      (when (file-exists-p path) path))))

;;;###autoload
(defun tibetan-cat-open-zettel-for-word-at-point (&optional arg)
  "Open the zettelkasten entry for the Wylie term under point.

Tries (in order):
  1. `tibetan-thesaurus--wylie-at-point' to read a `[wylie]'-bracket
     token from the current line (Detailed Dictionary / Interlinear
     Gloss layout).
  2. Falls back to a `read-string' prompt when no bracketed token
     is on the line.

Resolves the term through `tibetan-zettel-lookup' which indexes the
zettelkasten by normalised Wylie.

Routing:
  - With prefix arg \\[universal-argument]: open locally via `find-file'.
  - Otherwise: if the research Emacs server is running (socket file at
    \\='(server--socket-dir)/tibetan-cat-zettel-target-server\\='),
    route via `emacsclient --no-wait'.  This sends the zettel to the
    research instance — typical use case is a second monitor.
  - Otherwise (no server, no prefix): open locally via `find-file'.

When the lookup returns nil (no zettel for that Wylie), prompts the
user whether to create one and (if confirmed) delegates to `denote'
in the appropriate instance."
  (interactive "P")
  (require 'tibetan-zettel)
  (require 'server)
  (let* ((wylie (or (and (fboundp 'tibetan-thesaurus--wylie-at-point)
                         (tibetan-thesaurus--wylie-at-point))
                    (read-string "Wylie term: ")))
         (entry (and wylie (not (string-empty-p (string-trim wylie)))
                     (tibetan-zettel-lookup wylie)))
         (file (and entry (plist-get entry :path)))
         (socket (and (not arg)
                      (tibetan-cat--server-socket-path
                       tibetan-cat-zettel-target-server))))
    (cond
     ;; Hit + research server reachable + no prefix arg → emacsclient
     ((and file socket)
      (call-process "emacsclient" nil 0 nil
                    "-s" tibetan-cat-zettel-target-server
                    "--no-wait"
                    file)
      (message "Opened zettel for '%s' in research instance: %s"
               wylie (file-name-nondirectory file)))
     ;; Hit, but local routing (no server or prefix arg)
     (file
      (find-file file)
      (message "Opened zettel for '%s' locally" wylie))
     ;; No hit → offer to create
     ((and wylie (not (string-empty-p (string-trim wylie))))
      (when (y-or-n-p (format "No zettel for '%s'.  Create one? " wylie))
        (cond
         (socket
          (call-process "emacsclient" nil 0 nil
                        "-s" tibetan-cat-zettel-target-server
                        "--no-wait"
                        "--eval"
                        (format "(denote %S)" wylie))
          (message "Asked research instance to create zettel for '%s'" wylie))
         ((fboundp 'denote)
          (denote wylie))
         (t
          (message "denote not loaded — cannot create zettel for '%s'"
                   wylie))))))))

;; Bound under the CAT prefix `C-c u' (lowercase u) which CAT-tool owns.
;; `Z' uppercase to distinguish from `z' (already taken by thesaurus
;; bindings under `C-c u z').
(global-set-key (kbd "C-c u Z") #'tibetan-cat-open-zettel-for-word-at-point)

(provide 'tibetan-cat)
;;; tibetan-cat.el ends here
