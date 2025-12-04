;;; tibetan-text-classifier.el --- Classify Tibetan texts for appropriate analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Detects text classification to choose appropriate analysis tools
;;
;; Classifications:
;; - classical        → Prose texts for Tibetisch III (Bialek grammar)
;; - madhyamaka-verse → Madhyamaka verses (meter + philosophical terms)
;; - kagyu-verse      → Kagyü tradition verses
;; - gelug-verse      → Gelug tradition verses
;; - bhutanese        → Bhutanese tradition texts
;; - prose            → General prose (default)
;;
;; Usage:
;;   At top of file, add classification header:
;;   #+TIBETAN_TEXT_TYPE: madhyamaka-verse
;;   or
;;   # TIBETAN_TEXT_TYPE: classical

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; TEXT TYPE DEFINITIONS
;; ============================================================================

(defvar tibetan-text-types
  '((classical
     :description "Classical Tibetan prose for classroom use (Bialek framework)"
     :features (prose bialek-grammar converbial-focus)
     :tools (bialek-grammar translation-suggestion))

    (madhyamaka-verse
     :description "Madhyamaka philosophical verses (7-syllable meter, Gelug tradition)"
     :features (verse 7-syllable-meter madhyamaka-terms gelug-tradition)
     :tools (syllable-counter metrical-filler madhyamaka-terms critical-apparatus))

    (kagyu-verse
     :description "Kagyü tradition verses (Mahāmudrā, meditation instructions)"
     :features (verse kagyu-terms mahamudra)
     :tools (syllable-counter kagyu-vocabulary))

    (gelug-verse
     :description "Gelug tradition verses (philosophical, debate format)"
     :features (verse gelug-terms debate-format)
     :tools (syllable-counter gelug-terms))

    (bhutanese
     :description "Bhutanese tradition texts"
     :features (bhutanese-dialect special-vocabulary)
     :tools (bhutanese-vocabulary))

    (prose
     :description "General Tibetan prose (default)"
     :features (prose general-grammar)
     :tools (basic-grammar basic-vocabulary)))
  "Definitions of Tibetan text types and their characteristics.")

;; ============================================================================
;; CLASSIFICATION DETECTION
;; ============================================================================

(defun tibetan-detect-text-type ()
  "Detect text type from current buffer.
Checks for explicit classification header first, then uses heuristics.
Returns symbol: classical, madhyamaka-verse, kagyu-verse, etc."
  (or (tibetan-get-explicit-classification)
      (tibetan-classify-by-heuristics)))

(defun tibetan-get-explicit-classification ()
  "Get explicit text classification from buffer header.
Looks for:
  #+TIBETAN_TEXT_TYPE: madhyamaka-verse
  or
  # TIBETAN_TEXT_TYPE: classical
Returns symbol or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           "^#\\+?TIBETAN_TEXT_TYPE:\\s-*\\([-a-z]+\\)"
           (min (point-max) 2000) t)
      (intern (match-string 1)))))

