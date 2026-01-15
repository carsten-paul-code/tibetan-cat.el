;;; tibetan-verse-philology.el --- Philological tools for Tibetan verse texts -*- lexical-binding: t -*-

;;; Commentary:
;; Specialized tools for graduate-level philological work on Tibetan verse texts
;;
;; Designed for:
;; - Critical editions with apparatus
;; - 7-syllable verse meter analysis
;; - sa bcad (outline) structure navigation
;; - Root text + auto-commentary correlation
;; - Madhyamaka/philosophical terminology
;;
;; Features:
;; - Syllable counter and meter validator
;; - Metrical filler detection
;; - Condensed meaning extraction
;; - Critical apparatus display
;; - sa bcad outline navigation

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; SYLLABLE COUNTING & METER ANALYSIS
;; ============================================================================

(defun tibetan-count-syllables (tibetan-text)
  "Count syllables in TIBETAN-TEXT.
Returns number of syllables (segments separated by tsheg ་)."
  (let* ((clean (replace-regexp-in-string "[།༎༏༐༑༔\n\r ]" "" tibetan-text))
         (syllables (split-string clean "་" t)))
    (length syllables)))

(defun tibetan-syllable-breakdown (tibetan-text)
  "Break down TIBETAN-TEXT into individual syllables.
Returns list of syllables."
  (let* ((clean (replace-regexp-in-string "[།༎༏༐༑༔\n\r ]" "" tibetan-text))
         (syllables (split-string clean "་" t)))
    syllables))

(defun tibetan-validate-verse-meter (verse-lines)
  "Validate that VERSE-LINES follow 7-syllable meter.
VERSE-LINES is a list of verse lines.
Returns list of (line syllable-count valid-p)."
  (mapcar
   (lambda (line)
     (let ((count (tibetan-count-syllables line)))
       (list line count (= count 7))))
   verse-lines))

