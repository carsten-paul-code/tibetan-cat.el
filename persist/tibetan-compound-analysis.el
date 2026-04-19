;;; tibetan-compound-analysis.el --- Persistent compound (verse/sentence) analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Two-level analysis system for Tibetan texts:
;; - Level 1: Segment/line analysis (tibetan-analysis-persist.el)
;; - Level 2: Compound analysis (this file) - verses or sentences
;;
;; Features:
;; - Flexible compound boundary detection (markers, patterns, region)
;; - Aggregates segment analyses
;; - Inter-line grammar analysis (how lines connect)
;; - Context-aware translation (configurable per tradition)
;; - Persistent files with user sections preserved on re-analysis
;;
;; Keybindings:
;; - C-c v A: Open/create compound analysis
;; - C-c v R: Re-analyze compound (preserve notes)

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'md5)

;; Load segment analysis for reuse
(require 'tibetan-analysis-persist)

(defconst tibetan-compound-analysis-version "1.0"
  "Version of the compound analysis file format.")

;; ============================================================================
;; CONTEXT CONFIGURATION
;; ============================================================================

(defvar tibetan-compound-contexts
  '((bhutan-kagyu-madhyamaka
     :name "Bhutan Kagyu Madhyamaka"
     :description "Bhutanese Drukpa Kagyu interpretation of Madhyamaka"
     :terminology-style technical
     :translation-style balanced
     :key-concepts ("གནས་ལུགས" "སྣང་ཚུལ" "བདེན་གཉིས" "རྣམ་གྲངས་པ" "རྣམ་གྲངས་མིན་པ"))
    (gelug-madhyamaka
     :name "Gelug Madhyamaka"
     :description "Gelug Prāsaṅgika-Madhyamaka interpretation"
     :terminology-style technical
     :translation-style precise
     :key-concepts ("རང་བཞིན་གྱིས་སྟོང་པ" "ཐ་སྙད་དུ་ཡོད" "དོན་དམ་དུ་མེད"))
    (classical-prose
     :name "Classical Tibetan Prose"
     :description "Standard classical Tibetan without specific tradition"
     :terminology-style general
     :translation-style readable
     :key-concepts nil))
  "Available context configurations for compound analysis.
Each context affects terminology choices and translation style.")

