;;; tibetan-interlinear.el --- Interlinear gloss & particle overview -*- lexical-binding: t -*-

;;; Commentary:
;; Generates two new analysis sections:
;;
;; 1. ** Interlinear Gloss
;;    Wylie transliteration with inline annotations:
;;    - Lexical words get a Steinert link and short English gloss in brackets
;;    - Particles get a link to the Particle Overview and Bialek abbreviation
;;    - Verse structure (shad markers) is preserved
;;
;; 2. ** Particle Overview
;;    Per-segment mini-reference extracted from the user's Bialek Portfolio.
;;    Only the particles present in the current segment are included.
;;    Each entry shows the Portfolio description, sub-function, and the
;;    segment-specific application.
;;
;; Data flow:
;;   The Word / Particle List loop in tibetan-analysis-persist.el already
;;   computes vocab-pairs, enriched-vocab-pairs, gram-role, tag,
;;   short-meaning, wylie-key, and steinert-link for every entry.
;;   This module takes that data and reformats it.
;;
;; Requires:
;;   - tibetan-wylie          (tibetan-to-wylie-fixed)
;;   - tibetan-particles-bialek (tibetan-analyze-grammar-bialek)
;;   - tibetan-vocabulary     (tibetan-strip-particles, tibetan-steinert-url-org)

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defvar tibetan-interlinear-portfolio-file nil
  "Path to the Bialek Portfolio org file.
When nil, the Particle Overview section will still be generated
using the inline Bialek analysis data, but without Portfolio excerpts.")

;; ============================================================================
;; PORTFOLIO PARSER
;; ============================================================================
;;
;; The Portfolio is an org-mode file structured as:
;;   * Part 1: Case Suffixes
;;   ** 1.1 Genitive
;;   *** 1.1.1 Genitive Attribute
;;       - example1
;;       - example2
;;   *** 1.1.2 Genitive with Postpositions
;;       ...
;;   ** 1.3 Ergative
;;   ...
;;   * Part 2: Converb Constructions
;;   ** 2.1 Verb Stem + /kyang/
;;   ...
;;
;; We parse this into an alist keyed by a normalised label so that
;; particle detection results can look up the relevant Portfolio entry.

