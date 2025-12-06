;;; cat-mode.el --- Main entry point for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Main entry point for the Tibetan Computer-Assisted Translation tool.
;; This module:
;; - Loads all CAT submodules
;; - Provides interactive commands
;; - Manages keybindings
;; - Handles configuration
;;
;; Module structure:
;; cat-tool/
;; ├── core/
;; │   ├── cat-utils.el     - Shared utilities
;; │   ├── cat-grammar.el   - Grammar/particle analysis
;; │   └── cat-parser.el    - Text parsing & compounds
;; ├── display/
;; │   └── cat-display.el   - Analysis display
;; ├── persist/
;; │   └── cat-persist.el   - Persistent analysis storage
;; └── support/
;;     └── cat-translation.el - Translation generation

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; LOAD PATH SETUP
;; ============================================================================

(defvar cat-mode-base-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Base directory of CAT mode installation.")

(defvar cat-mode-data-dir nil
  "Directory containing CAT data files (dictionaries, glossaries).")

;; Add subdirectories to load path
(dolist (subdir '("core" "display" "persist" "support"))
  (add-to-list 'load-path (expand-file-name subdir cat-mode-base-dir)))

;; ============================================================================
;; LOAD SUBMODULES
;; ============================================================================

(require 'cat-utils)
(require 'cat-grammar)
(require 'cat-parser)
(require 'cat-display)
(require 'cat-persist)
(require 'cat-translation)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup cat-mode nil
  "Tibetan Computer-Assisted Translation tool."
  :group 'languages
  :prefix "cat-")

(defcustom cat-mode-auto-analyze nil
  "If non-nil, automatically analyze segments as cursor moves."
  :type 'boolean
  :group 'cat-mode)

(defcustom cat-mode-default-context 'classical-prose
  "Default translation context for new files."
  :type '(choice (const :tag "Classical Prose" classical-prose)
                (const :tag "Bhutan Kagyu Madhyamaka" bhutan-kagyu-madhyamaka)
                (const :tag "Gelug Madhyamaka" gelug-madhyamaka)
                (const :tag "Sutra" sutra)
                (const :tag "Commentary" commentary))
  :group 'cat-mode)

;; ============================================================================
;; INITIALIZATION
;; ============================================================================

(defun cat-mode-setup (data-dir)
  "Initialize CAT mode with DATA-DIR containing dictionaries and glossaries."
  (setq cat-mode-data-dir data-dir)

  ;; Set parser data directory
  (cat-parser-set-data-dir data-dir)

  ;; Load dictionaries
  (cat-parser-load-dictionaries)

  (message "CAT Mode initialized with data from: %s" data-dir))

;; ============================================================================
;; SEGMENT DETECTION
;; ============================================================================

(defun cat-mode-get-current-segment ()
  "Get the current segment at point.
Returns (seg-id . text) or nil."
  ;; Try tibetan-utils first
  (when (fboundp 'tibetan-get-current-segment-any-format)
    (tibetan-get-current-segment-any-format)))

(defun cat-mode-get-current-line-as-segment ()
  "Get the current line as a segment.
Returns (line-number . text)."
  (let ((text (string-trim (thing-at-point 'line t)))
        (line-num (line-number-at-pos)))
    (when (and text (not (string-empty-p text)))
      (cons (number-to-string line-num) text))))

;; ============================================================================
;; INTERACTIVE COMMANDS - SEGMENT ANALYSIS
;; ============================================================================

(defun cat-mode-analyze-segment ()
  "Analyze the current segment and display results."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let ((seg-id (car seg-data))
            (text (cdr seg-data)))
        (cat-display-basic-analysis seg-id text))
    (message "No segment at point")))

(defun cat-mode-analyze-segment-enhanced ()
  "Analyze the current segment with enhanced display."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let ((seg-id (car seg-data))
            (text (cdr seg-data)))
        (cat-display-enhanced-analysis seg-id text))
    (message "No segment at point")))

;; ============================================================================
;; INTERACTIVE COMMANDS - PERSISTENT ANALYSIS
;; ============================================================================

(defun cat-mode-save-segment-analysis ()
  "Analyze current segment and save to file."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let* ((seg-id (car seg-data))
             (text (cdr seg-data))
             (file (cat-persist-analyze-segment seg-id text)))
        (find-file-other-window file))
    (message "No segment at point")))

(defun cat-mode-re-analyze-segment ()
  "Re-analyze current segment, preserving user notes."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let* ((seg-id (car seg-data))
             (text (cdr seg-data))
             (file (cat-persist-re-analyze-segment seg-id text)))
        (find-file-other-window file))
    (message "No segment at point")))

(defun cat-mode-open-segment-analysis ()
  "Open existing analysis for current segment."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (cat-persist-open-segment-analysis (car seg-data))
    (message "No segment at point")))

;; ============================================================================
;; INTERACTIVE COMMANDS - TRANSLATION
;; ============================================================================

(defun cat-mode-show-translation ()
  "Show translation suggestion for current segment."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let* ((text (cdr seg-data))
             (suggestion (cat-translation-suggest text)))
        (message "Translation: %s"
                (or (alist-get :grammar-aware suggestion)
                    (alist-get :basic suggestion)
                    "[Could not generate]")))
    (message "No segment at point")))

;; ============================================================================
;; INTERACTIVE COMMANDS - GRAMMAR
;; ============================================================================

(defun cat-mode-show-particles ()
  "Show particle analysis for current segment."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let* ((text (cdr seg-data))
             (particles (cat-grammar-analyze-text text)))
        (if particles
            (with-output-to-temp-buffer "*CAT Particles*"
              (princ "Particles detected:\n\n")
              (dolist (p particles)
                (princ (format "%s: %s\n  %s\n\n"
                              (cat-particle-particle p)
                              (cat-grammar-get-type-name (cat-particle-type p))
                              (cat-particle-function p)))))
          (message "No particles detected")))
    (message "No segment at point")))

;; ============================================================================
;; INTERACTIVE COMMANDS - UTILITY
;; ============================================================================

(defun cat-mode-show-wylie ()
  "Show Wylie transliteration for current segment."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let ((wylie (cat-display-get-wylie (cdr seg-data))))
        (message "Wylie: %s" wylie))
    (message "No segment at point")))

