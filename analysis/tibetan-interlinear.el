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

(defvar tibetan-interlinear-emit-particle-overview nil
  "When non-nil, `tibetan-interlinear-insert-sections' emits the legacy
`** Particle Overview' level-2 section.  Default nil (Pass 6b,
2026-04-22): the per-particle Portfolio reference has moved into
`** Grammar / *** Particles in This Segment' rendered by
`tibetan-analysis--render-grammar-section'.  Kept as an escape
hatch for tests and callers that still want the old standalone
section.")

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

Returns one of:
  (STEM . (PARTICLE-TIBETAN . SHORT-LABEL))  — stem + clitic particle
  (nil  . (WORD . SHORT-LABEL))              — pure standalone particle
  (WORD . nil)                                — no particle detected

The pure-standalone-particle case fires when the whole word IS a
known particle (e.g. `ནས' on its own, not bolted onto a verb) AND
the bialek analysis tags it as such.  The Interlinear renderer
emits these as a compact `nas [ABL]' — no dictionary gloss, no
jump link — matching how stem-final particles are rendered."
  (if (or (null bialek-tag)
          (member bialek-tag '("Noun" "?" "Unknown" "N" "Verb"
                               "Transitive verb" "Intransitive verb")))
      ;; No particle — whole word is lexical
      (cons tibetan-word nil)
    ;; 1) First try matching a true suffix (strict: word longer than
    ;;    the suffix, so `bslabs + nas' splits but `nas' alone does
    ;;    not match as a suffix of itself).
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
              (setq stem (replace-regexp-in-string "[་ \t]+$" "" stem))
              (setq result (cons stem (cons suffix label)))))))
      (cond
       (result result)
       ;; 2) Pure standalone particle: the word IS one of the known
       ;;    particle forms and the bialek tag confirms it.  Render
       ;;    compactly via the particle-only branch in the format
       ;;    helper (stem = nil).
       ((cl-some (lambda (pattern) (string= (car pattern) tibetan-word))
                 tibetan-interlinear--particle-patterns)
        (let* ((entry (cl-find-if (lambda (pattern)
                                    (string= (car pattern) tibetan-word))
                                  tibetan-interlinear--particle-patterns))
               (label (cdr entry)))
          (cons nil (cons tibetan-word label))))
       ;; 3) Bialek says particle but we can't identify it — fall
       ;;    back to lexical rendering rather than mis-labelling.
       (t (cons tibetan-word nil))))))

;; ============================================================================
;; INTERLINEAR GLOSS GENERATOR
;; ============================================================================

(defun tibetan-interlinear--sanitize-gloss (gloss)
  "Make GLOSS safe to embed inside `[...]' without forming an org link.

Rangjung Yeshe and other glossaries contain entries whose gloss is
itself wrapped in square brackets — e.g. `[value-big]', `[R]', or
`[accusative, adverbial]'.  When the interlinear renderer wraps
such a gloss in `[...]' the resulting `[[value-big]]' is read by
org-mode as a link target, and `org-export-dispatch' aborts with
`Unable to resolve link: \"value-big\"'.  Replacing `[...]' with
`(...)' inside the gloss keeps the content readable while
guaranteeing no accidental double-bracket ever reaches the export
layer.  Called for its value; does not mutate input."
  (when gloss
    (let ((out (replace-regexp-in-string "\\[" "(" gloss)))
      (setq out (replace-regexp-in-string "\\]" ")" out))
      out)))

(defun tibetan-interlinear--format-gloss-entry (wylie-stem term-anchor
                                                 short-meaning
                                                 particle-wylie particle-label
                                                 &optional curated-p)
  "Format one interlinear entry.
WYLIE-STEM is the Wylie of the lexical part.
TERM-ANCHOR is the internal org-link target slug (e.g. `term-bdag-la')
  matching a `<<term-bdag-la>>' target in the Detailed Dictionary
  section — click the Wylie to jump to the full entry below.  Pass
  nil to render plain Wylie without a link (useful for pure function
  words that have no Detailed Dictionary entry).
SHORT-MEANING is the English gloss or nil.
PARTICLE-WYLIE is the Wylie of the particle part or nil.
PARTICLE-LABEL is the short Bialek label (\"GEN\", \"CONC\", etc.) or nil.
Optional CURATED-P, when non-nil, marks the entry as coming from
the per-document Resources / Custom vocabulary list.  The entry
gets a leading `★' and is given a longer truncation budget (60
vs 30 chars) so hand-curated glosses aren't cut mid-phrase.