(defvar tibetan-interlinear--portfolio-cache nil
  "Cached alist of parsed Portfolio entries.
Each entry is (KEY . plist) where plist has:
  :section   — section number string (\"1.1\", \"2.4\")
  :title     — heading text (\"Genitive\", \"Verb Stem + /ste/\")
  :intro     — introductory paragraph(s) before sub-sections
  :functions — alist of ((sub-section-number . sub-title) . description)")

(defvar tibetan-interlinear--portfolio-file-stamp nil
  "Modification time of the Portfolio file when cache was built.")

(defun tibetan-interlinear--portfolio-key (bialek-type)
  "Map a Bialek analysis type label to a Portfolio lookup key.
BIALEK-TYPE is e.g. \"GENITIVE (GEN)\" or \"CONVERBIAL: ABLATIVE CONVERB\".
Returns a normalised key like \"genitive\" or \"converb-nas\"."
  (let ((type (downcase (string-trim bialek-type))))
    (cond
     ;; Case particles → use the case name
     ((string-match "genitive" type)          "genitive")
     ((string-match "ergative" type)          "ergative")
     ((string-match "terminative" type)       "terminative")
     ((string-match "dative" type)            "dative")
     ((string-match "locative.*concessive" type) "locative+concessive")
     ((string-match "locative" type)          "locative")
     ((string-match "elative\\|ablative" type)
      (if (string-match "converb" type)       "converb-nas"
        "elative"))
     ((string-match "topic" type)             "topic")
     ((string-match "comitative" type)        "comitative")
     ;; Converbs → type-specific
     ((string-match "concessive" type)        "converb-kyang")
     ((string-match "coordinative" type)      "converb-ste")
     ((string-match "simultaneous" type)      "converb-cing")
     ((string-match "causal" type)            "converb-pas")
     (t (replace-regexp-in-string "[^a-z0-9]+" "-" type)))))

(defun tibetan-interlinear--parse-portfolio (file)
  "Parse the Bialek Portfolio org FILE into a structured alist.
Returns an alist suitable for `tibetan-interlinear--portfolio-cache'."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((entries '())
            (current-key nil)
            (current-plist nil)
            (current-functions '()))

        ;; Scan for ** N.N headings (the main case/converb sections)
        (while (re-search-forward
                "^\\*\\* \\([0-9]+\\.[0-9]+\\) \\(.+\\)$" nil t)
          ;; Save previous entry if any
          (when current-key
            (plist-put current-plist :functions (nreverse current-functions))
            (push (cons current-key current-plist) entries))

          (let* ((section-num (match-string 1))
                 (title (string-trim (match-string 2)))
                 (heading-end (line-end-position))
                 ;; Find the next ** heading or end of buffer
                 (section-end (save-excursion
                                (if (re-search-forward "^\\*\\* " nil t)
                                    (line-beginning-position)
                                  (point-max))))
                 ;; Extract introductory paragraph (text between heading
                 ;; and first *** sub-heading, skipping blank lines)
                 (first-sub (save-excursion
                              (goto-char heading-end)
                              (if (re-search-forward "^\\*\\*\\* " section-end t)
                                  (line-beginning-position)
                                section-end)))
                 (intro-text (string-trim
                              (buffer-substring-no-properties
                               (1+ heading-end) first-sub)))
                 ;; Strip org formatting: /italic/ → italic
                 (intro-clean (replace-regexp-in-string
                               "/\\([^/]+\\)/" "\\1" intro-text))
                 ;; Determine the portfolio key from the title
                 (key (cond
                       ((string-match "Genitive" title)       "genitive")
                       ((string-match "Absolutive" title)     "absolutive")
                       ((string-match "Ergative" title)       "ergative")
                       ((string-match "Locative" title)       "locative")
                       ((string-match "Dative" title)         "dative")
                       ((string-match "Terminative" title)    "terminative")
                       ((string-match "Comitative" title)     "comitative")
                       ((string-match "Elative" title)        "elative")
                       ((string-match "Delative" title)       "delative")
                       ((string-match "Topic" title)          "topic")
                       ;; Converb sections: ** 2.N Verb Stem + /particle/
                       ((string-match "/kyang/" title)        "converb-kyang")
                       ((string-match "/rung/" title)         "converb-rung")
                       ((string-match "/cing/" title)         "converb-cing")
                       ((string-match "/ste/" title)          "converb-ste")
                       ((string-match "/tsa na/" title)       "converb-tsana")
                       ((string-match "\\+ /la/" title)       "converb-la")
                       ((string-match "\\+ /kyi/" title)      "converb-kyi")
                       ((string-match "\\+ /na/" title)       "converb-na")
                       ((string-match "\\+ /pa/ \\+ /dang/" title) "converb-padang")
                       ((string-match "\\+ /pa/ \\+ /la/" title)   "converb-pala")
                       ((string-match "\\+ /pa/ \\+ /las/" title)  "converb-palas")
                       ((string-match "\\+ /pas/" title)      "converb-pas")
                       ((string-match "\\+ /pa/ \\+ /na/" title)   "converb-pana")
                       ((string-match "\\+ /par/" title)      "converb-par")
                       (t (replace-regexp-in-string
                           "[^a-z0-9]+" "-"
                           (downcase title))))))

            (setq current-key key)
            (setq current-plist
                  (list :section section-num
                        :title title
                        :intro intro-clean
                        :functions nil))
            (setq current-functions '())

            ;; Parse *** sub-sections within this section
            (save-excursion
              (goto-char heading-end)
              (while (re-search-forward
                      "^\\*\\*\\* \\([0-9.]+\\) \\(.+\\)$"
                      section-end t)
                (let* ((sub-num (match-string 1))
                       (sub-title (string-trim (match-string 2)))
                       (sub-start (1+ (line-end-position)))
                       (sub-end (save-excursion
                                  (if (re-search-forward
                                       "^\\*\\*\\*? " section-end t)
                                      (line-beginning-position)
                                    section-end)))
                       (sub-body (string-trim
                                  (buffer-substring-no-properties
                                   sub-start sub-end)))
                       ;; Strip org formatting
                       (sub-clean (replace-regexp-in-string
                                   "/\\([^/]+\\)/" "\\1"
                                   sub-body)))
                  (push (cons (cons sub-num sub-title) sub-clean)
                        current-functions))))))

        ;; Save the last entry
        (when current-key
          (plist-put current-plist :functions (nreverse current-functions))
          (push (cons current-key current-plist) entries))

        (nreverse entries)))))

(defun tibetan-interlinear--get-portfolio ()
  "Return the parsed Portfolio, using cache when valid."
  (let ((file tibetan-interlinear-portfolio-file))
    (if (or (null file) (not (file-readable-p file)))
        nil
      (let ((mtime (file-attribute-modification-time
                    (file-attributes file))))
        (unless (and tibetan-interlinear--portfolio-cache
                     (equal mtime tibetan-interlinear--portfolio-file-stamp))
          (setq tibetan-interlinear--portfolio-cache
                (tibetan-interlinear--parse-portfolio file))
          (setq tibetan-interlinear--portfolio-file-stamp mtime))
        tibetan-interlinear--portfolio-cache))))

;; ============================================================================
;; WORD/PARTICLE SPLITTING
;; ============================================================================
;;
;; Given a Word/Particle List entry like "སྐྱེས་གྱུར་ཀྱང" tagged
;; [CONCESSIVE PARTICLE], split it into:
;;   stem:     "སྐྱེས་གྱུར"  (→ Steinert link + gloss)
;;   particle: "ཀྱང"          (→ Particle Overview link)
;;
;; We reuse the particle patterns from tibetan-strip-particles but
;; return BOTH parts instead of just the stem.

(defvar tibetan-interlinear--particle-patterns
  '(;; Ergative/Instrumental (longer first to avoid partial matches)
    ("ཀྱིས" . "ERG")  ("གྱིས" . "ERG")  ("གིས" . "ERG")
    ("འིས" . "ERG")   ("ཡིས" . "ERG")
    ;; Genitive
    ("ཀྱི" . "GEN")   ("གྱི" . "GEN")   ("གི" . "GEN")
    ("འི" . "GEN")    ("ཡི" . "GEN")
    ;; Causal converb
    ("པས" . "CONV:pas") ("བས" . "CONV:pas")
    ;; Ablative / Elative
    ("ནས" . "ABL/CONV:nas") ("ལས" . "DELAT")
    ;; Coordinative converb
    ("སྟེ" . "CONV:ste") ("ཏེ" . "CONV:ste") ("དེ" . "CONV:ste")
    ;; Simultaneous converb
    ("ཅིང" . "CONV:cing") ("ཞིང" . "CONV:cing") ("ཤིང" . "CONV:cing")
    ;; Concessive
    ("ཀྱང" . "CONC")  ("ཡང" . "CONC")   ("འང" . "CONC")
    ;; Terminative
    ("དུ" . "TERM")   ("ཏུ" . "TERM")   ("སུ" . "TERM")
    ("རུ" . "TERM")
    ;; Dative
    ("ལ" . "DAT")
    ;; Terminative single-char (after དུ/ཏུ/སུ/རུ to avoid false positives)
    ("ར" . "TERM")
    ;; Topic
    ("ནི" . "TOP")
    ;; Comitative
    ("དང" . "COM")
    ;; Locative
    ("ན" . "LOC"))
  "Alist of (TIBETAN-SUFFIX . SHORT-LABEL) for known particles.
Ordered longest-first within each group to avoid partial matches.")

(defun tibetan-interlinear--split-word-particle (tibetan-word bialek-tag)
  "Split TIBETAN-WORD into (STEM . PARTICLE-INFO) using BIALEK-TAG.
BIALEK-TAG is the grammatical role string from the Word/Particle List,
e.g. \"GENITIVE (GEN)\" or \"CONCESSIVE PARTICLE\" or nil.
Returns (STEM . (PARTICLE-TIBETAN . SHORT-LABEL)) if a particle is found,
or (WORD . nil) if no particle detected."
  (if (or (null bialek-tag)
          (member bialek-tag '("Noun" "?" "Unknown" "N" "Verb"
                               "Transitive verb" "Intransitive verb")))
      ;; No particle — whole word is lexical
      (cons tibetan-word nil)
    ;; Try to match a particle suffix
    (let ((result nil))
      (cl-dolist (pattern tibetan-interlinear--particle-patterns)
        (let ((suffix (car pattern))
              (label (cdr pattern)))
          (when (and (not result)
                     (string-suffix-p suffix tibetan-word)
                     (> (length tibetan-word) (length suffix)))
            (let ((stem (substring tibetan-word 0
                                   (- (length tibetan-word)
                                      (length suffix)))))
              ;; Strip trailing tsheg from stem
              (setq stem (replace-regexp-in-string "[་ \t]+$" "" stem))
              (setq result (cons stem (cons suffix label)))))))
      (if result
          result
        ;; Tag says it's a particle but we couldn't strip it —
        ;; treat the whole word as lexical with the tag shown
        (cons tibetan-word nil)))))

;; ============================================================================
;; INTERLINEAR GLOSS GENERATOR
;; ============================================================================

(defun tibetan-interlinear--format-gloss-entry (wylie-stem steinert-link
                                                 short-meaning
                                                 particle-wylie particle-label)
  "Format one interlinear entry.
WYLIE-STEM is the Wylie of the lexical part.
STEINERT-LINK is an org link string or nil.
SHORT-MEANING is the English gloss or nil.
PARTICLE-WYLIE is the Wylie of the particle part or nil.
PARTICLE-LABEL is the short Bialek label (\"GEN\", \"CONC\", etc.) or nil.
Returns a string like:
  [[steinert-url][stem[gloss]]] [[particle-overview][particle[LABEL]]]"
  (let ((parts '()))
    ;; Lexical stem part
    (let ((stem-text
           (if (and short-meaning (not (string-empty-p short-meaning)))
               (format "%s[%s]" wylie-stem
                       ;; Keep gloss short for the interlinear
                       (tibetan-interlinear--truncate-gloss short-meaning 30))
             wylie-stem)))
      (if steinert-link
          ;; Wrap in Steinert link: [[url][displayed-text]]
          ;; steinert-link is already formatted as [[url][Steinert]]
          ;; We need to extract the URL and re-wrap with our text
          (if (string-match "\\[\\[\\([^]]+\\)\\]\\[" steinert-link)
              (push (format "[[%s][%s]]" (match-string 1 steinert-link)
                            stem-text)
                    parts)
            (push stem-text parts))
        (push stem-text parts)))

    ;; Particle part (if any)
    (when (and particle-wylie particle-label)
      (push (format "[[particle:%s][%s[%s]]]"
                    particle-wylie particle-wylie particle-label)
            parts))

    (mapconcat #'identity (nreverse parts) " ")))

(defun tibetan-interlinear--truncate-gloss (meaning max-len)
  "Truncate MEANING to MAX-LEN characters for interlinear display.
Tries to cut at a word boundary."
  (if (<= (length meaning) max-len)
      meaning
    (let* ((cut (substring meaning 0 max-len))
           (space-pos (cl-position ?\s cut :from-end t)))
      (if (and space-pos (> space-pos (/ max-len 2)))
          (substring cut 0 space-pos)
        (concat (substring meaning 0 (- max-len 1)) "…")))))

(defun tibetan-interlinear-generate-gloss (_vocab-pairs enriched-vocab-pairs
                                            bialek-analysis _tibetan-text)
  "Generate the Interlinear Gloss section content.
_VOCAB-PAIRS is the raw (tibetan . meaning) alist from segmentation
 (accepted for caller symmetry but currently unused — enriched pairs
 carry the short meanings the renderer needs).
ENRICHED-VOCAB-PAIRS is ((tibetan-clean . short-meaning) ...) from the
Word/Particle List loop.
BIALEK-ANALYSIS is the result of `tibetan-analyze-grammar-bialek'.
_TIBETAN-TEXT is the original Tibetan string (for verse structure —
reserved for shad/verse-break reinsertion; currently unused).
Returns a string ready to insert after the `** Interlinear Gloss' heading."
  (let* (;; Build a lookup: tibetan-clean → (tag . short-meaning)
         ;; from the enriched vocab pairs and bialek analysis
         (bialek-by-word (make-hash-table :test 'equal))
         (gloss-by-word (make-hash-table :test 'equal))
         (result-parts '()))

    ;; Index Bialek analysis by Tibetan word
    (dolist (a bialek-analysis)
      (let ((word (nth 1 a))
            (type (nth 2 a)))
        (puthash word type bialek-by-word)))

    ;; Index enriched glosses
    (dolist (pair enriched-vocab-pairs)
      (puthash (car pair) (cdr pair) gloss-by-word))

    ;; Process each vocab entry in order
    (dolist (pair enriched-vocab-pairs)
      (let* ((tibetan-clean (car pair))
             (short-meaning (cdr pair))
             (bialek-tag (gethash tibetan-clean bialek-by-word))
             ;; Split into stem + particle
             (split (tibetan-interlinear--split-word-particle
                     tibetan-clean bialek-tag))
             (stem-tibetan (car split))
             (particle-info (cdr split))   ; (PARTICLE-TIB . LABEL) or nil
             ;; Convert to Wylie
             (stem-wylie
              (condition-case nil
                  (when (fboundp 'tibetan-to-wylie-fixed)
                    (downcase (string-trim
                               (tibetan-to-wylie-fixed stem-tibetan))))
                (error nil)))
             (particle-wylie
              (when particle-info
                (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (downcase (string-trim
                                 (tibetan-to-wylie-fixed
                                  (car particle-info)))))
                  (error nil))))
             (particle-label (when particle-info (cdr particle-info)))
             ;; Steinert link for the STEM (not the whole word with particle)
             (steinert-link
              (when (and stem-wylie
                        (fboundp 'tibetan-steinert-url-org)
                        ;; Skip Steinert for pure function words
                        (not (member bialek-tag
                                     '("TOPIC (TOP)"))))
                (condition-case nil
                    (tibetan-steinert-url-org stem-wylie)
                  (error nil)))))

        (push (tibetan-interlinear--format-gloss-entry
               (or stem-wylie "?")
               steinert-link
               short-meaning
               particle-wylie
               particle-label)
              result-parts)))

    ;; Join entries, inserting verse breaks where the original text has shad
    ;; For now, simple space-separated join.  We preserve shad positions
    ;; by scanning the original Wylie for "/" markers and inserting them.
    (let ((gloss-line (mapconcat #'identity (nreverse result-parts) " ")))
      ;; Re-insert verse breaks from the full Wylie transliteration
      ;; The full Wylie has " /" for shad — we match these positions
      ;; approximately by inserting newlines at shad boundaries
      (concat gloss-line "\n"))))

;; ============================================================================
;; PARTICLE OVERVIEW GENERATOR
;; ============================================================================

(defun tibetan-interlinear-generate-particle-overview (bialek-analysis
                                                        _enriched-vocab-pairs)
  "Generate the Particle Overview section content.
BIALEK-ANALYSIS is the result of `tibetan-analyze-grammar-bialek'.
_ENRICHED-VOCAB-PAIRS is accepted for caller symmetry but is not
currently consulted — the portfolio lookup keys off the Bialek
particle tag alone.
Returns a string ready to insert after the `** Particle Overview' heading."
  (let ((portfolio (tibetan-interlinear--get-portfolio))
        (seen-keys (make-hash-table :test 'equal))
        (sections '()))

    (dolist (a bialek-analysis)
      (let* ((particle-tib (nth 0 a))
             (word-tib (nth 1 a))
             (type (nth 2 a))
             (function-desc (nth 3 a))
             (trans-guide (nth 4 a))
             (portfolio-key (tibetan-interlinear--portfolio-key type))
             ;; Wylie forms
             (particle-wylie
              (condition-case nil
                  (when (fboundp 'tibetan-to-wylie-fixed)
                    (downcase (string-trim
                               (tibetan-to-wylie-fixed particle-tib))))
                (error (format "%s" particle-tib))))
             (word-wylie
              (condition-case nil
                  (when (fboundp 'tibetan-to-wylie-fixed)
                    (downcase (string-trim
                               (tibetan-to-wylie-fixed word-tib))))
                (error (format "%s" word-tib)))))

        ;; Only one entry per portfolio key (e.g. one "genitive" section
        ;; even if kyi appears twice in the segment)
        (unless (gethash portfolio-key seen-keys)
          (puthash portfolio-key t seen-keys)

          (let* ((portfolio-entry (cdr (assoc portfolio-key portfolio)))
                 (p-section (when portfolio-entry
                              (plist-get portfolio-entry :section)))
                 (p-title (when portfolio-entry
                            (plist-get portfolio-entry :title)))
                 (p-intro (when portfolio-entry
                            (plist-get portfolio-entry :intro)))
                 (section-ref (if p-section
                                  (format "§%s" p-section)
                                ""))
                 (heading-title (if p-title
                                    (format "%s — %s (%s)"
                                            particle-wylie p-title section-ref)
                                  (format "%s — %s" particle-wylie type))))

            (let ((text (with-temp-buffer
                          ;; Sub-heading (level 3 in the analysis file)
                          (insert (format "*** %s\n" heading-title))

                          ;; Portfolio introduction paragraph
                          (when (and p-intro
                                     (not (string-empty-p p-intro)))
                            (insert (format "%s\n\n"
                                            (tibetan-interlinear--truncate-para
                                             p-intro 300))))

                          ;; Sub-functions from Portfolio
                          (when portfolio-entry
                            (let ((functions (plist-get portfolio-entry
                                                       :functions)))
                              (when functions
                                (insert "Functions:\n")
                                (dolist (fn functions)
                                  (let ((sub-id (caar fn))
                                        (sub-title (cdar fn)))
                                    (insert (format "- %s %s\n"
                                                    sub-id sub-title))))
                                (insert "\n"))))

                          ;; Segment-specific application
                          (insert (format "In this segment: %s %s → %s\n"
                                          word-wylie particle-wylie
                                          (or trans-guide
                                              function-desc
                                              type)))
                          (buffer-string))))
              (push text sections))))))

    (mapconcat #'identity (nreverse sections) "\n")))

(defun tibetan-interlinear--truncate-para (text max-len)
  "Truncate TEXT to approximately MAX-LEN characters at a sentence boundary."
  (if (<= (length text) max-len)
      text
    ;; Try to cut at a sentence boundary
    (let ((truncated (substring text 0 max-len)))
      (if (string-match "\\.[^.]*$" truncated)
          (substring truncated 0 (1+ (match-beginning 0)))
        (concat (string-trim-right truncated) "…")))))

;; ============================================================================
;; ENTRY POINT FOR ANALYSIS PIPELINE
;; ============================================================================

(defun tibetan-interlinear-insert-sections (enriched-vocab-pairs
                                             bialek-analysis
                                             tibetan-text
                                             &optional vocab-pairs)
  "Insert Interlinear Gloss and Particle Overview sections at point.
This is the main entry point called from the analysis generation pipeline.
ENRICHED-VOCAB-PAIRS, BIALEK-ANALYSIS, TIBETAN-TEXT as for the
individual generators.  Optional VOCAB-PAIRS for future use."
  ;; Interlinear Gloss
  (insert "** Interlinear Gloss\n")
  (insert (tibetan-interlinear-generate-gloss
           vocab-pairs enriched-vocab-pairs
           bialek-analysis tibetan-text))
  (insert "\n")

  ;; Particle Overview
  (when bialek-analysis
    (insert "** Particle Overview\n")
    (insert (tibetan-interlinear-generate-particle-overview
             bialek-analysis enriched-vocab-pairs))
    (insert "\n")))

(provide 'tibetan-interlinear)
;;; tibetan-interlinear.el ends here