(defun cat-mode-copy-wylie ()
  "Copy Wylie transliteration to kill ring."
  (interactive)
  (if-let ((seg-data (or (cat-mode-get-current-segment)
                        (cat-mode-get-current-line-as-segment))))
      (let ((wylie (cat-display-get-wylie (cdr seg-data))))
        (kill-new wylie)
        (message "Copied: %s" wylie))
    (message "No segment at point")))

(defun cat-mode-reload-dictionaries ()
  "Reload all CAT dictionaries."
  (interactive)
  (cat-parser-reload-dictionaries)
  (message "Dictionaries reloaded"))

;; ============================================================================
;; KEYBINDINGS
;; ============================================================================

(defvar cat-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Segment analysis (C-c u prefix)
    (define-key map (kbd "C-c u i") #'cat-mode-analyze-segment)
    (define-key map (kbd "C-c u I") #'cat-mode-analyze-segment-enhanced)
    (define-key map (kbd "C-c u A") #'cat-mode-save-segment-analysis)
    (define-key map (kbd "C-c u R") #'cat-mode-re-analyze-segment)
    (define-key map (kbd "C-c u E") #'cat-mode-open-segment-analysis)

    ;; Translation (C-c u t prefix)
    (define-key map (kbd "C-c u t") #'cat-mode-show-translation)

    ;; Grammar (C-c u p for particles)
    (define-key map (kbd "C-c u p") #'cat-mode-show-particles)

    ;; Wylie
    (define-key map (kbd "C-c u w") #'cat-mode-show-wylie)
    (define-key map (kbd "C-c u W") #'cat-mode-copy-wylie)

    map)
  "Keymap for CAT mode commands.")

;; ============================================================================
;; MINOR MODE
;; ============================================================================

(define-minor-mode cat-mode
  "Minor mode for Tibetan Computer-Assisted Translation.

Key bindings:
\\{cat-mode-map}"
  :lighter " CAT"
  :keymap cat-mode-map
  :group 'cat-mode

  (if cat-mode
      (message "CAT mode enabled")
    (message "CAT mode disabled")))

;; ============================================================================
;; GLOBAL ACTIVATION
;; ============================================================================

(defun cat-mode-enable-globally ()
  "Enable CAT mode in all Tibetan-related buffers."
  (interactive)
  (add-hook 'org-mode-hook
            (lambda ()
              (when (or (string-match-p "\\.tib\\'" (or buffer-file-name ""))
                       (save-excursion
                         (goto-char (point-min))
                         (re-search-forward "^#\\+TIBETAN" nil t)))
                (cat-mode 1)))))

(provide 'cat-mode)
;;; cat-mode.el ends here