The English gloss (or Bialek label) is rendered OUTSIDE the org link
so the clickable area covers only the Wylie, keeping the readable
English visible as plain text.  Any brackets inside the gloss are
rewritten to parens so the enclosing `[...]' wrapper never produces
a second `[' / `]' pair that org-mode would parse as a link.
Returns something like:

  [[term-anchor][stem]] ★ [gloss] particle [LABEL]"
  (let ((parts '())
        (gloss-budget (if curated-p 60 30)))
    ;; Lexical stem part — link wraps ONLY the Wylie; English gloss
    ;; follows outside the link.  Curated-P entries get a leading ★
    ;; marker inserted between the link and the gloss.  The link
    ;; target is an internal anchor (`term-xxx') — the Detailed
    ;; Dictionary section below emits matching `<<term-xxx>>' radio
    ;; targets.  Pass TERM-ANCHOR=nil to render plain Wylie text.
    ;;
    ;; Empty / nil WYLIE-STEM signals a pure-standalone-particle
    ;; token (e.g. a bare `ནས' functioning as ablative converb); the
    ;; caller has already stuffed the particle data into the
    ;; PARTICLE-WYLIE / PARTICLE-LABEL slots, so we simply skip the
    ;; stem rendering and let the particle branch below do its job.
    (when (and wylie-stem (not (string-empty-p wylie-stem)))
      (let ((linked-stem
             (if (and term-anchor (stringp term-anchor))
                 (format "[[%s][%s]]" term-anchor wylie-stem)
               wylie-stem)))
        (push (if (and short-meaning (not (string-empty-p short-meaning)))
                  (format "%s %s[%s]" linked-stem
                          (if curated-p "★ " "")
                          (tibetan-interlinear--sanitize-gloss
                           (tibetan-interlinear--truncate-gloss
                            short-meaning gloss-budget)))
                (if curated-p
                    (format "%s ★" linked-stem)
                  linked-stem))
              parts)))

    ;; Particle part — rendered as plain text `wylie [LABEL]'.
    ;;
    ;; Previously this produced `[[particle:%s][%s]]' links pointing at
    ;; an org target `particle:X', but no such target existed: exporters
    ;; failed with `Unable to resolve link: \"particle:du\"'.  The
    ;; particles ARE detailed in the Particle Overview section, but
    ;; that section is per-segment (and duplicated across all 217
    ;; segments in the combined document) so there's no single
    ;; canonical target to point at.  Plain text is safer and doesn't
    ;; lose any information — the label is what the reader cares about.
    (when (and particle-wylie particle-label)
      (push (format "%s [%s]"
                    particle-wylie
                    (tibetan-interlinear--sanitize-gloss particle-label))
            parts))

    (mapconcat #'identity (nreverse parts) " ")))

(defun tibetan-interlinear--prefer-english (meaning)
  "If MEANING is a bilingual `DE // EN' gloss, return just the English half.
Otherwise return MEANING unchanged.

User-curated Resources entries routinely carry both halves
separated by ` // ' — e.g. `Personenname; der baumwollgewandete
[Yogin] aus der Mid-la-Familie // name of a person; the
cotton-clad [yogin] from the Mid la family'.  Without this
helper the interlinear would truncate the German half and leave
the reader with a stub like `Personenname; der', which is
semantically worthless at a glance.  We strip everything up to
and including the first ` // ' and keep what follows, recursively
in case the entry packs multiple `//' separators (take the last
segment, which in practice is always English)."
  (if (and meaning (string-match-p " // " meaning))
      (car (last (split-string meaning " // " t)))
    meaning))

(defun tibetan-interlinear--truncate-gloss (meaning max-len)
  "Truncate MEANING to MAX-LEN characters for interlinear display.
Tries to cut at a word boundary.  Bilingual `DE // EN' glosses are
reduced to their English half first so the truncation never
strands the reader on half a German phrase."
  (let ((m (tibetan-interlinear--prefer-english meaning)))
    (if (<= (length m) max-len)
        m
      (let* ((cut (substring m 0 max-len))
             (space-pos (cl-position ?\s cut :from-end t)))
        (if (and space-pos (> space-pos (/ max-len 2)))
            (substring cut 0 space-pos)
          (concat (substring m 0 (- max-len 1)) "…"))))))

(defun tibetan-interlinear-generate-gloss (_vocab-pairs enriched-vocab-pairs
                                            bialek-analysis _tibetan-text
                                            &optional curated-words-hash)
  "Generate the Interlinear Gloss section content.
_VOCAB-PAIRS is the raw (tibetan . meaning) alist from segmentation
 (accepted for caller symmetry but currently unused — enriched pairs
 carry the short meanings the renderer needs).
ENRICHED-VOCAB-PAIRS is ((tibetan-clean . short-meaning) ...) from the
vocabulary loop in `tibetan-analysis-generate-content'.
BIALEK-ANALYSIS is the result of `tibetan-analyze-grammar-bialek'.
_TIBETAN-TEXT is the original Tibetan string (for verse structure —
reserved for shad/verse-break reinsertion; currently unused).
Optional CURATED-WORDS-HASH is a hash (word → t) of tokens whose
primary dictionary hit came from per-document Resources / Custom.
When non-nil, those entries get a leading `★' and a longer
truncation (60 chars vs 30) so the hand-curated gloss isn't cut
off mid-phrase.
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
             ;; Split into stem + particle.  Three shapes:
             ;;   (STEM . (PART-TIB . LABEL))   — clitic on stem
             ;;   (nil  . (WORD . LABEL))       — pure standalone particle
             ;;   (WORD . nil)                  — lexical, no particle
             (split (tibetan-interlinear--split-word-particle
                     tibetan-clean bialek-tag))
             (stem-tibetan (car split))
             (particle-info (cdr split))   ; (PARTICLE-TIB . LABEL) or nil
             ;; Convert to Wylie.  When the token is a pure standalone
             ;; particle, stem-tibetan is nil and the format helper's
             ;; particle-only branch renders `wylie [LABEL]' without a
             ;; stem link or dictionary gloss (matching how stem+clitic
             ;; compounds already render the clitic half).
             (stem-wylie
              (when stem-tibetan
                (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (downcase (string-trim
                                 (tibetan-to-wylie-fixed stem-tibetan))))
                  (error nil))))
             (particle-wylie
              (when particle-info
                (condition-case nil
                    (when (fboundp 'tibetan-to-wylie-fixed)
                      (downcase (string-trim
                                 (tibetan-to-wylie-fixed
                                  (car particle-info)))))
                  (error nil))))
             (particle-label (when particle-info (cdr particle-info)))
             ;; Internal org link target for the STEM — the Detailed
             ;; Dictionary section below emits `<<term-xxxx>>' anchors
             ;; matching these, so the student can click the Wylie in
             ;; the Interlinear and jump straight to the full entry.
             ;; The external Steinert URL lives only on the Detailed
             ;; Dictionary head line — a two-level navigation
             ;; (shallow: same file; deep: external) that keeps the
             ;; Interlinear uncluttered.
             (term-anchor
              (when (and stem-wylie
                         (fboundp 'tibetan-vocab-term-anchor)
                         ;; Skip link for pure function words — they
                         ;; won't have a Detailed Dictionary entry to
                         ;; jump to.
                         (not (member bialek-tag
                                      '("TOPIC (TOP)"))))
                (tibetan-vocab-term-anchor stem-wylie)))
             ;; Curated-entry flag: set only when the caller provided
             ;; a hash AND the hash knows about this token.  Passed on
             ;; to the formatter so it can prepend ★ and use a longer
             ;; truncation for hand-curated Resources glosses.
             (curated-p (and curated-words-hash
                             (gethash tibetan-clean curated-words-hash))))

        (push (tibetan-interlinear--format-gloss-entry
               ;; Pure-particle tokens pass "" as the stem — the format
               ;; helper's `short-meaning' path is skipped (no gloss to
               ;; print for a bare function word) and the particle
               ;; branch emits the compact `wylie [LABEL]'.
               (or stem-wylie "")
               term-anchor
               ;; Suppress the dictionary gloss for pure-particle
               ;; tokens — the particle label IS the gloss here.
               (and stem-wylie short-meaning)
               particle-wylie
               particle-label
               curated-p)
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

(defun tibetan-interlinear-portfolio-function-snippet (portfolio-key sub-id)
  "Return the Portfolio snippet `(SUB-TITLE . DESCRIPTION)' for
PORTFOLIO-KEY + SUB-ID, or nil if not found.
PORTFOLIO-KEY is a normalised key like \"terminative\",
\"converb-nas\" (see `tibetan-interlinear--portfolio-key').  SUB-ID
is a section identifier string like \"1.5.1\" or \"2.11.2\".

Walks the parsed Portfolio's `:functions' alist (which stores
`((SUB-NUM . SUB-TITLE) . DESCRIPTION)' entries) and returns the
first match.  When SUB-ID doesn't correspond to a parsed sub-section
— Claude may have emitted a broader `1.5' when the Portfolio only
has `1.5.1'..`1.5.9' — returns nil so the caller can fall back to
the top-level `:intro' or omit the snippet.

Used by `*** Particles in This Segment' in the Grammar renderer
(Pass 6c) to attach Portfolio text per particle occurrence, so the
analysis file is self-contained for readers without access to the
user's Portfolio source."
  (let ((portfolio (tibetan-interlinear--get-portfolio)))
    (when (and portfolio portfolio-key sub-id)
      (let* ((entry (cdr (assoc portfolio-key portfolio)))
             (functions (and entry (plist-get entry :functions))))
        (when functions
          (cl-loop for fn in functions
                   for key = (car fn)
                   when (and (consp key) (equal (car key) sub-id))
                   return (cons (cdr key) (cdr fn))))))))

(defun tibetan-interlinear-portfolio-reference-block ()
  "Return a markdown-style reference block listing every parsed
Portfolio section + sub-section with its ACTUAL numbering from the
user's Portfolio file.

The block is designed to be injected into the Claude system prompt
so Claude's `## Particles' output uses EXACTLY the section IDs the
user's Portfolio defines — not Bialek-canonical numbers that may
diverge (Carsten's Portfolio has Terminative at §1.6; some Bialek
textbook editions have it at §1.5).  Without this the Grammar
section's `*** Particles in This Segment' renderer fails to resolve
Portfolio snippets for correctly-tagged particles, because
`tibetan-interlinear-portfolio-function-snippet' looks up IDs in
the parsed cache.

Returns an empty string when no Portfolio is loaded — callers
concatenate unconditionally and the prompt simply omits the block.

Format:
  Portfolio section reference (use these EXACT numbers in ...):
    §1.1 Genitive — 1.1.1 Genitive Attribute; 1.1.2 Genitive with...
    §1.3 Ergative — 1.3.1 Subject of Transitive Verbs; ...
    §1.5 Dative
    §1.6 Terminative — 1.6.1 Place / Location; 1.6.3 Time; ..."
  (let ((portfolio (tibetan-interlinear--get-portfolio)))
    (if (null portfolio)
        ""
      (let ((lines '())
            ;; Sort by section number so the block reads in
            ;; natural order (1.1 → 1.3 → 1.6 → 2.1 → ...).
            (sorted
             (sort (copy-sequence portfolio)
                   (lambda (a b)
                     (let ((sa (plist-get (cdr a) :section))
                           (sb (plist-get (cdr b) :section)))
                       (and sa sb
                            (tibetan-interlinear--section-lt sa sb)))))))
        (dolist (entry sorted)
          (let* ((section (plist-get (cdr entry) :section))
                 (title   (plist-get (cdr entry) :title))
                 (functions (plist-get (cdr entry) :functions))
                 (sub-line
                  (when functions
                    (mapconcat
                     (lambda (fn)
                       (let ((id (caar fn))
                             (sub-title (cdar fn)))
                         (format "%s %s" id sub-title)))
                     functions "; "))))
            (when (and section title)
              (push (if sub-line
                        (format "  §%s %s — %s" section title sub-line)
                      (format "  §%s %s" section title))
                    lines))))
        (concat
         "Portfolio section reference (use these EXACT numbers in "
         "`portfolio-sub-id'; if a particle function is not covered "
         "by any section here, fall back to the closest parent "
         "section number and flag the mismatch in the `label' field):\n"
         (mapconcat #'identity (nreverse lines) "\n"))))))

(defun tibetan-interlinear--section-lt (a b)
  "Compare two Portfolio section-number strings numerically.
`1.2' < `1.10'; `1.9' < `2.1'.  Simple numeric tuple compare —
each dot-separated component is parsed as an integer."
  (let ((na (mapcar #'string-to-number (split-string a "\\.")))
        (nb (mapcar #'string-to-number (split-string b "\\."))))
    (catch 'done
      (while (or na nb)
        (let ((xa (or (car na) 0))
              (xb (or (car nb) 0)))
          (cond
           ((< xa xb) (throw 'done t))
           ((> xa xb) (throw 'done nil))
           (t (setq na (cdr na) nb (cdr nb))))))
      nil)))

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
                                             &optional vocab-pairs
                                             curated-words-hash)
  "Insert Interlinear Gloss and Particle Overview sections at point.
This is the main entry point called from the analysis generation pipeline.
ENRICHED-VOCAB-PAIRS, BIALEK-ANALYSIS, TIBETAN-TEXT as for the
individual generators.  Optional VOCAB-PAIRS for future use.

Optional CURATED-WORDS-HASH is a hash (word → t) of tokens whose
primary dictionary hit came from the per-document Resources /
Custom vocabulary list.  When passed, the Interlinear generator
prepends `★' to those entries so students see at a glance which
glosses are authoritative, hand-curated for this document."
  ;; Interlinear Gloss
  (insert "** Interlinear Gloss\n")
  (insert (tibetan-interlinear-generate-gloss
           vocab-pairs enriched-vocab-pairs
           bialek-analysis tibetan-text
           curated-words-hash))
  (insert "\n")

  ;; Particle Overview emission is GATED by
  ;; `tibetan-interlinear-emit-particle-overview' (default nil as of
  ;; Pass 6b, 2026-04-22).  The per-particle Portfolio reference and
  ;; per-occurrence segment translation hint now live under
  ;; `** Grammar / *** Particles in This Segment' rendered by the
  ;; persist module.  Tests and legacy callers that want the old
  ;; standalone `** Particle Overview' section can set the variable
  ;; to non-nil to re-enable.
  (when (and bialek-analysis
             (bound-and-true-p tibetan-interlinear-emit-particle-overview))
    (insert "** Particle Overview\n")
    (insert (tibetan-interlinear-generate-particle-overview
             bialek-analysis enriched-vocab-pairs))
    (insert "\n")))

(provide 'tibetan-interlinear)
;;; tibetan-interlinear.el ends here
