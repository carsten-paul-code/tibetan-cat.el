;;; cat-display.el --- Analysis display for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Display module for CAT analysis results.
;; Provides formatted output for:
;; - Segment analysis (basic and enhanced)
;; - Lexical units and compounds
;; - Particle and grammar analysis
;; - Verb analysis with argument structure
;; - Translation suggestions
;; - Word-by-word glosses

;;; Code:

(require 'cl-lib)
(require 'cat-utils)
(require 'cat-grammar)
(require 'cat-parser)

;; ============================================================================
;; BUFFER NAMES
;; ============================================================================

(defconst cat-display-segment-buffer "*Segment Info*"
  "Buffer name for basic segment analysis.")

(defconst cat-display-enhanced-buffer "*Segment Info Enhanced*"
  "Buffer name for enhanced segment analysis.")

;; ============================================================================
;; WYLIE CONVERSION
;; ============================================================================

(defun cat-display-get-wylie (text)
  "Get Wylie transliteration for TEXT with error handling."
  (condition-case err
      (if (fboundp 'tibetan-to-wylie-fixed)
          (tibetan-to-wylie-fixed text)
        "[Wylie converter not loaded]")
    (error (format "[Wylie error: %s]" (error-message-string err)))))

;; ============================================================================
;; DHARMAMITRA TRANSLATION
;; ============================================================================

(defun cat-display-get-dharmamitra (text)
  "Get DharmaMitra translation for TEXT with error handling."
  (condition-case nil
      (when (fboundp 'dharmamitra-text-get-translation)
        (let ((trans (dharmamitra-text-get-translation text)))
          (when (and trans
                     (not (string-empty-p trans))
                     (not (string= trans "null")))
            (string-trim trans))))
    (error nil)))

;; ============================================================================
;; WORKING TRANSLATION GENERATION
;; ============================================================================

(defun cat-display-generate-translation (parse-result &optional verbs)
  "Generate working translation from PARSE-RESULT and optional VERBS."
  (let* ((segments (cat-parse-result-segments parse-result))
         (multiword-units (cat-parse-result-multiword-units parse-result))
         (content-words '())
         ;; Particles to skip in translation
         (skip-particles '("ནི" "ཡང" "གི" "ཀྱི" "འི" "ཡི" "གྱི"
                          "ལ" "ན" "དུ" "སུ" "ར" "ས" "ནས" "ལས" "དང")))

    ;; Collect content word meanings
    (dolist (seg segments)
      (let ((meaning (cat-parser-lookup-segment seg parse-result)))
        (when (and meaning
                   (not (string-empty-p meaning))
                   (not (member seg skip-particles)))
          ;; Clean up - take first meaning
          (when (string-match "^\\([^,;]+\\)" meaning)
            (setq meaning (string-trim (match-string 1 meaning))))
          (push meaning content-words))))
    (setq content-words (nreverse content-words))

    ;; Build translation
    (let ((trans-text (string-join content-words " ")))
      ;; Add verb meaning if available
      (when (and verbs (car verbs))
        (let* ((main-verb (car verbs))
               (verb-meaning (when (and (listp main-verb) (consp (car main-verb)))
                              (car (split-string (or (alist-get 'meaning main-verb) "") "," t)))))
          (when (and verb-meaning
                     (not (cl-some (lambda (w) (string-match-p (regexp-quote verb-meaning) w))
                                   content-words)))
            (setq trans-text (concat trans-text " " verb-meaning)))))

      ;; Capitalize first letter if ASCII
      (when (and (> (length trans-text) 0)
                 (string-match "^[a-z]" trans-text))
        (setq trans-text (concat (upcase (substring trans-text 0 1))
                                (substring trans-text 1))))

      (if (> (length trans-text) 0)
          trans-text
        nil))))

;; ============================================================================
;; VERB DISPLAY
;; ============================================================================

(defun cat-display-insert-verb (verb)
  "Insert formatted display for single VERB entry."
  (when (and verb (listp verb) (consp (car verb)))
    (let* ((lemma (alist-get 'lemma verb))
           (present (or (alist-get 'present_stem verb) "—"))
           (past (or (alist-get 'past_stem verb) "—"))
           (future (or (alist-get 'future_stem verb) "—"))
           (imperative (or (alist-get 'imperative_stem verb) "—"))
           (vol (or (alist-get 'volitionality verb) "?"))
           (trans (or (alist-get 'transitivity verb) "?"))
           (frame (or (alist-get 'case_frame verb) "?"))
           (class (or (alist-get 'indigenous_class verb) "?"))
           (meaning (alist-get 'meaning verb))
           ;; Map volitionality to controllability
           (controllable (cond
                         ((string= vol "Voluntary") "Controllable")
                         ((string= vol "Involuntary") "Uncontrollable")
                         ((string= vol "Both") "Context-dependent")
                         (t "?"))))
      (insert (format "%s" lemma))
      (when meaning (insert (format " - %s" meaning)))
      (insert "\n")
      (insert (format "STEMS: %s / %s / %s / %s\n" present past future imperative))
      (insert (format "VOLITIONALITY: %s\n" vol))
      (insert (format "CONTROLLABILITY: %s (Schwieger/Bialek)\n" controllable))
      (insert (format "TRANSITIVITY: %s\n" trans))
      (insert (format "ARGUMENT FRAME: %s\n" frame))
      (insert (format "TIBETAN CLASS: %s\n"
                     (cond
                      ((string= class "tha_dad_pa") "ཐ་དད་པ་ (tha dad pa - transitive)")
                      ((string= class "tha_mi_dad_pa") "ཐ་མི་དད་པ་ (tha mi dad pa - intransitive)")
                      (t "—"))))
      (insert "\n"))))

(defun cat-display-insert-verbs (verbs)
  "Insert formatted verb analysis for VERBS list."
  (when verbs
    (cat-insert-header "Verb Analysis (Hill 2010)")
    (dolist (verb verbs)
      (cat-display-insert-verb verb))
    (cat-insert-separator)
    (insert "\n")))

;; ============================================================================
;; LEXICAL UNITS DISPLAY
;; ============================================================================

(defun cat-display-insert-lexical-units (multiword-units)
  "Insert formatted display for MULTIWORD-UNITS."
  (when multiword-units
    (cat-insert-header "Lexical Units")
    (dolist (unit multiword-units)
      (let* ((form (nth 2 unit))
             (data (nth 3 unit))
             (wylie-val (alist-get 'wylie data))
             (english (alist-get 'english data))
             (sanskrit (alist-get 'sanskrit data))
             (category (alist-get 'category data))
             (wylie-display (or wylie-val
                               (cat-display-get-wylie form)
                               "?")))
        (insert (format "%s [%s]\n" form wylie-display))
        (let ((cat-display (if category
                              (capitalize (replace-regexp-in-string "_" " " category))
                            "Vocabulary")))
          (insert (format "TYPE: %s\n" cat-display)))
        (insert (format "MEANING: %s\n" (or english "?")))
        (when sanskrit
          (insert (format "SANSKRIT: %s\n" sanskrit)))
        (insert "\n")))
    (cat-insert-separator)
    (insert "\n")))

;; ============================================================================
;; PARTICLE DISPLAY (Enhanced)
;; ============================================================================

(defun cat-display-insert-particles-enhanced (words claimed-indices multiword-units)
  "Insert enhanced particle analysis.
WORDS is syllable list, CLAIMED-INDICES are compound indices,
MULTIWORD-UNITS are recognized compounds."
  (cat-insert-header "Particles & Case Markers")
  (let ((particles-found nil)
        (seen-particles (make-hash-table :test 'equal)))

    ;; PASS 1: Check each FREE syllable for particles
    (cl-loop for idx from 0 below (length words)
             unless (gethash idx claimed-indices)
             do (let* ((word (nth idx words))
                      (detections (cat-grammar-detect-all-in-word word)))
                 (dolist (detection detections)
                   (let* ((type (nth 0 detection))
                          (particle (nth 1 detection))
                          (root (nth 2 detection))
                          (key (concat word "-" (symbol-name type))))
                     (unless (gethash key seen-particles)
                       (puthash key t seen-particles)
                       (setq particles-found t)
                       (insert (format "%s (after %s)\n" particle root))
                       (insert (format "TYPE: %s\n" (cat-grammar-get-type-name type)))
                       (insert (format "FUNCTION: %s\n"
                                      (plist-get (cdr (assq type cat-grammar-particle-info))
                                                :function)))
                       (insert (format "REFERENCE: %s\n\n"
                                      (plist-get (cdr (assq type cat-grammar-particle-info))
                                                :reference))))))
                 ;; Check for standalone particles
                 (when (and (member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
                           (not (gethash word seen-particles)))
                   (puthash word t seen-particles)
                   (setq particles-found t)
                   (when-let ((p (cat-grammar-detect-standalone-particle word)))
                     (insert (format "%s\n" word))
                     (insert (format "TYPE: %s\n" (cat-grammar-get-type-name (cat-particle-type p))))
                     (insert (format "FUNCTION: %s\n" (cat-particle-function p)))
                     (insert "\n")))))

    ;; PASS 2: Check lexical units for embedded particles
    (dolist (unit multiword-units)
      (let* ((form (nth 2 unit))
             (syllables (split-string form "་" t)))
        ;; Check if compound ends with a case particle
        (when (and (> (length syllables) 1)
                  (member (car (last syllables)) '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང")))
          (let* ((particle (car (last syllables)))
                 (base-syllables (butlast syllables))
                 (base (string-join base-syllables "་")))
            (unless (gethash (concat form "-embedded") seen-particles)
              (puthash (concat form "-embedded") t seen-particles)
              (setq particles-found t)
              (insert (format "%s (after %s in compound %s)\n" particle base form))
              (insert "TYPE: Case particle (in lexical unit)\n")
              (insert (format "FUNCTION: %s\n"
                             (cat-parser-particle-function particle)))
              (insert "\n"))))
        ;; Check syllables for genitive particles
        (dolist (syl syllables)
          (when (string-match "\\(.+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\|གྱི\\)$" syl)
            (let ((base-in-syl (match-string 1 syl))
                  (particle (match-string 2 syl))
                  (key (concat form "-" syl "-gen")))
              (unless (gethash key seen-particles)
                (puthash key t seen-particles)
                (setq particles-found t)
                (insert (format "%s (after %s in compound %s)\n" particle base-in-syl form))
                (insert "TYPE: Genitive (GEN) (in lexical unit)\n")
                (insert "FUNCTION: Marks possessor or modifier\n")
                (insert "REFERENCE: Bialek: Genitive for possession/modification\n\n")))))))

    (unless particles-found
      (insert "  [No particles detected in this segment]\n\n"))
    (cat-insert-separator)
    (insert "\n")))

;; ============================================================================
;; WORD-BY-WORD GLOSS
;; ============================================================================

(defun cat-display-insert-gloss (parse-result)
  "Insert word-by-word gloss from PARSE-RESULT."
  (cat-insert-header "Word-by-Word Gloss")
  (let ((segments (cat-parse-result-segments parse-result)))
    (dolist (seg segments)
      (let ((meaning (cat-parser-lookup-segment seg parse-result)))
        (insert (format "%s = %s\n" seg (or meaning "[look up]"))))))
  (insert "\n")
  (cat-insert-separator)
  (insert "\n"))

;; ============================================================================
;; MAIN DISPLAY FUNCTIONS
;; ============================================================================

(defun cat-display-insert-absolutives (absolutives)
  "Insert formatted absolutive analysis for ABSOLUTIVES list."
  (when absolutives
    (cat-insert-header "Absolutive Arguments (Zero Marking)")
    (dolist (abs absolutives)
      (let ((word (cat-absolutive-word abs))
            (role (cat-absolutive-role abs))
            (verb (cat-absolutive-verb abs))
            (verb-info (cat-absolutive-verb-info abs))
            (confidence (cat-absolutive-confidence abs)))
        (insert (format "%s\n" word))
        (insert (format "  CASE: ABSOLUTIVE (ABS) - zero marker\n"))
        (insert (format "  ROLE: %s\n" (cat-grammar-absolutive-role-name role)))
        (when verb
          (insert (format "  VERB: %s (%s, %s)\n"
                          verb
                          (or (plist-get verb-info :transitivity) "?")
                          (or (plist-get verb-info :volitionality) "?"))))
        (insert (format "  CONFIDENCE: %s\n\n" confidence))))
    (cat-insert-separator)
    (insert "\n")))

(defun cat-display-enhanced-analysis (seg-id tibetan-text)
  "Display enhanced analysis for segment SEG-ID with TIBETAN-TEXT."
  (let* ((buffer (cat-get-or-create-buffer cat-display-enhanced-buffer))
         ;; Parse
         (parse-result (cat-parser-parse tibetan-text))
         (words (cat-parse-result-words parse-result))
         (multiword-units (cat-parse-result-multiword-units parse-result))
         (claimed-indices (cat-parse-result-claimed-indices parse-result))
         (segments (cat-parse-result-segments parse-result))
         ;; Wylie
         (wylie (cat-display-get-wylie tibetan-text))
         ;; Verbs
         (verbs (cat-parser-extract-verbs parse-result))
         ;; Absolutives (zero-marked arguments)
         (absolutives (cat-grammar-detect-absolutives words))
         ;; Translations
         (working-trans (cat-display-generate-translation parse-result verbs))
         (dm-trans (cat-display-get-dharmamitra tibetan-text)))

    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)

        ;; Header
        (cat-insert-box-header "SEGMENT ANALYSIS - ENHANCED")
        (insert (format "Segment: %s\n\n" seg-id))

        ;; Tibetan text
        (cat-insert-header "Tibetan Text")
        (insert tibetan-text)
        (insert "\n\n")

        ;; Wylie
        (cat-insert-header "Wylie")
        (insert wylie)
        (insert "\n\n")

        ;; Segmentation
        (cat-insert-header "Segmentation")
        (insert (string-join segments " | "))
        (insert "\n")
        (cat-insert-separator)
        (insert "\n")

        ;; Lexical units
        (cat-display-insert-lexical-units multiword-units)

        ;; Particles (overt case markers)
        (cat-display-insert-particles-enhanced words claimed-indices multiword-units)

        ;; Absolutives (zero-marked arguments)
        (cat-display-insert-absolutives absolutives)

        ;; Verbs
        (cat-display-insert-verbs verbs)

        ;; Working translation
        (cat-insert-header "Working Translation")
        (if working-trans
            (insert (format "\"%s\"\n" working-trans))
          (insert "[Could not generate translation - check vocabulary]\n"))
        (insert "\n")
        (cat-insert-separator)
        (insert "\n")

        ;; DharmaMitra
        (cat-insert-header "DharmaMitra Translation")
        (insert (or dm-trans "[Not available]"))
        (insert "\n\n")
        (cat-insert-separator)
        (insert "\n")

        ;; Word-by-word gloss
        (cat-display-insert-gloss parse-result)

        (insert "\n[Press q to close]\n")

        (goto-char (point-min))
        (view-mode 1)))

    ;; Display buffer
    (cat-display-in-side-window buffer)
    (message "Segment %s - Enhanced analysis on right" seg-id)))

(defun cat-display-basic-analysis (seg-id tibetan-text)
  "Display basic analysis for segment SEG-ID with TIBETAN-TEXT."
  (let* ((buffer (cat-get-or-create-buffer cat-display-segment-buffer))
         (wylie (cat-display-get-wylie tibetan-text))
         (particles (cat-grammar-analyze-text tibetan-text))
         (dm-trans (cat-display-get-dharmamitra tibetan-text)))

    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)

        ;; Header
        (cat-insert-box-header "SEGMENT ANALYSIS")
        (insert (format "Segment: %s\n\n" seg-id))

        ;; Tibetan text
        (cat-insert-header "Tibetan Text")
        (insert tibetan-text)
        (insert "\n\n")

        ;; Wylie
        (cat-insert-header "Wylie")
        (insert wylie)
        (insert "\n\n")

        ;; Particles
        (cat-insert-header "Particles & Grammar")
        (insert (cat-grammar-format-analysis particles))
        (cat-insert-separator)
        (insert "\n")

        ;; Translation
        (cat-insert-header "DharmaMitra Translation")
        (insert (or dm-trans "[Not available]"))
        (insert "\n\n")

        (insert "[Press q to close]\n")

        (goto-char (point-min))
        (view-mode 1)))

    (cat-display-in-side-window buffer)
    (message "Segment %s - Analysis on right" seg-id)))

(provide 'cat-display)
;;; cat-display.el ends here