(defun tibetan-compound-get-context ()
  "Get the context configuration for current buffer.
Reads from #+TIBETAN_CONTEXT header or defaults to classical-prose."
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+TIBETAN_CONTEXT:\\s-*\\(.+\\)$" nil t)
        (let ((ctx-name (intern (string-trim (match-string 1)))))
          (or (assq ctx-name tibetan-compound-contexts)
              (assq 'classical-prose tibetan-compound-contexts)))
      (assq 'classical-prose tibetan-compound-contexts))))

;; ============================================================================
;; COMPOUND BOUNDARY DETECTION
;; ============================================================================

(defun tibetan-compound-detect-verse-number ()
  "Detect verse boundary by Tibetan numeral pattern.
Returns (start-line . end-line) or nil.
Looks for patterns like ། ༡༢ །"
  (save-excursion
    (let ((current-line (line-number-at-pos)))
      ;; Search backward for previous verse number or beginning
      (let ((start-line current-line)
            (end-line current-line))
        ;; Find end: next verse number or double shad
        (forward-line 1)
        (while (and (not (eobp))
                    (not (looking-at ".*། [༠-༩]+ །"))
                    (not (looking-at ".*།།"))
                    (not (looking-at "^\\s-*$")))
          (setq end-line (line-number-at-pos))
          (forward-line 1))
        ;; Check if current line has verse number (then it's end of verse)
        (goto-char (point-min))
        (forward-line (1- current-line))
        (when (looking-at ".*། [༠-༩]+ །")
          (setq end-line current-line))
        ;; Find start: go back to previous verse number or section start
        (goto-char (point-min))
        (forward-line (1- current-line))
        (while (and (> (line-number-at-pos) 1)
                    (not (looking-at ".*། [༠-༩]+ །"))
                    (not (looking-at ".*།།"))
                    (not (looking-at "^\\*")))  ; org heading
          (forward-line -1)
          (setq start-line (line-number-at-pos)))
        ;; If we hit a verse marker going backward, start after it
        (when (looking-at ".*། [༠-༩]+ །")
          (forward-line 1)
          (setq start-line (line-number-at-pos)))
        (when (< start-line end-line)
          (cons start-line end-line))))))

(defun tibetan-compound-detect-double-shad ()
  "Detect compound boundary by double shad (།།).
Returns (start-line . end-line) or nil."
  (save-excursion
    (let ((current-line (line-number-at-pos))
          start-line end-line)
      ;; Find end: next double shad
      (end-of-line)
      (if (re-search-forward "།།" nil t)
          (setq end-line (line-number-at-pos))
        (setq end-line (line-number-at-pos (point-max))))
      ;; Find start: previous double shad
      (goto-char (point-min))
      (forward-line (1- current-line))
      (beginning-of-line)
      (if (re-search-backward "།།" nil t)
          (progn
            (forward-line 1)
            (setq start-line (line-number-at-pos)))
        (setq start-line 1))
      (when (and start-line end-line (<= start-line end-line))
        (cons start-line end-line)))))

(defun tibetan-compound-detect-syllable-meter ()
  "Detect verse by finding 4 consecutive 7-syllable lines.
Returns (start-line . end-line) or nil."
  (save-excursion
    (let ((_current-line (line-number-at-pos))
          (_seven-count 0)
          start-line end-line)
      ;; Go back to find start of 7-syllable sequence
      (beginning-of-line)
      (while (and (> (line-number-at-pos) 1)
                  (let ((text (tibetan-compound--extract-tibetan-from-line)))
                    (and text (= (tibetan-count-syllables text) 7))))
        (forward-line -1))
      (unless (let ((text (tibetan-compound--extract-tibetan-from-line)))
                (and text (= (tibetan-count-syllables text) 7)))
        (forward-line 1))
      (setq start-line (line-number-at-pos))
      ;; Count forward to find end
      (while (and (not (eobp))
                  (let ((text (tibetan-compound--extract-tibetan-from-line)))
                    (and text (= (tibetan-count-syllables text) 7))))
        (setq end-line (line-number-at-pos))
        (forward-line 1))
      ;; Only return if we found at least 2 lines (half-verse minimum)
      (when (and start-line end-line (>= (- end-line start-line) 1))
        (cons start-line end-line)))))

(defun tibetan-compound-detect-explicit-markers ()
  "Detect compound by explicit markers.
Supports multiple marker formats:
  - 〔verse:NNN〕 (legacy numbered)
  - 〔verse :num N〕...〔/verse〕 (new property-based)
  - 〔sent〕...〔/sent〕 (sentence blocks)
  - 〔prose :comment-on N〕...〔/prose〕 (commentary blocks)
Returns (start-line . end-line) or nil."
  (save-excursion
    (let ((current-pos (point)))
      ;; Try new-style markers first: 〔sent〕, 〔verse :num N〕, 〔prose〕
      (or
       ;; Detect 〔sent〕...〔/sent〕 block
       (tibetan-compound--detect-block-markers "sent")
       ;; Detect 〔verse :num N〕...〔/verse〕 block
       (tibetan-compound--detect-block-markers "verse")
       ;; Detect 〔prose :comment-on N〕...〔/prose〕 block
       (tibetan-compound--detect-block-markers "prose")
       ;; Legacy: 〔verse:NNN〕
       (progn
         (goto-char current-pos)
         (when (re-search-backward "〔verse:\\([0-9]+\\)〕" nil t)
           (let ((_verse-num (match-string 1))
                 (start-line (1+ (line-number-at-pos)))
                 end-line)
             (forward-line 1)
             (if (re-search-forward "〔verse:\\|^\\*" nil t)
                 (setq end-line (1- (line-number-at-pos)))
               (setq end-line (line-number-at-pos (point-max))))
             (when (<= start-line end-line)
               (cons start-line end-line)))))))))

(defun tibetan-compound--detect-block-markers (marker-type)
  "Detect block bounded by 〔MARKER-TYPE...〕 and 〔/MARKER-TYPE〕.
MARKER-TYPE is one of: sent, verse, prose.
Returns (start-line . end-line) or nil."
  (save-excursion
    (let ((current-pos (point))
          (open-re (format "〔%s[^〕]*〕" marker-type))
          (close-re (format "〔/%s〕" marker-type)))
      ;; Find opening marker before point
      (when (re-search-backward open-re nil t)
        (let ((start-line (line-number-at-pos)))
          ;; Find closing marker after the opening
          (when (re-search-forward close-re nil t)
            (let ((end-line (line-number-at-pos)))
              ;; Only return if cursor was inside the block
              (when (and (<= start-line (line-number-at-pos current-pos))
                         (>= end-line (line-number-at-pos current-pos)))
                (cons start-line end-line)))))))))

(defun tibetan-compound-detect-region ()
  "Use active region as compound boundary.
Returns (start-line . end-line) or nil if no region."
  (when (use-region-p)
    (let ((start-line (line-number-at-pos (region-beginning)))
          (end-line (line-number-at-pos (region-end))))
      (cons start-line end-line))))

(defun tibetan-compound-detect-boundaries ()
  "Detect compound boundaries using multiple strategies.
Tries in order: region, explicit markers, verse numbers, double shad, meter.
Returns (start-line . end-line) or nil."
  (or (tibetan-compound-detect-region)
      (tibetan-compound-detect-explicit-markers)
      (tibetan-compound-detect-verse-number)
      (tibetan-compound-detect-double-shad)
      (tibetan-compound-detect-syllable-meter)))

;; ============================================================================
;; LINE EXTRACTION
;; ============================================================================

(defun tibetan-compound--extract-tibetan-from-line ()
  "Extract Tibetan text from current line.
Handles both plain lines and 〔seg:...〕 markers."
  (save-excursion
    (beginning-of-line)
    (let ((line (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position))))
      (cond
       ;; Explicit segment marker
       ((string-match "〔seg:[^〕]+〕\\([^〔]+\\)〔/seg〕" line)
        (string-trim (match-string 1 line)))
       ;; Line with Tibetan characters (no markers)
       ((string-match "[ༀ-࿿]+" line)
        ;; Extract just the Tibetan portion
        (let ((tibetan-text ""))
          (with-temp-buffer
            (insert line)
            (goto-char (point-min))
            (while (re-search-forward "[ༀ-࿿་།༎༏༐༑༔༠-༩]+" nil t)
              (setq tibetan-text (concat tibetan-text (match-string 0)))))
          (when (> (length tibetan-text) 0)
            (string-trim tibetan-text))))
       (t nil)))))

(defun tibetan-compound-extract-lines (start-line end-line)
  "Extract Tibetan lines between START-LINE and END-LINE.
Returns list of (line-number . tibetan-text)."
  (save-excursion
    (let ((lines '()))
      (goto-char (point-min))
      (forward-line (1- start-line))
      (while (<= (line-number-at-pos) end-line)
        (let ((text (tibetan-compound--extract-tibetan-from-line)))
          (when (and text (not (string-empty-p text)))
            (push (cons (line-number-at-pos) text) lines)))
        (forward-line 1)
        (when (eobp) (cl-return)))
      (nreverse lines))))

;; ============================================================================
;; PATH AND FILENAME FUNCTIONS
;; ============================================================================

(defun tibetan-compound-get-folder ()
  "Get the compound analysis folder path for current buffer.
Creates the folder if it doesn't exist."
  (let* ((source-file (buffer-file-name))
         (source-dir (file-name-directory source-file))
         (analysis-dir (expand-file-name "analysis" source-dir)))
    (unless (file-exists-p analysis-dir)
      (make-directory analysis-dir t))
    analysis-dir))

(defun tibetan-compound-filename (compound-id)
  "Generate filename for compound COMPOUND-ID.
Returns filename like \='compound-001.org\='."
  (format "compound-%03d.org" compound-id))

(defun tibetan-compound-get-next-id ()
  "Get the next available compound ID.
Scans existing compound-NNN.org files in analysis folder."
  (let* ((folder (tibetan-compound-get-folder))
         (files (directory-files folder nil "^compound-[0-9]+\\.org$"))
         (max-id 0))
    (dolist (file files)
      (when (string-match "compound-\\([0-9]+\\)\\.org" file)
        (let ((id (string-to-number (match-string 1 file))))
          (when (> id max-id)
            (setq max-id id)))))
    (1+ max-id)))

(defun tibetan-compound-compute-hash (lines)
  "Compute MD5 hash for LINES (list of tibetan texts).
Used for change detection."
  (md5 (mapconcat #'cdr lines "")))

;; ============================================================================
;; INTER-LINE GRAMMAR ANALYSIS
;; ============================================================================

(defun tibetan-compound-analyze-connectors (lines)
  "Analyze how LINES connect grammatically.
Returns list of connector analyses."
  (let ((connectors '())
        (prev-line nil))
    (dolist (line-data lines)
      (let ((_text (cdr line-data))
            (line-num (car line-data)))
        (when prev-line
          ;; Check for converb endings that link to next line
          (let ((prev-text (cdr prev-line)))
            (cond
             ;; ནས་ converb: "after V-ing" links action to next
             ((string-match "ནས།?$" prev-text)
              (push `((from . ,(car prev-line))
                      (to . ,line-num)
                      (connector . "ནས")
                      (type . converb)
                      (function . "Sequential action: 'after V-ing, [then]...'"))
                    connectors))
             ;; ཏེ་/སྟེ་/དེ་ converb
             ((string-match "\\(ཏེ\\|སྟེ\\|དེ\\)།?$" prev-text)
              (push `((from . ,(car prev-line))
                      (to . ,line-num)
                      (connector . ,(match-string 1 prev-text))
                      (type . converb)
                      (function . "Coordination: 'V-ing' or 'and then'"))
                    connectors))
             ;; ཅིང་/ཞིང་/ཤིང་ converb
             ((string-match "\\(ཅིང\\|ཞིང\\|ཤིང\\)།?$" prev-text)
              (push `((from . ,(car prev-line))
                      (to . ,line-num)
                      (connector . ,(match-string 1 prev-text))
                      (type . converb)
                      (function . "Simultaneous: 'while V-ing' or lists"))
                    connectors))
             ;; པ་/བ་ nominalizer often links to next
             ((string-match "\\(པ\\|བ\\)།$" prev-text)
              (push `((from . ,(car prev-line))
                      (to . ,line-num)
                      (connector . "nominalized clause")
                      (type . nominalization)
                      (function . "Nominalized clause serving as argument for next line"))
                    connectors))
             ;; དང་ conjunction
             ((string-match "དང་།?$" prev-text)
              (push `((from . ,(car prev-line))
                      (to . ,line-num)
                      (connector . "དང")
                      (type . conjunction)
                      (function . "Conjunction: 'and' linking parallel elements"))
                    connectors)))))
        (setq prev-line line-data)))
    (nreverse connectors)))

(defun tibetan-compound-analyze-topic-flow (lines)
  "Analyze topic/subject flow across LINES.
Identifies shared topics and referent tracking."
  (let ((analyses '())
        (all-words '()))
    ;; Collect all words from all lines
    (dolist (line-data lines)
      (let* ((text (cdr line-data))
             (words (split-string text "་" t)))
        (dolist (word words)
          (push word all-words))))
    ;; Look for repeated key terms (potential topic continuity)
    (let ((word-counts (make-hash-table :test 'equal)))
      (dolist (word all-words)
        (let ((clean (replace-regexp-in-string "[།༎]" "" word)))
          (when (> (length clean) 1)  ; Skip single-syllable particles
            (puthash clean (1+ (gethash clean word-counts 0)) word-counts))))
      ;; Find repeated terms
      (maphash (lambda (word count)
                 (when (> count 1)
                   (push `((term . ,word)
                           (occurrences . ,count)
                           (note . "Repeated term - possible topic continuity"))
                         analyses)))
               word-counts))
    analyses))

;; ============================================================================
;; TRANSLATION SUGGESTION
;; ============================================================================


;; ============================================================================
;; CONTENT GENERATION
;; ============================================================================

(defun tibetan-compound-build-line-translation (gloss verbs connectors line-idx total-lines)
  "Build a draft English translation for a single line.
GLOSS is alist of (tibetan . english) pairs.
VERBS is list of verb analyses.
CONNECTORS contains inter-line grammar.
LINE-IDX is current line number (1-based).
TOTAL-LINES is total number of lines."
  (let* ((content-words '())
         (main-verb (car verbs))
         (verb-meaning (when (and main-verb (listp main-verb) (consp (car main-verb)))
                         (car (split-string (or (alist-get 'meaning main-verb) "") "," t))))
         ;; Common particles to skip in translation
         (particles '("ནི" "ཡང" "གི" "ཀྱི" "འི" "ཡི" "གྱི" "ལ" "ན" "དུ" "སུ" "ར" "ས" "ནས" "ལས" "དང"))
         ;; Check for line-ending connector
         (line-connector nil))

    ;; Find connector for this line
    (dolist (conn connectors)
      (when (= (alist-get 'from conn) line-idx)
        (setq line-connector conn)))

    ;; Build content words list (skip particles)
    (dolist (pair gloss)
      (let ((tib (car pair))
            (eng (cdr pair)))
        (unless (or (string= eng "?")
                    (string= eng "")
                    (member tib particles))
          (push (cons tib eng) content-words))))
    (setq content-words (nreverse content-words))

    ;; Build the line translation
    (let ((parts '()))
      ;; Add content words
      (dolist (word content-words)
        (let ((eng (cdr word)))
          ;; Clean up the English - take first meaning if multiple
          (when (string-match "^\\([^,;]+\\)" eng)
            (setq eng (string-trim (match-string 1 eng))))
          (push eng parts)))

      ;; Build the line
      (let ((line-text (string-join (nreverse parts) " ")))
        ;; Add verb if not already included
        (when (and verb-meaning
                   (not (cl-some (lambda (w) (string-match-p (regexp-quote verb-meaning) (cdr w)))
                                 content-words)))
          (setq line-text (concat line-text " " verb-meaning)))

        ;; Add connector suffix based on grammar
        (when line-connector
          (let ((conn-type (alist-get 'type line-connector))
                (connector (alist-get 'connector line-connector)))
            (cond
             ((and (eq conn-type 'converb) (string= connector "ནས"))
              ;; Only downcase if text is pure ASCII
              (let ((lower-text (if (string-match-p "^[[:ascii:]]+$" line-text)
                                    (downcase line-text)
                                  line-text)))
                (setq line-text (concat "Having " lower-text ","))))
             ((and (eq conn-type 'converb) (member connector '("ཏེ" "སྟེ" "དེ")))
              (setq line-text (concat line-text ",")))
             ((and (eq conn-type 'converb) (member connector '("ཅིང" "ཞིང" "ཤིང")))
              (setq line-text (concat line-text " and")))
             ((eq conn-type 'conjunction)
              (setq line-text (concat line-text " and"))))))

        ;; Capitalize first letter (handle multi-byte characters safely)
        (when (> (length line-text) 0)
          (let ((first-char (string (aref line-text 0))))
            ;; Only capitalize if it's an ASCII letter
            (when (string-match "^[a-z]" first-char)
              (setq line-text (concat (upcase first-char)
                                      (substring line-text 1))))))

        ;; Add period if last line
        (when (= line-idx total-lines)
          (setq line-text (concat line-text ".")))

        line-text))))

(defun tibetan-compound-generate-translations-section (lines connectors context)
  "Generate translation section for LINES.
CONNECTORS provides inter-line grammar analysis.
CONTEXT provides tradition-specific terminology.
Returns org-mode formatted string with actual draft translations."
  (let* ((context-name (plist-get (cdr context) :name))
         (all-text (mapconcat #'cdr lines " "))
         (all-vocab (make-hash-table :test 'equal))
         (line-data-list '())
         (total-lines (length lines)))

    ;; Collect vocabulary and build line data
    (let ((line-idx 1))
      (dolist (line-data lines)
        (let* ((tibetan (cdr line-data))
               (parsed (when (fboundp 'tibetan-parse-enhanced)
                         (tibetan-parse-enhanced tibetan)))
               (words (alist-get 'words parsed))
               (multiword-units (alist-get 'multiword-units parsed))
               (verbs (when (fboundp 'tibetan-extract-verbs-compound-aware)
                        (tibetan-extract-verbs-compound-aware tibetan words multiword-units)))
               (line-gloss '()))

          ;; Collect multiword units
          (dolist (unit multiword-units)
            (let* ((form (nth 2 unit))
                   (data (nth 3 unit))
                   (english (alist-get 'english data)))
              (when english
                (puthash form english all-vocab))))

          ;; Collect single words
          (when (and words (boundp 'tibetan-comprehensive-vocabulary))
            (dolist (word words)
              (let ((meaning (gethash word tibetan-comprehensive-vocabulary)))
                (when meaning
                  (puthash word meaning all-vocab)))))

          ;; Build line gloss
          (when (and words (fboundp 'tibetan-build-compound-aware-segments))
            (let ((segments (tibetan-build-compound-aware-segments words multiword-units)))
              (dolist (seg segments)
                (let ((meaning (or (gethash seg all-vocab)
                                   (when (boundp 'tibetan-comprehensive-vocabulary)
                                     (gethash seg tibetan-comprehensive-vocabulary)))))
                  (push (cons seg (or meaning "?")) line-gloss)))))

          ;; Store for translation building
          (push `((line-idx . ,line-idx)
                  (tibetan . ,tibetan)
                  (gloss . ,(nreverse line-gloss))
                  (verbs . ,verbs))
                line-data-list)
          (setq line-idx (1+ line-idx)))))

    (setq line-data-list (nreverse line-data-list))

    (with-temp-buffer
      ;; Working Translation (For Study) - GENERATED
      (insert "** Working Translation (For Study)\n\n")
      (insert "#+begin_quote\n")
      ;; Build working translation from glosses
      (dolist (ld line-data-list)
        (let* ((line-idx (alist-get 'line-idx ld))
               (gloss (alist-get 'gloss ld))
               (verbs (alist-get 'verbs ld))
               (line-trans (tibetan-compound-build-line-translation
                            gloss verbs connectors line-idx total-lines)))
          (insert (format "%s\n" line-trans))))
      (insert "#+end_quote\n\n")

      ;; Madhyamaka-Precise Translation (Technical) - GENERATED with Tibetan terms
      (insert "** Madhyamaka-Precise Translation (Technical)\n\n")
      (insert (format "/Following %s interpretation:/\n\n" context-name))
      (insert "#+begin_quote\n")
      ;; Build technical translation with Tibetan terms in parentheses
      (dolist (ld line-data-list)
        (let* ((line-idx (alist-get 'line-idx ld))
               (gloss (alist-get 'gloss ld))
               (_verbs (alist-get 'verbs ld))
               (parts '()))
          ;; Build with technical terms
          (dolist (pair gloss)
            (let ((tib (car pair))
                  (eng (cdr pair)))
              (unless (or (string= eng "?")
                          (string= eng "")
                          (member tib '("ནི" "ཡང" "གི" "ཀྱི" "འི" "ཡི" "ལ" "ན" "དུ" "སུ" "ར")))
                ;; For technical terms, include Tibetan in parentheses
                (when (string-match "^\\([^,;]+\\)" eng)
                  (setq eng (string-trim (match-string 1 eng))))
                ;; Check if this is a key philosophical term (multi-syllable)
                (if (> (length (split-string tib "་" t)) 1)
                    (push (format "%s (%s)" eng tib) parts)
                  (push eng parts)))))
          ;; Build line
          (let ((line-text (string-join (nreverse parts) " ")))
            ;; Capitalize first letter (handle multi-byte characters safely)
            (when (> (length line-text) 0)
              (let ((first-char (string (aref line-text 0))))
                (when (string-match "^[a-z]" first-char)
                  (setq line-text (concat (upcase first-char)
                                          (substring line-text 1))))))
            (when (= line-idx total-lines)
              (setq line-text (concat line-text ".")))
            (insert (format "%s\n" line-text)))))
      (insert "#+end_quote\n\n")

      ;; DharmaMitra-style Translation (if available)
      (insert "** DharmaMitra-Style Translation\n\n")
      (let ((dm-trans (when (fboundp 'tibetan-get-dharmamitra-translation)
                        (tibetan-get-dharmamitra-translation all-text))))
        (if (and dm-trans (not (string= dm-trans "")))
            (progn
              (insert "#+begin_quote\n")
              (insert dm-trans)
              (insert "\n#+end_quote\n\n"))
          (insert "/[DharmaMitra translation not available]/\n\n")))

      ;; Translation Notes
      (insert "** Translation Notes\n\n")

      ;; Key terms with explanations
      (let ((key-terms '()))
        ;; Collect Madhyamaka terms
        (when (fboundp 'tibetan-extract-madhyamaka-vocabulary)
          (let ((terms (tibetan-extract-madhyamaka-vocabulary all-text)))
            (dolist (term-pair terms)
              (push term-pair key-terms))))
        ;; Collect multi-word units as key terms
        (dolist (ld line-data-list)
          (let ((gloss (alist-get 'gloss ld)))
            (dolist (pair gloss)
              (let ((tib (car pair))
                    (eng (cdr pair)))
                (when (and (> (length (split-string tib "་" t)) 1)
                           (not (string= eng "?"))
                           (not (assoc tib key-terms)))
                  (push (cons tib eng) key-terms))))))

        (when key-terms
          (insert "Key terms and translation choices:\n\n")
          (dolist (term-pair (nreverse key-terms))
            (let ((tib (car term-pair))
                  (eng (cdr term-pair)))
              ;; Get first meaning
              (when (string-match "^\\([^,;]+\\)" eng)
                (setq eng (string-trim (match-string 1 eng))))
              (insert (format "- *%s* (%s): %s\n"
                              tib
                              (if (fboundp 'tibetan-to-wylie-fixed)
                                  (condition-case nil
                                      (tibetan-to-wylie-fixed tib)
                                    (error "?"))
                                "?")
                              eng))))
          (insert "\n")))

      ;; Sentence flow guidance
      (when connectors
        (insert "*** Sentence Flow\n")
        (insert "How the lines connect grammatically:\n\n")
        (dolist (conn connectors)
          (let ((from (alist-get 'from conn))
                (to (alist-get 'to conn))
                (connector (alist-get 'connector conn))
                (conn-type (alist-get 'type conn)))
            (insert (format "- Line %d → %d via *%s*: " from to connector))
            (cond
             ((eq conn-type 'converb)
              (cond
               ((string= connector "ནས")
                (insert "Sequential action — \"Having [done X], ...\" or \"After [X]-ing, ...\"\n"))
               ((member connector '("ཏེ" "སྟེ" "དེ"))
                (insert "Coordination — \"[X]-ing, ...\" or \"and then ...\"\n"))
               ((member connector '("ཅིང" "ཞིང" "ཤིང"))
                (insert "Simultaneous — \"while [X]-ing\" or list with \"and\"\n"))
               (t (insert (format "Converb: %s\n" connector)))))
             ((eq conn-type 'nominalization)
              (insert "Nominalized clause — \"that which [X]\" or \"the [X]-ing\"\n"))
             ((eq conn-type 'conjunction)
              (insert "Conjunction — \"and\" or \"together with\"\n"))
             (t (insert (format "%s\n" conn-type))))))
        (insert "\n"))

      (buffer-string))))

(defun tibetan-compound-generate-content (lines context)
  "Generate compound analysis content for LINES with CONTEXT.
Returns org-mode formatted string."
  (let* ((context-name (plist-get (cdr context) :name))
         (connectors (tibetan-compound-analyze-connectors lines))
         (topic-flow (tibetan-compound-analyze-topic-flow lines)))
    (with-temp-buffer
      ;; All lines combined (Tibetan text)
      (insert "** Complete Text\n")
      (dolist (line-data lines)
        (insert (format "%s\n" (cdr line-data))))
      (insert "\n")

      ;; Wylie for complete compound
      (insert "** Wylie Transliteration\n")
      (dolist (line-data lines)
        (let ((tibetan (cdr line-data)))
          (if (fboundp 'tibetan-to-wylie-fixed)
              (insert (condition-case nil
                          (tibetan-to-wylie-fixed tibetan)
                        (error "[Wylie error]")))
            (insert "[Wylie not available]"))
          (insert " |\n")))
      (insert "\n")

      ;; *** TRANSLATIONS IMMEDIATELY AFTER WYLIE ***
      (insert (tibetan-compound-generate-translations-section lines connectors context))

      ;; Meter analysis
      (insert "** Meter Analysis\n")
      (let ((all-seven t)
            (counts '()))
        (dolist (line-data lines)
          (let ((count (when (fboundp 'tibetan-count-syllables)
                         (tibetan-count-syllables (cdr line-data)))))
            (push count counts)
            (when (and count (/= count 7))
              (setq all-seven nil))))
        (setq counts (nreverse counts))
        (if all-seven
            (insert (format "Standard 7-syllable meter (%d lines) ✓\n" (length lines)))
          (insert "Syllable counts: ")
          (insert (mapconcat #'number-to-string counts ", "))
          (insert "\n")))
      (insert "\n")

      ;; Line-by-line analysis (SHAD-BY-SHAD)
      (insert "** Shad-by-Shad (Word-by-Word) Analysis\n")
      (let ((line-num 1))
        (dolist (line-data lines)
          (let* ((tibetan (cdr line-data))
                 (_src-line (car line-data))
                 (syllable-count (when (fboundp 'tibetan-count-syllables)
                                   (tibetan-count-syllables tibetan))))
            (insert (format "*** LINE %d: %s\n" line-num tibetan))
            (when syllable-count
              (insert (format "Syllables: %d %s\n\n"
                              syllable-count
                              (if (= syllable-count 7) "✓" ""))))
            ;; Individual line analysis (reuse segment analysis)
            (when (fboundp 'tibetan-analysis-generate-content)
              (let ((analysis (tibetan-analysis-generate-content tibetan)))
                ;; Indent the analysis under this line
                (insert (replace-regexp-in-string "^\\*\\*" "****" analysis))))
            (insert "\n"))
          (setq line-num (1+ line-num))))

      ;; Inter-line grammar
      (insert "** Inter-Line Grammar\n")
      (if connectors
          (progn
            (insert "How the lines connect grammatically:\n\n")
            (dolist (conn connectors)
              (let ((from (alist-get 'from conn))
                    (to (alist-get 'to conn))
                    (connector (alist-get 'connector conn))
                    (conn-type (alist-get 'type conn))
                    (function (alist-get 'function conn)))
                (insert (format "- Line %d → Line %d via *%s* (%s)\n"
                                from to connector conn-type))
                (insert (format "  %s\n\n" function)))))
        (insert "[No explicit inter-line connectors detected]\n\n"))

      ;; Topic flow
      (insert "** Topic/Subject Flow\n")
      (if topic-flow
          (progn
            (insert "Repeated terms suggesting topic continuity:\n\n")
            (dolist (item topic-flow)
              (let ((term (alist-get 'term item))
                    (count (alist-get 'occurrences item)))
                (insert (format "- *%s* (×%d)\n" term count)))))
        (insert "[No repeated key terms detected]\n"))
      (insert "\n")

      ;; Context information
      (insert (format "** Context: %s\n" context-name))
      (let ((key-concepts (plist-get (cdr context) :key-concepts)))
        (when key-concepts
          (insert "Key concepts to watch for:\n")
          (dolist (concept key-concepts)
            (let ((found (cl-some (lambda (line) (string-match-p concept (cdr line))) lines)))
              (insert (format "- %s %s\n" concept (if found "✓" "")))))))
      (insert "\n")

      ;; Madhyamaka terms in detail (if available)
      (when (fboundp 'tibetan-extract-madhyamaka-vocabulary)
        (insert "** Madhyamaka Terminology (Detailed)\n")
        (let* ((all-text (mapconcat #'cdr lines " "))
               (terms (tibetan-extract-madhyamaka-vocabulary all-text)))
          (if terms
              (dolist (term-pair terms)
                (insert (format "*** %s\n" (car term-pair)))
                (insert (format "%s\n\n" (cdr term-pair))))
            (insert "[No Madhyamaka technical terms detected]\n"))))
      (insert "\n")

      (buffer-string))))

;; ============================================================================
;; FILE OPERATIONS
;; ============================================================================

(defun tibetan-compound-create-file (compound-id lines source-file auto-content)
  "Create a new compound analysis file.
COMPOUND-ID is the numeric ID.
LINES is list of (line-num . tibetan-text).
SOURCE-FILE is path to source.
AUTO-CONTENT is generated analysis.
Returns the filepath."
  (let* ((folder (tibetan-compound-get-folder))
         (filename (tibetan-compound-filename compound-id))
         (filepath (expand-file-name filename folder))
         (hash (tibetan-compound-compute-hash lines))
         (source-name (file-name-nondirectory source-file))
         (line-range (format "%d-%d" (caar lines) (caar (last lines)))))
    (with-temp-file filepath
      (insert (format "#+TITLE: Compound %d Analysis\n" compound-id))
      (insert (format "#+SOURCE: [[file:../%s][%s]] (lines %s)\n"
                      source-name source-name line-range))
      (insert (format "#+TIBETAN_HASH: %s\n" hash))
      (insert (format "#+ANALYSIS_VERSION: %s\n" tibetan-compound-analysis-version))
      (insert (format "#+CREATED: %s\n" (format-time-string "%Y-%m-%d")))
      (insert (format "#+LAST_ANALYZED: %s\n" (format-time-string "%Y-%m-%d")))
      (insert (format "#+LINE_COUNT: %d\n\n" (length lines)))

      ;; Tibetan text section
      (insert "* Tibetan Text\n")
      (dolist (line-data lines)
        (insert (format "%s\n" (cdr line-data))))
      (insert "\n")

      ;; Auto-analysis section
      (insert "* Auto-Analysis\n")
      (insert ":PROPERTIES:\n")
      (insert ":GENERATED: t\n")
      (insert ":END:\n\n")
      (insert auto-content)
      (insert "\n")

      ;; User sections
      (insert "* Working Translation\n")
      (insert "[Your translation here]\n\n")

      (insert "* Translation Notes\n")
      (insert "[Notes on translation choices, alternatives, difficulties]\n\n")

      (insert "* Grammatical Notes\n")
      (insert "[Your grammatical observations and questions]\n\n")

      (insert "* Philosophical Commentary\n")
      (insert "[Connections to doctrine, commentary tradition, etc.]\n\n")

      (insert "* Footnotes\n")
      (insert "[Scholarly footnotes for publication]\n"))

    filepath))

(defun tibetan-compound-check-sync (filepath lines)
  "Check if compound analysis at FILEPATH is in sync with LINES.
Returns t if hashes match, nil otherwise."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TIBETAN_HASH:\\s-*\\(.+\\)$" nil t)
        (let ((stored-hash (string-trim (match-string 1)))
              (current-hash (tibetan-compound-compute-hash lines)))
          (string= stored-hash current-hash))))))

(defun tibetan-compound-regenerate-auto (filepath lines context)
  "Regenerate auto-analysis in FILEPATH for LINES with CONTEXT.
Preserves user sections."
  (let ((auto-content (tibetan-compound-generate-content lines context))
        (new-hash (tibetan-compound-compute-hash lines)))
    (with-current-buffer (find-file-noselect filepath)
      ;; Update hash
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TIBETAN_HASH:.*$" nil t)
        (replace-match (format "#+TIBETAN_HASH: %s" new-hash)))

      ;; Update last-analyzed date
      (goto-char (point-min))
      (when (re-search-forward "^#\\+LAST_ANALYZED:.*$" nil t)
        (replace-match (format "#+LAST_ANALYZED: %s" (format-time-string "%Y-%m-%d"))))

      ;; Update Tibetan Text section
      (goto-char (point-min))
      (when (re-search-forward "^\\* Tibetan Text\n" nil t)
        (let ((section-start (point)))
          (if (re-search-forward "^\\* " nil t)
              (progn
                (beginning-of-line)
                (delete-region section-start (point)))
            (delete-region section-start (point-max)))
          (goto-char section-start)
          (dolist (line-data lines)
            (insert (format "%s\n" (cdr line-data))))
          (insert "\n")))

      ;; Replace Auto-Analysis section
      (goto-char (point-min))
      (if (re-search-forward "^\\* Auto-Analysis\n" nil t)
          (let ((section-start (match-beginning 0)))
            (if (re-search-forward "^\\* " nil t)
                (progn
                  (beginning-of-line)
                  (delete-region section-start (point)))
              (delete-region section-start (point-max)))
            (goto-char section-start)
            (insert "* Auto-Analysis\n")
            (insert ":PROPERTIES:\n")
            (insert ":GENERATED: t\n")
            (insert ":END:\n\n")
            (insert auto-content)
            (insert "\n"))
        ;; Section missing, add it
        (goto-char (point-max))
        (insert "\n* Auto-Analysis\n")
        (insert ":PROPERTIES:\n")
        (insert ":GENERATED: t\n")
        (insert ":END:\n\n")
        (insert auto-content))

      (save-buffer)
      (message "Re-analyzed compound. User notes preserved."))))

;; ============================================================================
;; FIND EXISTING ANALYSIS
;; ============================================================================

(defun tibetan-compound-find-existing (lines)
  "Find existing compound analysis file for LINES.
Returns filepath if found, nil otherwise."
  (let* ((folder (tibetan-compound-get-folder))
         (target-hash (tibetan-compound-compute-hash lines))
         (files (directory-files folder t "^compound-[0-9]+\\.org$")))
    (cl-find-if
     (lambda (file)
       (with-temp-buffer
         (insert-file-contents file)
         (goto-char (point-min))
         (when (re-search-forward "^#\\+TIBETAN_HASH:\\s-*\\(.+\\)$" nil t)
           (string= (string-trim (match-string 1)) target-hash))))
     files)))

;; ============================================================================
;; MAIN COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-open-compound-analysis ()
  "Open or create persistent compound analysis.
Detects compound boundaries automatically or uses region.
Opens analysis in side window."
  (interactive)
  (let ((bounds (tibetan-compound-detect-boundaries)))
    (if (not bounds)
        (message "No compound detected. Select a region or position cursor in verse.")
      (let* ((start-line (car bounds))
             (end-line (cdr bounds))
             (lines (tibetan-compound-extract-lines start-line end-line))
             (context (tibetan-compound-get-context))
             (source-file (buffer-file-name)))

        (if (not lines)
            (message "No Tibetan text found in lines %d-%d" start-line end-line)
          ;; Check for existing analysis
          (let ((existing (tibetan-compound-find-existing lines)))
            (if existing
                ;; Open existing
                (progn
                  (unless (tibetan-compound-check-sync existing lines)
                    (message "WARNING: Source text has changed since last analysis!"))
                  (let ((buf (find-file-noselect existing)))
                    (with-current-buffer buf
                      (tibetan-analysis-setup-faces))
                    (display-buffer-in-side-window buf
                                                   '((side . right)
                                                     (window-width . 0.5)))))
              ;; Create new
              (let* ((compound-id (tibetan-compound-get-next-id))
                     (auto-content (tibetan-compound-generate-content lines context))
                     (new-filepath (tibetan-compound-create-file
                                    compound-id lines source-file auto-content)))
                (message "Created compound analysis: %s" new-filepath)
                (let ((buf (find-file-noselect new-filepath)))
                  (with-current-buffer buf
                    (tibetan-analysis-setup-faces))
                  (display-buffer-in-side-window buf
                                                 '((side . right)
                                                   (window-width . 0.5))))))))))))

;;;###autoload
(defun tibetan-reanalyze-compound ()
  "Re-analyze current compound, preserving user notes.
Must be called from within a compound analysis buffer."
  (interactive)
  (let ((filepath (buffer-file-name)))
    (unless (and filepath (string-match "compound-[0-9]+\\.org$" filepath))
      (error "Not in a compound analysis buffer"))

    ;; Get source file and line range
    (save-excursion
      (goto-char (point-min))
      (unless (re-search-forward "^#\\+SOURCE:.*\\[\\[file:\\.\\./" nil t)
        (error "Cannot find source file reference"))
      (let* ((source-match (buffer-substring (point) (line-end-position)))
             (source-file (when (string-match "\\([^]]+\\)\\]" source-match)
                            (match-string 1 source-match)))
             (source-path (expand-file-name
                           (concat "../" source-file)
                           (file-name-directory filepath))))

        ;; Get lines from * Tibetan Text section
        (goto-char (point-min))
        (unless (re-search-forward "^\\* Tibetan Text\n" nil t)
          (error "Cannot find Tibetan Text section"))
        (let ((lines '())
              (line-num 1))
          (while (and (not (eobp))
                      (not (looking-at "^\\* ")))
            (let ((text (string-trim (buffer-substring-no-properties
                                      (line-beginning-position)
                                      (line-end-position)))))
              (when (and (> (length text) 0)
                         (string-match "[ༀ-࿿]" text))
                (push (cons line-num text) lines)))
            (setq line-num (1+ line-num))
            (forward-line 1))
          (setq lines (nreverse lines))

          (when lines
            (let ((context (with-current-buffer (find-file-noselect source-path)
                             (tibetan-compound-get-context))))
              (tibetan-compound-regenerate-auto filepath lines context))))))))

;; ============================================================================
;; ANALYSIS FUNCTIONS FOR INTERACTIVE COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-compound-analyze-document-structure ()
  "Analyze the structure of the current document.
Returns a list of analysis results or nil if no structure found."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((headings '()))
      (while (re-search-forward "^\\*+\\s-+\\(.+\\)$" nil t)
        (push (list (match-string 1) (line-number-at-pos)) headings))
      (when headings
        (nreverse headings)))))

(defun tibetan-compound-analyze-verse-structure (lines)
  "Analyze verse structure from LINES.
LINES should be a list of (line-num . text) cons cells.
Returns a list of verse analysis or nil."
  (when lines
    (let ((analysis '()))
      (dolist (line-data lines)
        (let ((text (cdr line-data)))
          (when (string-match "[ༀ-࿿]" text)
            (push (list :line (car line-data) :text text) analysis))))
      (when analysis
        (nreverse analysis)))))

(provide 'tibetan-compound-analysis)
;;; tibetan-compound-analysis.el ends here
