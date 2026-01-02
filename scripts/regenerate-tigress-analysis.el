;;; regenerate-tigress-analysis.el --- Regenerate Tigress story analysis files -*- lexical-binding: t -*-

;;; Commentary:
;; Batch script to regenerate analysis files for Tigress Jātaka segments.
;; Run with: emacs --batch -l this-file.el

;;; Code:

;; Disable file locking to avoid conflicts with GUI Emacs
(setq create-lockfiles nil)

;; Define data directory BEFORE loading any modules (like run-specs.el does)
(defvar tibetan-cat-data-dir nil
  "Directory containing Tibetan CAT data files.")

;; Setup paths - use load-file-name for dynamic path resolution
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  ;; Go up from scripts/ to emacs-tibetan-cat/
  (setq base-dir (expand-file-name ".." base-dir))
  (add-to-list 'load-path base-dir)
  (add-to-list 'load-path (expand-file-name "core" base-dir))
  (add-to-list 'load-path (expand-file-name "analysis" base-dir))
  (add-to-list 'load-path (expand-file-name "persist" base-dir))
  ;; Set data directory BEFORE loading modules that need it
  (setq tibetan-cat-data-dir base-dir))

;; Load modules (in order) - use optional loading like run-specs.el
(require 'tibetan-wylie nil t)
(require 'tibetan-utils nil t)
(require 'tibetan-vocabulary nil t)
(require 'tibetan-verb-classifier nil t)
(require 'tibetan-enhanced-parser nil t)
(require 'tibetan-particles-bialek nil t)
(require 'tibetan-enhanced-display nil t)
(require 'tibetan-analysis-persist nil t)

;; Skip comprehensive glossaries for faster execution - use built-in dicts
;; (load "/Users/cp/buddhist-studies/translation-tools/load-comprehensive-glossaries.el")

;; Define segments to regenerate
(defvar tigress-segments
  '(("seg-026" . "དེའི་ཚེ་ཀུན་དགའ་བོ་ངོ་མཚར་དུ་གྱུར་པ་ལ་བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ།")
    ("seg-027" . "མ་སྨད་གསུམ་པོ་འདི་ནི་ངས་ད་ལྟར་འདི་འབའ་ཞིག་ཏུ་མ་ཟད།")
    ("seg-028" . "སྔོན་གྱི་དུས་ནའང་བཀའ་དྲིན་གྱིས་གསོས་པ་ཡིན་ཏེ།")
    ("seg-032" . "སྔོན་འདས་པའི་དུས་བསྐལ་པ་གྲངས་མེད་པའི་ཕ་རོལ་ན།"))
  "List of (seg-id . tibetan-text) for regeneration.")

(defvar tigress-analysis-dir
  "/Users/cp/buddhist-studies/WS25-26/Tibetisch III/TigressStory/WorkInProgress/analysis/"
  "Directory containing analysis files.")

(defun regenerate-tigress-segment (seg-id tibetan-text)
  "Regenerate analysis for SEG-ID with TIBETAN-TEXT."
  (message "\n=== Regenerating %s ===" seg-id)
  (let* ((filepath (expand-file-name (concat seg-id ".org") tigress-analysis-dir))
         (auto-content (tibetan-analysis-generate-content tibetan-text)))
    (if (file-exists-p filepath)
        (progn
          (tibetan-analysis-regenerate-auto filepath tibetan-text auto-content)
          (message "  Updated: %s" filepath))
      (message "  SKIPPED: %s (file not found)" filepath))))

;; Run regeneration
(when noninteractive
  (message "Starting Tigress analysis regeneration...")
  (message "Loaded dictionaries: compounds=%d, proper_nouns=%d"
           (hash-table-count tibetan-compounds-dict)
           (hash-table-count tibetan-proper-nouns-dict))
  (dolist (seg tigress-segments)
    (regenerate-tigress-segment (car seg) (cdr seg)))
  (message "\nRegeneration complete!"))

(provide 'regenerate-tigress-analysis)
;;; regenerate-tigress-analysis.el ends here
