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

  ;; Set data directory for glossaries
  (defvar tibetan-cat-data-dir (expand-file-name "data" base-dir)
    "Directory containing Tibetan CAT data files (glossaries, etc.)"))

;; ============================================================================
;; LOAD CORE MODULES
;; ============================================================================

(require 'tibetan-utils)          ; Utility functions
(require 'tibetan-wylie)          ; Wylie transliteration
(require 'tibetan-vocabulary)     ; Vocabulary lookup with DharmaMitra
(require 'tibetan-org-structure)  ; Org-mode structure support (new format)
(require 'tibetan-text-classifier) ; Text type classification (NEW)

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

(require 'tibetan-analysis-persist)    ; Persistent segment analysis (C-c u A / C-c u R)
(require 'tibetan-compound-analysis)   ; Persistent compound analysis (C-c v A / C-c v R)
(require 'tibetan-clause-analysis)     ; Clause analysis (converbs, main verbs)
(require 'tibetan-auto-analysis)       ; Auto-analyze document (C-c u B)
(require 'tibetan-structure-reorg)     ; Reorganize analysis files (C-c u O / C-c u U)

;; ============================================================================
;; LOAD DOCUMENT DISPLAY MODULES
;; ============================================================================

(require 'tibetan-doc-display)         ; Display settings for prepared documents

;; ============================================================================
;; LOAD KEYBINDINGS
;; ============================================================================

(require 'tibetan-keybindings)

;; ============================================================================
;; INITIALIZATION
;; ============================================================================

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

      (insert "───────────────────────────────────────────────────────────────────\n")
      (insert "DOCUMENT CONTEXT (add to header):\n")
      (insert "  #+TIBETAN_TEXT_TYPE: classical | madhyamaka-verse | kagyu-verse\n")
      (insert "  #+TIBETAN_CONTEXT: bhutan-kagyu-madhyamaka | gelug-madhyamaka\n")
      (insert "───────────────────────────────────────────────────────────────────\n")

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
