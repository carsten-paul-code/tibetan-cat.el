;;; tibetan-cat.el --- Tibetan Computer-Assisted Translation System -*- lexical-binding: t -*-

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
  (add-to-list 'load-path base-dir)  ; For modules in root (tibetan-analysis-persist.el)
  (add-to-list 'load-path (expand-file-name "core" base-dir))
  (add-to-list 'load-path (expand-file-name "analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "workspace" base-dir))
  (add-to-list 'load-path (expand-file-name "philology" base-dir))  ; New: verse philology
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

;; Bialek grammar system (for classical prose)
(require 'tibetan-particles-bialek)    ; Bialek-based grammar analysis
(require 'tibetan-translation-suggest)  ; Translation suggestion engine
(require 'tibetan-classroom)            ; Segment analysis (main classroom tool)

;; Enhanced parsing (Phase 1 improvements)
(require 'tibetan-enhanced-parser)      ; Multi-word units, accurate particle detection
(require 'tibetan-enhanced-display)     ; Enhanced analysis display

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
  (message "Tibetan CAT system initialized")
  (message "")
  (message "SEGMENT (line) analysis:")
  (message "  C-c u i - Segment analysis (Bialek grammar + verb stems)")
  (message "  C-c u I - Enhanced segment analysis (improved parsing)")
  (message "  C-c u A - Persistent segment analysis (with notes, footnotes)")
  (message "  C-c u R - Re-analyze segment (keep notes)")
  (message "")
  (message "COMPOUND (verse/sentence) analysis:")
  (message "  C-c v v - Quick verse analysis (meter + vocab)")
  (message "  C-c v A - Persistent compound analysis (verse/sentence)")
  (message "  C-c v R - Re-analyze compound (keep notes)")
  (message "")
  (message "OTHER:")
  (message "  C-c u E - Toggle auto-analysis")
  (message "  C-c s w - Sentence workspace")
  (message "  C-c u v - Reload glossaries")
  (message "")
  (message "CONTEXT (add to document header):")
  (message "  #+TIBETAN_TEXT_TYPE: classical | madhyamaka-verse | kagyu-verse")
  (message "  #+TIBETAN_CONTEXT: bhutan-kagyu-madhyamaka | gelug-madhyamaka"))

;; Auto-run setup on load
(tibetan-cat-setup)

;; ============================================================================
;; VERSION INFO
;; ============================================================================

(defconst tibetan-cat-version "1.0.0"
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