(defun tibetan-classify-by-heuristics ()
  "Classify text type using heuristics when no explicit header.
Analyzes:
- Presence of verse markers/meter
- Technical terminology
- Sentence structure
Returns symbol: classical, madhyamaka-verse, etc."
  (let ((text (buffer-substring-no-properties (point-min)
                                              (min (point-max) 5000))))
    (cond
     ;; Check for Madhyamaka verse indicators
     ((and (tibetan-text-has-verse-structure-p text)
           (tibetan-text-has-madhyamaka-terms-p text))
      'madhyamaka-verse)

     ;; Check for Kagyü indicators (Mahāmudrā terms)
     ((and (tibetan-text-has-verse-structure-p text)
           (tibetan-text-has-kagyu-terms-p text))
      'kagyu-verse)

     ;; Check for classroom prose (Bialek indicators)
     ((tibetan-text-has-bialek-structure-p text)
      'classical)

     ;; Default to prose
     (t 'prose))))

;; ============================================================================
;; HEURISTIC HELPERS
;; ============================================================================

(defun tibetan-text-has-verse-structure-p (text)
  "Check if TEXT has verse structure.
Looks for:
- Short lines (likely 7-syllable)
- Regular line breaks
- Line-final particles (common in verse)"
  (and
   ;; Has shad marks (verse punctuation)
   (string-match-p "།" text)
   ;; Not too long (verses have short lines)
   (< (length (split-string text "།" t)) 20)
   ;; Has verse-typical structure
   (string-match-p "།.*།.*།" text)))

(defun tibetan-text-has-madhyamaka-terms-p (text)
  "Check if TEXT contains Madhyamaka technical terms."
  (or (string-match-p "དབུ་མ" text)       ; Madhyamaka
      (string-match-p "སྟོང་པ" text)       ; Empty
      (string-match-p "རྟེན་འབྱུང" text)  ; Dependent arising
      (string-match-p "བདེན་གཉིས" text)   ; Two truths
      (string-match-p "དོན་དམ" text)       ; Ultimate
      (string-match-p "ཀུན་རྫོབ" text)))   ; Conventional

(defun tibetan-text-has-kagyu-terms-p (text)
  "Check if TEXT contains Kagyü/Mahāmudrā terms."
  (or (string-match-p "ཕྱག་རྒྱ་ཆེན་པོ" text)    ; Mahāmudrā
      (string-match-p "བདེ་སྟོང" text)          ; Bliss-emptiness
      (string-match-p "རྩ་བའི་བླ་མ" text)      ; Root guru
      (string-match-p "མ་ཧཱ་མུ་དྲཱ" text)))      ; Mahāmudrā (Sanskrit)

(defun tibetan-text-has-bialek-structure-p (text)
  "Check if TEXT has Bialek classroom text structure.
Looks for:
- Sentence markers
- Segment markers
- Org-mode headings"
  (or (string-match-p "\\*\\*\\* Segment" text)
      (string-match-p "〔seg:" text)
      (string-match-p "\\*\\* Sentence" text)))

;; ============================================================================
;; CLASSIFICATION INFO
;; ============================================================================

(defun tibetan-get-text-type-info (text-type)
  "Get information about TEXT-TYPE.
Returns plist with :description, :features, :tools."
  (cdr (assq text-type tibetan-text-types)))

(defun tibetan-get-tools-for-text-type (text-type)
  "Get list of appropriate tools for TEXT-TYPE.
Returns list of tool symbols."
  (plist-get (tibetan-get-text-type-info text-type) :tools))

(defun tibetan-display-text-type-info ()
  "Display information about current text type."
  (interactive)
  (let* ((text-type (tibetan-detect-text-type))
         (info (tibetan-get-text-type-info text-type))
         (description (plist-get info :description))
         (tools (plist-get info :tools)))
    (message "Text type: %s\n%s\nTools: %s"
             text-type
             description
             (mapconcat 'symbol-name tools ", "))))

;; ============================================================================
;; FILE HEADER INSERTION
;; ============================================================================

(defun tibetan-insert-text-type-header (text-type)
  "Insert TEXT-TYPE classification header at top of buffer.
Prompts for text type if not provided."
  (interactive
   (list (intern (completing-read
                  "Text type: "
                  '("classical" "madhyamaka-verse" "kagyu-verse"
                    "gelug-verse" "bhutanese" "prose")
                  nil t))))
  (save-excursion
    (goto-char (point-min))
    ;; Check if already has classification
    (if (re-search-forward "^#\\+?TIBETAN_TEXT_TYPE:"
                          (min (point-max) 2000) t)
        (progn
          (beginning-of-line)
          (kill-line)
          (insert (format "#+TIBETAN_TEXT_TYPE: %s" text-type)))
      ;; Insert new header
      (goto-char (point-min))
      (when (looking-at "^#\\+")  ; After existing org headers
        (while (and (looking-at "^#\\+") (not (eobp)))
          (forward-line 1)))
      (insert (format "#+TIBETAN_TEXT_TYPE: %s\n" text-type))))
  (message "Text type set to: %s" text-type))

(provide 'tibetan-text-classifier)
;;; tibetan-text-classifier.el ends here
