;;; tibetan-ocr-validate.el --- Dictionary validation for Tibetan OCR -*- lexical-binding: t -*-

;;; Commentary:
;; Validates Tibetan text against local dictionaries to identify
;; potential OCR errors.
;;
;; Uses existing data sources:
;; - tibetan-comprehensive-vocabulary (17,777+ entries)
;; - compounds.json (3,000+ compounds)
;; - proper_nouns.json
;; - Particle patterns from tibetan-particles-bialek.el
;;
;; Usage:
;;   (tibetan-ocr-validate-text "བདག་གི་སེམས།")
;;   → Returns validation result plist

;;; Code:

(require 'cl-lib)
(require 'json)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-ocr-validate nil
  "Tibetan OCR validation settings."
  :group 'tibetan-doc-prep
  :prefix "tibetan-ocr-validate-")

(defcustom tibetan-ocr-validate-data-dir
  (expand-file-name "data" (file-name-directory
                            (directory-file-name
                             (file-name-directory (or load-file-name buffer-file-name)))))
  "Directory containing validation data files."
  :type 'directory
  :group 'tibetan-ocr-validate)

;; ============================================================================
;; DATA STRUCTURES
;; ============================================================================

(defvar tibetan-ocr-validate--compounds nil
  "Hash table of compound words from compounds.json.")

(defvar tibetan-ocr-validate--proper-nouns nil
  "Hash table of proper nouns from proper_nouns.json.")

(defvar tibetan-ocr-validate--loaded nil
  "Whether validation data has been loaded.")

;; ============================================================================
;; PARTICLE PATTERNS (from Bialek)
;; ============================================================================

(defconst tibetan-ocr-validate--particles
  '(;; Ergative
    "ཀྱིས" "གྱིས" "གིས" "འིས" "ཡིས" "ས"
    ;; Genitive
    "ཀྱི" "གྱི" "གི" "འི" "ཡི"
    ;; Dative/Allative
    "ལ" "ར" "དུ" "ཏུ" "སུ" "རུ"
    ;; Ablative
    "ནས" "ལས"
    ;; Locative
    "ན"
    ;; Converbs
    "སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང"
    ;; Causal
    "པས" "བས"
    ;; Nominalizers
    "པ" "བ" "པོ" "བོ" "མ" "མོ"
    ;; Concessive
    "ཀྱང" "ཡང" "འང"
    ;; Topic
    "ནི"
    ;; Sentence-final
    "སོ" "ཏོ" "ནོ" "དོ" "རོ" "འོ" "ངོ")
  "List of valid Tibetan particles.")

(defconst tibetan-ocr-validate--particle-regex
  (concat "\\(" (mapconcat #'regexp-quote tibetan-ocr-validate--particles "\\|") "\\)$")
  "Regex matching particle suffixes.")

;; ============================================================================
;; COMMON OCR ERROR PATTERNS
;; ============================================================================

(defconst tibetan-ocr-validate--confusion-pairs
  '(;; Visually similar base letters
    ("ག" . "ད")    ; ga/da
    ("ད" . "ག")
    ("བ" . "པ")    ; ba/pa
    ("པ" . "བ")
    ("ང" . "ཅ")    ; nga/ca
    ("ཅ" . "ང")
    ("ཇ" . "ཉ")    ; ja/nya
    ("ཉ" . "ཇ")
    ("ཐ" . "ཕ")    ; tha/pha
    ("ཕ" . "ཐ")
    ("ཤ" . "ཥ")    ; sha variants
    ("ཥ" . "ཤ")
    ;; Subscript confusions
    ("ྱ" . "ྲ")    ; ya-btags/ra-btags
    ("ྲ" . "ྱ")
    ("ྭ" . "ྲ")    ; wa-zur/ra-btags
    ("ྲ" . "ྭ"))
  "Pairs of commonly confused Tibetan characters in OCR.")

(defconst tibetan-ocr-validate--vowel-marks
  '("ི" "ུ" "ེ" "ོ" "ཱ")
  "Tibetan vowel marks that may be dropped or confused in OCR.")

;; ============================================================================
;; DATA LOADING
;; ============================================================================

(defun tibetan-ocr-validate--load-json (file)
  "Load JSON FILE into hash table."
  (when (file-exists-p file)
    (let ((json-object-type 'hash-table)
          (json-array-type 'list)
          (json-key-type 'string))
      (json-read-file file))))

(defun tibetan-ocr-validate--ensure-loaded ()
  "Ensure validation data is loaded."
  (unless tibetan-ocr-validate--loaded
    ;; Load compounds
    (let ((compounds-file (expand-file-name "dictionaries/compounds.json"
                                            tibetan-ocr-validate-data-dir)))
      (setq tibetan-ocr-validate--compounds
            (or (tibetan-ocr-validate--load-json compounds-file)
                (make-hash-table :test 'equal))))

    ;; Load proper nouns
    (let ((nouns-file (expand-file-name "dictionaries/proper_nouns.json"
                                        tibetan-ocr-validate-data-dir)))
      (setq tibetan-ocr-validate--proper-nouns
            (or (tibetan-ocr-validate--load-json nouns-file)
                (make-hash-table :test 'equal))))

    (setq tibetan-ocr-validate--loaded t)
    (message "Loaded OCR validation data: %d compounds, %d proper nouns"
             (hash-table-count tibetan-ocr-validate--compounds)
             (hash-table-count tibetan-ocr-validate--proper-nouns))))

;; ============================================================================
;; SYLLABLE VALIDATION
;; ============================================================================

(defun tibetan-ocr-validate--strip-particle (word)
  "Strip particle suffix from WORD, return (root . particle) or (word . nil)."
  (if (string-match tibetan-ocr-validate--particle-regex word)
      (let ((particle (match-string 1 word))
            (root (substring word 0 (match-beginning 1))))
        (if (> (length root) 0)
            (cons root particle)
          (cons word nil)))
    (cons word nil)))

(defun tibetan-ocr-validate--check-vocabulary (syllable)
  "Check if SYLLABLE is in comprehensive vocabulary.
Returns source name if found, nil otherwise."
  (when (and (boundp 'tibetan-comprehensive-vocabulary)
             tibetan-comprehensive-vocabulary
             (gethash syllable tibetan-comprehensive-vocabulary))
    "vocabulary"))

(defun tibetan-ocr-validate--check-compounds (syllable)
  "Check if SYLLABLE is part of a compound.
Returns source name if found, nil otherwise."
  (tibetan-ocr-validate--ensure-loaded)
  (when (gethash syllable tibetan-ocr-validate--compounds)
    "compound"))

(defun tibetan-ocr-validate--check-proper-nouns (syllable)
  "Check if SYLLABLE is a proper noun.
Returns source name if found, nil otherwise."
  (tibetan-ocr-validate--ensure-loaded)
  (when (gethash syllable tibetan-ocr-validate--proper-nouns)
    "proper-noun"))

(defun tibetan-ocr-validate--is-particle (syllable)
  "Check if SYLLABLE is a standalone particle."
  (member syllable tibetan-ocr-validate--particles))

(defun tibetan-ocr-validate--valid-syllable-structure-p (syllable)
  "Check if SYLLABLE has valid Tibetan syllable structure.
Basic check for valid character combinations."
  (and (> (length syllable) 0)
       ;; Must contain at least one Tibetan character
       (string-match-p "[ༀ-࿿]" syllable)
       ;; Should not have multiple vowels on same base
       (not (string-match-p "[ཱིེོུ][ཱིེོུ]" syllable))
       ;; Should not start with subscript
       (not (string-match-p "^[ྐ-ྼ]" syllable))))

(defun tibetan-ocr-validate-syllable (syllable)
  "Validate single SYLLABLE against all sources.
Returns plist: (:status valid|unknown|suspicious
                :source \"vocabulary\"|\"compound\"|etc.|nil
                :suggestions (list))"
  (let* ((cleaned (string-trim syllable))
         ;; Remove trailing punctuation for lookup
         (lookup-form (replace-regexp-in-string "[།༎༏་]+$" "" cleaned))
         (root-and-particle (tibetan-ocr-validate--strip-particle lookup-form))
         (root (car root-and-particle))
         (particle (cdr root-and-particle))
         source status suggestions)

    (cond
     ;; Empty or punctuation only
     ((or (string-empty-p lookup-form)
          (string-match-p "^[།༎༏༐༑༔]+$" lookup-form))
      (setq status 'valid source "punctuation"))

     ;; Check as standalone particle
     ((tibetan-ocr-validate--is-particle lookup-form)
      (setq status 'valid source "particle"))

     ;; Check full form in vocabulary
     ((setq source (tibetan-ocr-validate--check-vocabulary lookup-form))
      (setq status 'valid))

     ;; Check root form (with particle stripped)
     ((and particle
           (setq source (tibetan-ocr-validate--check-vocabulary root)))
      (setq status 'valid source (concat source "+particle")))

     ;; Check in compounds
     ((setq source (tibetan-ocr-validate--check-compounds lookup-form))
      (setq status 'valid))

     ;; Check proper nouns
     ((setq source (tibetan-ocr-validate--check-proper-nouns lookup-form))
      (setq status 'valid))

     ;; Check if structurally valid but unknown
     ((tibetan-ocr-validate--valid-syllable-structure-p lookup-form)
      (setq status 'unknown
            suggestions (tibetan-ocr-validate--find-similar lookup-form)))

     ;; Structurally suspicious
     (t
      (setq status 'suspicious
            suggestions (tibetan-ocr-validate--find-similar lookup-form))))

    (list :status status
          :source source
          :syllable cleaned
          :suggestions suggestions)))

;; ============================================================================
;; SIMILARITY / SUGGESTION
;; ============================================================================

(defun tibetan-ocr-validate--edit-distance (s1 s2)
  "Calculate Levenshtein edit distance between S1 and S2."
  (let* ((len1 (length s1))
         (len2 (length s2))
         (matrix (make-vector (1+ len1) nil)))
    ;; Initialize matrix
    (dotimes (i (1+ len1))
      (aset matrix i (make-vector (1+ len2) 0)))
    ;; Fill first row and column
    (dotimes (i (1+ len1))
      (aset (aref matrix i) 0 i))
    (dotimes (j (1+ len2))
      (aset (aref matrix 0) j j))
    ;; Fill rest of matrix
    (dotimes (i len1)
      (dotimes (j len2)
        (let ((cost (if (equal (aref s1 i) (aref s2 j)) 0 1)))
          (aset (aref matrix (1+ i)) (1+ j)
                (min (1+ (aref (aref matrix i) (1+ j)))           ; deletion
                     (1+ (aref (aref matrix (1+ i)) j))           ; insertion
                     (+ cost (aref (aref matrix i) j)))))))       ; substitution
    (aref (aref matrix len1) len2)))

(defun tibetan-ocr-validate--apply-confusion (syllable)
  "Generate variants of SYLLABLE using confusion pairs."
  (let ((variants '()))
    (dolist (pair tibetan-ocr-validate--confusion-pairs)
      (let ((from (car pair))
            (to (cdr pair)))
        (when (string-match-p (regexp-quote from) syllable)
          (push (replace-regexp-in-string (regexp-quote from) to syllable)
                variants))))
    variants))

(defun tibetan-ocr-validate--find-similar (syllable)
  "Find dictionary entries similar to SYLLABLE.
Uses confusion pairs and edit distance."
  (let ((candidates '())
        (max-suggestions 5))

    ;; Try confusion pair variants
    (dolist (variant (tibetan-ocr-validate--apply-confusion syllable))
      (when (tibetan-ocr-validate--check-vocabulary variant)
        (push variant candidates)))

    ;; If we have vocabulary, do edit distance search (limited)
    (when (and (boundp 'tibetan-comprehensive-vocabulary)
               tibetan-comprehensive-vocabulary
               (< (length candidates) max-suggestions))
      (let ((count 0))
        (maphash (lambda (key _value)
                   (when (and (< count 1000)  ; Limit search
                             (< (length candidates) max-suggestions)
                             (<= (abs (- (length key) (length syllable))) 2)
                             (<= (tibetan-ocr-validate--edit-distance key syllable) 2))
                     (push key candidates))
                   (setq count (1+ count)))
                 tibetan-comprehensive-vocabulary)))

    (seq-take (delete-dups candidates) max-suggestions)))

;; ============================================================================
;; MAIN VALIDATION FUNCTION
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-validate-text (text)
  "Validate TEXT against all dictionaries.
Returns plist:
  :total       Total syllables checked
  :valid       List of (syllable . source) for valid syllables
  :unknown     List of unknown syllables (structurally valid)
  :suspicious  List of suspicious syllables (possible OCR errors)
  :details     List of full validation results"
  (tibetan-ocr-validate--ensure-loaded)

  (let* ((normalized (replace-regexp-in-string "[ \t\n]+" "་" text))
         (syllables (split-string normalized "་" t))
         (valid '())
         (unknown '())
         (suspicious '())
         (details '()))

    (dolist (syl syllables)
      (let* ((result (tibetan-ocr-validate-syllable syl))
             (status (plist-get result :status))
             (source (plist-get result :source))
             (cleaned (plist-get result :syllable)))

        (push result details)

        (pcase status
          ('valid (push (cons cleaned source) valid))
          ('unknown (push cleaned unknown))
          ('suspicious (push cleaned suspicious)))))

    (list :total (length syllables)
          :valid (nreverse valid)
          :unknown (nreverse unknown)
          :suspicious (nreverse suspicious)
          :details (nreverse details))))

;; ============================================================================
;; REPORTING
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-validation-report (validation-result)
  "Generate human-readable report from VALIDATION-RESULT."
  (let ((total (plist-get validation-result :total))
        (valid (plist-get validation-result :valid))
        (unknown (plist-get validation-result :unknown))
        (suspicious (plist-get validation-result :suspicious)))

    (concat
     (format "=== OCR Validation Report ===\n\n")
     (format "Total syllables: %d\n" total)
     (format "Valid:      %d (%.1f%%)\n"
             (length valid)
             (if (> total 0) (* 100.0 (/ (float (length valid)) total)) 0))
     (format "Unknown:    %d (%.1f%%)\n"
             (length unknown)
             (if (> total 0) (* 100.0 (/ (float (length unknown)) total)) 0))
     (format "Suspicious: %d (%.1f%%)\n\n"
             (length suspicious)
             (if (> total 0) (* 100.0 (/ (float (length suspicious)) total)) 0))

     (when unknown
       (concat "--- Unknown Syllables ---\n"
               (mapconcat #'identity unknown "\n")
               "\n\n"))

     (when suspicious
       (concat "--- Suspicious Syllables ---\n"
               (mapconcat #'identity suspicious "\n")
               "\n")))))

;; ============================================================================
;; INTERACTIVE COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-ocr-validate-buffer ()
  "Validate current buffer and show report."
  (interactive)
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (result (tibetan-ocr-validate-text text))
         (report (tibetan-ocr-validation-report result)))
    (with-current-buffer (get-buffer-create "*Tibetan OCR Validation*")
      (erase-buffer)
      (insert report)
      (goto-char (point-min)))
    (display-buffer "*Tibetan OCR Validation*")))

;;;###autoload
(defun tibetan-ocr-validate-region (start end)
  "Validate region between START and END."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (result (tibetan-ocr-validate-text text))
         (report (tibetan-ocr-validation-report result)))
    (with-current-buffer (get-buffer-create "*Tibetan OCR Validation*")
      (erase-buffer)
      (insert report)
      (goto-char (point-min)))
    (display-buffer "*Tibetan OCR Validation*")))

;;;###autoload
(defun tibetan-ocr-validate-reload-data ()
  "Reload validation data from files."
  (interactive)
  (setq tibetan-ocr-validate--loaded nil)
  (tibetan-ocr-validate--ensure-loaded)
  (message "Validation data reloaded"))

(provide 'tibetan-ocr-validate)
;;; tibetan-ocr-validate.el ends here