(defun tibetan-format-syllables-numbered (tibetan-text)
  "Format TIBETAN-TEXT with numbered syllables.
Example output:
  བླ་  མ་  ལ་  ནི་  ཕྱག་  འཚལ་  ལོ།
  1    2   3   4    5     6      7"
  (let* ((syllables (tibetan-syllable-breakdown tibetan-text))
         (syl-line (mapconcat 'identity syllables "  "))
         (num-line (mapconcat (lambda (n) (format "%-4d" n))
                              (number-sequence 1 (length syllables))
                              "")))
    (concat syl-line "\n" num-line)))

;; ============================================================================
;; METRICAL FILLER DETECTION
;; ============================================================================

(defvar tibetan-common-metrical-fillers
  '("ནི" "ཡང" "ནོ" "སོ" "ཏོ" "ཀྱང" "གི" "ཡི" "ཀྱི" "གྱི" "འི")
  "Common particles used as metrical fillers in 7-syllable verse.
These often don't carry semantic weight, just maintain meter.")

(defun tibetan-identify-metrical-fillers (tibetan-text)
  "Identify potential metrical fillers in TIBETAN-TEXT.
Returns list of (syllable position is-filler-p)."
  (let* ((syllables (tibetan-syllable-breakdown tibetan-text))
         (result '()))
    (dotimes (i (length syllables))
      (let* ((syl (nth i syllables))
             (is-filler (member syl tibetan-common-metrical-fillers))
             (is-final (= i (1- (length syllables)))))
        (push (list syl (1+ i) (or is-filler is-final)) result)))
    (nreverse result)))

(defun tibetan-extract-core-meaning (tibetan-text)
  "Extract core meaning by removing likely metrical fillers.
Returns string with fillers marked."
  (let* ((syllables (tibetan-syllable-breakdown tibetan-text))
         (analysis (tibetan-identify-metrical-fillers tibetan-text))
         (core-parts '()))
    (dolist (item analysis)
      (let ((syl (nth 0 item))
            (pos (nth 1 item))
            (is-filler (nth 2 item)))
        (if is-filler
            (push (format "[%s]" syl) core-parts)
          (push syl core-parts))))
    (mapconcat 'identity (nreverse core-parts) "་")))

;; ============================================================================
;; SA BCAD (OUTLINE) STRUCTURE
;; ============================================================================

(defun tibetan-parse-sa-bcad-number (sa-bcad-str)
  "Parse sa bcad outline number like '2.2.1.2.1.2.4'.
Returns list of integers."
  (mapcar 'string-to-number (split-string sa-bcad-str "\\." t)))

(defun tibetan-sa-bcad-depth (sa-bcad-str)
  "Return depth level of sa bcad outline number.
Example: '2.2.1' → 3"
  (length (tibetan-parse-sa-bcad-number sa-bcad-str)))

(defun tibetan-format-sa-bcad-outline (sa-bcad-str subject)
  "Format sa bcad outline entry with proper indentation.
Example:
  2.2.1.2.1.2.4 → '        Definition (mtshan nyid)'"
  (let* ((depth (tibetan-sa-bcad-depth sa-bcad-str))
         (indent (make-string (* 2 (1- depth)) ?\s)))
    (format "%s%s %s" indent sa-bcad-str subject)))

;; ============================================================================
;; VERSE DISPLAY & ANALYSIS
;; ============================================================================

(defun tibetan-analyze-verse-line (verse-line verse-number)
  "Analyze a single VERSE-LINE with VERSE-NUMBER.
Returns formatted analysis string."
  (let* ((syllables (tibetan-syllable-breakdown verse-line))
         (count (length syllables))
         (valid (= count 7))
         (fillers (tibetan-identify-metrical-fillers verse-line))
         (core (tibetan-extract-core-meaning verse-line))
         (numbered (tibetan-format-syllables-numbered verse-line)))
    (concat
     (format "Verse %s: %s\n" verse-number verse-line)
     (format "  Syllable count: %d %s\n" count (if valid "✓" "✗ IRREGULAR"))
     (format "  Breakdown:\n    %s\n" numbered)
     (format "  Core meaning: %s\n" core)
     (when (cl-some (lambda (x) (nth 2 x)) fillers)
       (format "  Likely fillers: %s\n"
               (mapconcat (lambda (x)
                           (when (nth 2 x) (nth 0 x)))
                         fillers ", "))))))

(defun tibetan-analyze-verse-block (verse-lines verse-number)
  "Analyze a block of VERSE-LINES with VERSE-NUMBER.
VERSE-LINES is list of lines (typically 4 lines per verse).
Returns formatted analysis."
  (let ((result (format "\n╔═══════════════════════════════════════════════════════════╗\n"))
        (line-num 1))
    (setq result (concat result (format "║ VERSE %s ANALYSIS\n" verse-number)))
    (setq result (concat result "╚═══════════════════════════════════════════════════════════╝\n\n"))

    (dolist (line verse-lines)
      (setq result (concat result (format "Line %d: %s\n" line-num line)))
      (let* ((syllables (tibetan-syllable-breakdown line))
             (count (length syllables)))
        (setq result (concat result (format "  [%d syllables] %s\n"
                                           count
                                           (if (= count 7) "✓" "✗"))))
        (setq result (concat result (format "  %s\n\n"
                                           (tibetan-format-syllables-numbered line)))))
      (setq line-num (1+ line-num)))

    ;; Overall analysis
    (setq result (concat result "METRICAL ANALYSIS:\n"))
    (dolist (line verse-lines)
      (setq result (concat result (format "  %s\n" (tibetan-extract-core-meaning line)))))

    result))

;; ============================================================================
;; CRITICAL APPARATUS HANDLING
;; ============================================================================

(defun tibetan-format-apparatus-entry (lemma reading-a reading-b note)
  "Format a critical apparatus entry.
LEMMA: the word/phrase in question
READING-A: reading from auto-commentary
READING-B: reading from base text
NOTE: apparatus note (emend., conj., etc.)"
  (format "%s] %s, %s %s"
          lemma
          note
          reading-a
          reading-b))

(defun tibetan-display-apparatus (apparatus-entries)
  "Display APPARATUS-ENTRIES in formatted style.
APPARATUS-ENTRIES is list of (lemma reading-a reading-b note)."
  (let ((result "\nCRITICAL APPARATUS:\n"))
    (setq result (concat result "──────────────────────────────────────\n"))
    (dolist (entry apparatus-entries)
      (setq result (concat result
                          (format "  %s\n"
                                 (apply 'tibetan-format-apparatus-entry entry)))))
    result))

;; ============================================================================
;; INTERACTIVE VERSE ANALYSIS
;; ============================================================================

(defun tibetan-get-current-verse-block ()
  "Extract current verse block data from buffer.
Returns (verse-number . verse-lines) or nil if not in a verse block."
  (save-excursion
    (let (verse-number verse-lines verse-start-line)
      ;; Find the verse marker before point
      (when (re-search-backward "〔verse:\\([0-9]+\\)〕" nil t)
        (setq verse-number (match-string 1))
        (setq verse-start-line (line-number-at-pos))
        (forward-line 1)
        ;; Collect all segment lines until:
        ;; - next verse marker
        ;; - level 1 or 2 org heading (^* or ^**)
        ;; - "Translation:" line (common in prepared documents)
        ;; - max 50 lines from verse start
        (let ((max-line (+ verse-start-line 50)))
          (while (and (not (eobp))
                      (not (looking-at "〔verse:"))
                      (not (looking-at "^\\*\\*? [A-Z]"))  ; Level 1-2 headings
                      (not (looking-at "^Translation:"))
                      (< (line-number-at-pos) max-line))
            (when (looking-at ".*〔seg:[^〕]+〕\\([^〔〕]+\\)〔/seg〕")
              (let ((line (match-string 1)))
                (when (and line (not (string-empty-p (string-trim line))))
                  (push (string-trim line) verse-lines))))
            (forward-line 1)))
        ;; Return verse data if we found lines
        (when verse-lines
          (cons verse-number (nreverse verse-lines)))))))

(defun tibetan-analyze-current-verse-interactive ()
  "Analyze the verse block at point and display in side window.
Shows:
- Verse text with line-by-line syllable analysis
- Metrical analysis (7-syllable validation)
- Core meaning extraction (fillers marked)
- Vocabulary for all terms
- Madhyamaka terminology identification

Bound to C-c v v."
  (interactive)
  (let ((verse-data (tibetan-get-current-verse-block)))
    (if (not verse-data)
        (message "Not in a verse block. Look for 〔verse:NNN〕 markers.")
      (let* ((verse-number (car verse-data))
             (verse-lines (cdr verse-data))
             (buffer (get-buffer-create "*Verse Analysis*"))
             (source-window (selected-window)))

        ;; Generate analysis
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)

            ;; Header
            (insert "╔══════════════════════════════════════════════════════════════╗\n")
            (insert "║         VERSE ANALYSIS - PHILOLOGY TOOLS                     ║\n")
            (insert "╚══════════════════════════════════════════════════════════════╝\n\n")

            ;; Verse identification
            (insert (format "VERSE %s\n\n" verse-number))

            ;; Full verse text
            (insert "ROOT TEXT:\n")
            (insert "──────────────────────────────────────\n")
            (dolist (line verse-lines)
              (insert (format "%s\n" line)))
            (insert "\n")

            ;; Metrical analysis from existing function
            (insert (tibetan-analyze-verse-block verse-lines verse-number))

            ;; Vocabulary for all lines
            (insert "\nVOCABULARY (all lines):\n")
            (insert "──────────────────────────────────────\n")
            (dolist (line verse-lines)
              (let ((vocab (when (fboundp 'tibetan-extract-vocabulary)
                            (tibetan-extract-vocabulary line))))
                (when vocab
                  (insert (format "  %s:\n" line))
                  (dolist (word-pair vocab)
                    (insert (format "    • %s (%s)\n" (car word-pair) (cdr word-pair))))
                  (insert "\n"))))

            ;; Madhyamaka terms if function exists
            (when (fboundp 'tibetan-extract-madhyamaka-vocabulary)
              (insert "\nMADHYAMAKA TERMINOLOGY:\n")
              (insert "──────────────────────────────────────\n")
              (let ((all-text (mapconcat 'identity verse-lines " "))
                    (found-terms (tibetan-extract-madhyamaka-vocabulary all-text)))
                (if found-terms
                    (dolist (term-pair found-terms)
                      (insert (format "  • %s\n    → %s\n\n" (car term-pair) (cdr term-pair))))
                  (insert "  [No Madhyamaka technical terms detected]\n\n"))))

            ;; Translation workspace
            (insert "\nTRANSLATION WORKSPACE:\n")
            (insert "──────────────────────────────────────\n")
            (insert "[Your translation here]\n\n")

            ;; Notes
            (insert "PHILOLOGICAL NOTES:\n")
            (insert "──────────────────────────────────────\n")
            (insert "[Your notes here]\n\n")

            (insert "[Press q to close]\n")

            (goto-char (point-min))
            (view-mode 1)))

        ;; Display in side window (similar to segment analysis)
        (let ((analysis-window (get-buffer-window "*Verse Analysis*")))
          (if analysis-window
              ;; Window exists - update it
              (progn
                (set-window-buffer analysis-window buffer)
                (select-window source-window))
            ;; Create new window
            (progn
              (unless (get-buffer-window "*Sentence Workspace*")
                (delete-other-windows))
              (let ((new-window (split-window source-window nil 'right)))
                (set-window-buffer new-window buffer)
                (select-window source-window)))))

        (message "Verse %s - Analysis on right (C-c v v)" verse-number)))))

;; ============================================================================
;; VERSE WORKSPACE
;; ============================================================================

(defun tibetan-create-verse-workspace (verse-data)
  "Create philological workspace for VERSE-DATA.
VERSE-DATA is plist with :number, :sa-bcad, :subject, :lines, :page, :apparatus."
  (let ((verse-num (plist-get verse-data :number))
        (sa-bcad (plist-get verse-data :sa-bcad))
        (subject (plist-get verse-data :subject))
        (lines (plist-get verse-data :lines))
        (page (plist-get verse-data :page))
        (apparatus (plist-get verse-data :apparatus))
        (buffer-name (format "*Verse %s Analysis*" (plist-get verse-data :number))))

    (with-current-buffer (get-buffer-create buffer-name)
      (erase-buffer)
      (insert "╔══════════════════════════════════════════════════════════════╗\n")
      (insert "║     TIBETAN VERSE PHILOLOGY - CRITICAL EDITION              ║\n")
      (insert "╚══════════════════════════════════════════════════════════════╝\n\n")

      ;; Metadata
      (insert (format "VERSE: %s\n" verse-num))
      (insert (format "SA BCAD: %s\n" sa-bcad))
      (insert (format "SUBJECT: %s\n" subject))
      (insert (format "PAGE(S): %s\n\n" page))

      ;; Verse text
      (insert "ROOT TEXT:\n")
      (insert "──────────────────────────────────────\n")
      (dolist (line lines)
        (insert (format "%s\n" line)))
      (insert "\n")

      ;; Metrical analysis
      (insert (tibetan-analyze-verse-block lines verse-num))

      ;; Critical apparatus
      (when apparatus
        (insert (tibetan-display-apparatus apparatus)))

      ;; Translation space
      (insert "\n\nTRANSLATION:\n")
      (insert "──────────────────────────────────────\n")
      (insert "[Your translation here]\n\n")

      ;; Notes space
      (insert "PHILOLOGICAL NOTES:\n")
      (insert "──────────────────────────────────────\n")
      (insert "[Your notes here]\n\n")

      (goto-char (point-min))
      (current-buffer))))

(provide 'tibetan-verse-philology)
;;; tibetan-verse-philology.el ends here
