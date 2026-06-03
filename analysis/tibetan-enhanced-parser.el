;;; tibetan-enhanced-parser.el --- Enhanced Tibetan parser with compound/proper noun recognition -*- lexical-binding: t -*-

;;; Commentary:
;; Improved parsing that:
;; 1. Segments text into tsheg-delimited units FIRST
;; 2. Checks compound/proper noun dictionaries BEFORE analysis
;; 3. Only analyzes particles at word boundaries (not inside syllables)
;; 4. Filters verb matches by context
;;
;; This addresses false positives like:
;; - Finding ན inside གཞན (gzhan = "other")
;; - Matching verb stems that aren't verbs in context
;; - Missing multi-word units like གླེང་གཞི (nidāna)

;;; Code:

(require 'json)
(require 'cl-lib)

;; Soft-require tibetan-vocabulary for comprehensive glossaries
(require 'tibetan-vocabulary nil t)

;; ============================================================================
;; EXTERNAL VARIABLES
;; ============================================================================

(defvar tibetan-cat-data-dir nil
  "Base directory for Tibetan CAT data files.")

;; Populated by `tibetan-glossary-loader' when the bundled glossaries
;; are loaded.  Declared here so the byte-compiler recognises it.
(defvar tibetan-comprehensive-vocabulary)

;; ============================================================================
;; DICTIONARY LOADING
;; ============================================================================

(defvar tibetan-compounds-dict nil
  "Hash table of Tibetan compound terms.
Key: Tibetan text, Value: alist with wylie, english, sanskrit, category.")

(defvar tibetan-proper-nouns-dict nil
  "Hash table of Tibetan proper nouns.
Key: Tibetan text, Value: alist with wylie, english, sanskrit, category.")

(defun tibetan-load-json-dict (filename)
  "Load JSON dictionary from FILENAME, return as hash table."
  (let ((file-path (expand-file-name filename tibetan-cat-data-dir)))
    (when (file-exists-p file-path)
      (let* ((json-object-type 'alist)
             (json-array-type 'list)
             (json-key-type 'string)  ; Use strings for Tibetan keys
             (json-data (json-read-file file-path))
             (hash (make-hash-table :test 'equal)))
        (dolist (entry json-data)
          (let ((key (car entry))
                (value (cdr entry)))
            ;; Ensure key is a string (convert from symbol if needed)
            (puthash (if (symbolp key) (symbol-name key) key)
                     value hash)))
        hash))))

(defun tibetan-load-dictionaries ()
  "Load compound and proper noun dictionaries from JSON files.
Creates empty hash tables if files don't exist or tibetan-cat-data-dir is unset."
  (unless tibetan-compounds-dict
    (let ((loaded (and (boundp 'tibetan-cat-data-dir)
                       tibetan-cat-data-dir
                       (tibetan-load-json-dict "data/dictionaries/compounds.json"))))
      (setq tibetan-compounds-dict (or loaded (make-hash-table :test 'equal)))
      (when loaded
        (message "✓ Loaded %d compound terms" (hash-table-count tibetan-compounds-dict)))))

  (unless tibetan-proper-nouns-dict
    (let ((loaded (and (boundp 'tibetan-cat-data-dir)
                       tibetan-cat-data-dir
                       (tibetan-load-json-dict "data/dictionaries/proper_nouns.json"))))
      (setq tibetan-proper-nouns-dict (or loaded (make-hash-table :test 'equal)))
      (when loaded
        (message "✓ Loaded %d proper nouns" (hash-table-count tibetan-proper-nouns-dict))))))

;; Load on require
(tibetan-load-dictionaries)

;; ============================================================================
;; MULTI-WORD SEGMENTATION
;; ============================================================================

(defun tibetan-segment-text (text)
  "Segment TEXT into tsheg-delimited units.
Returns list of word strings."
  (let ((cleaned (replace-regexp-in-string "[།༎༏༐༑༔]" "" text)))
    (split-string cleaned "་" t)))

(defconst tibetan-enhanced-parser--case-particle-tails
  '("ར" "ལ" "ན" "ས" "སུ" "ཏུ" "དུ" "རུ" "ནས" "ལས" "དང"
    "གི" "གྱི" "ཀྱི" "ཡི" "ནི" "འི" "པར" "བར"
    "ཀྱིས" "གིས" "གྱིས" "ཡིས" "ས" "སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང"
    "པས" "བས")
  "Syllables that mark a case/converb particle when they are the tail
of a candidate multiword unit.  Used to reject Steinert MWU hits
whose last syllable is itself a particle — those are phrasal idioms
like `ཞིག་ཏུ' (\"as a...\") rather than lexicalised compounds.
Nominaliser tails (`པ', `བ', `མ', …) are deliberately omitted: forms
like `བསྐལ་པ' (kalpa) are legitimate lexical compounds.")

(defun tibetan-enhanced-parser--case-particle-tail-p (joined)
  "Return non-nil if JOINED (a `་'-joined string) ends in a case/converb
particle listed in `tibetan-enhanced-parser--case-particle-tails'."
  (let ((parts (split-string joined "་" t)))
    (and parts
         (member (car (last parts))
                 tibetan-enhanced-parser--case-particle-tails))))

(defun tibetan-enhanced-parser--negation-plus-hill-verb-p (joined)
  "Return non-nil when JOINED is `མ-V' or `མི-V' with V a Hill-DB verb.

Live test on gotrapatala.org seg-008 (`སྤྱོད་དང་རབ་གནས་ཐ་མ་
ཡིན་༎') showed the MWU finder bundling `མ་ཡིན' as a Steinert
2-syllable MWU, hiding the copula `ཡིན' from verb extraction.
The verb extractor's `prev-word-negates-p' mechanism already
handles `མ' / `མི' + verb correctly when they are SEPARATE
words; bundling them as an MWU only causes harm.

This predicate is consumed by the MWU finder's steinert-hit
branch — when it returns non-nil for a candidate JOINED, the
2-syllable Steinert hit is rejected so the MWU finder falls
through to length-1 and the verb extractor sees `མ' / `མི'
and the verb as separate words.

Returns nil for:
  - non-2-syllable forms (`མ་ཡིན་པ' falls outside)
  - heads other than `མ' / `མི' (`ཐ་མ' has tail `མ' but head
    is `ཐ', not negation)
  - tails not present in the Hill-DB verb table — closed-set
    minor verbs (`མཛད', `གསོལ', `བྱུང', …) are intentionally
    out of scope, so user-facing genuine `མ-V' / `མི-V'
    Steinert idioms involving honorific or aspectual verbs
    keep their MWU bundling.

Defensive: returns nil when Hill-DB lookup is unavailable
\(`tibetan-verb-lookup' not fbound) — the predicate becomes a
no-op rather than raising."
  (when (and joined (stringp joined) (not (string-empty-p joined))
             (fboundp 'tibetan-verb-lookup))
    (let ((parts (split-string joined "་" t)))
      (and parts
           (= (length parts) 2)
           (or (string= (nth 0 parts) "མ")
               (string= (nth 0 parts) "མི"))
           (tibetan-verb-lookup (nth 1 parts))
           t))))

(defun tibetan-enhanced-parser--verb-tail-p (joined)
  "Return non-nil if the LAST tsheg-syllable of JOINED is a Hill-DB verb.

Used by the MWU finder to stop a multi-syllable (≥3) unit from absorbing
a finite verb — e.g. `དྲུང་དུ་ཕྱིན' (a Rangjung-Yeshe phrasal entry)
bundling the past verb `ཕྱིན' (\"went\").  The verb belongs to clause /
sentence-structure analysis, not the noun phrase, so the candidate is
rejected and the finder falls through to a shorter length, leaving the
verb a separate word.  Defensive no-op when `tibetan-verb-lookup' is
unavailable."
  (when (and joined (stringp joined)
             (fboundp 'tibetan-verb-lookup))
    (let* ((parts (split-string joined "་" t))
           (tail (car (last parts))))
      (and tail (>= (length parts) 2)
           (tibetan-verb-lookup tail)
           t))))

(defun tibetan-find-multiword-units (words)
  "Find multi-word compound/proper noun units in WORDS list.
Uses longest-match-first strategy.
Returns list of (start-index . end-index . entry-data) tuples."
  ;; Ensure dictionaries are loaded
  (tibetan-load-dictionaries)
  ;; Also ensure the canonical bundled glossaries are in place — the
  ;; MWU loop below relies on `tibetan-comprehensive-vocabulary' being
  ;; populated.  `load-all-glossaries' is idempotent so calling it when
  ;; the hash is already primed is cheap.
  (when (and (fboundp 'load-all-glossaries)
             (or (not (boundp 'tibetan-comprehensive-vocabulary))
                 (not tibetan-comprehensive-vocabulary)
                 (= (hash-table-count tibetan-comprehensive-vocabulary) 0)))
    (load-all-glossaries))
  ;; Per-document Resources / Custom vocabulary — load now so the MWU
  ;; loop below (which checks `tibetan-current-resources-vocab' and
  ;; `tibetan-current-custom-vocab') sees the user's hand-written
  ;; entries.  Without this the user's `ཆུང་མ་བྱེད' / `ཀློག་སློབ' MWUs
  ;; never reach the parser's `multiword-units' output, and downstream
  ;; MWU-aware verb / NP / negation logic has nothing to consult.
  (when (fboundp 'tibetan-load-resources-vocab)
    (ignore-errors (tibetan-load-resources-vocab)))
  (when (fboundp 'tibetan-load-custom-vocab)
    (ignore-errors (tibetan-load-custom-vocab)))
  (let ((matches '())
        (i 0))
    (while (< i (length words))
      (let ((found nil)
            (max-len (min 8 (- (length words) i))))  ; Check up to 8-word compounds
        ;; Try longest matches first
        (cl-loop for len from max-len downto 1
                 until found
                 do
                 (let* ((slice (cl-subseq words i (+ i len)))
                        (joined (string-join slice "་"))
                        ;; Per-document Resources / Custom vocab — the
                        ;; user's hand-written multiword entries
                        ;; (`ཆུང་མ་བྱེད', `ཀློག་སློབ').  Highest priority;
                        ;; consulted for width > 1 only.
                        (resources-vocab
                         (when (and (boundp 'tibetan-current-resources-vocab)
                                    tibetan-current-resources-vocab
                                    (> len 1))
                           (gethash joined tibetan-current-resources-vocab)))
                        (custom-vocab
                         (when (and (boundp 'tibetan-current-custom-vocab)
                                    tibetan-current-custom-vocab
                                    (> len 1))
                           (gethash joined tibetan-current-custom-vocab)))
                        ;; Comprehensive vocabulary (bundled).
                        (comp-vocab (when (boundp 'tibetan-comprehensive-vocabulary)
                                     (gethash joined tibetan-comprehensive-vocabulary)))
                        ;; JSON compound/proper-noun dictionaries.
                        (compound (when tibetan-compounds-dict
                                   (gethash joined tibetan-compounds-dict)))
                        (proper-noun (when tibetan-proper-nouns-dict
                                      (gethash joined tibetan-proper-nouns-dict)))
                        ;; Steinert fallback — the user's two-syllable
                        ;; compounds (`ནམ་ཞིག', `ཀློག་སློབ', `ངོ་མཚར',
                        ;; `བསྐལ་པ') often live only here, not in
                        ;; comprehensive-vocab or Resources.
                        ;; `tibetan-extract-vocabulary' (the
                        ;; Word/Particle List code path) already picks
                        ;; them up via `tibetan-lookup-word'; per the
                        ;; DRY rule, we need to see the same inventory
                        ;; so `multiword-units' stays in sync.
                        ;;
                        ;; Width == 2 only.  RangjungYeshe and IvesWaldo
                        ;; include many multi-syllable idiomatic entries
                        ;; (`ངོ་མཚར་དུ་གྱུར' = "marveled",
                        ;; `བཅོམ་ལྡན་འདས་ཀྱིས་བཀའ་སྩལ་པ' = "the
                        ;; Bhagavan replied") whose constituents are
                        ;; still independent content words that the
                        ;; verb / clause analysers need to see.
                        ;; Capping at 2 keeps legitimate lexical
                        ;; compounds while excluding phrasal idioms.
                        ;;
                        ;; Shadow check: when a Steinert 2-syllable hit
                        ;; at position i would cover the first syllable
                        ;; of a BETTER 2-syllable hit at position i+1
                        ;; (e.g. `དུས་བསྐལ' shadowing the canonical
                        ;; `བསྐལ་པ' at position 1 in `དུས་བསྐལ་པ་གྲངས'),
                        ;; we reject the position-i match so the outer
                        ;; loop falls through to len=1 and the shifted
                        ;; MWU gets picked up on the next iteration.
                        (steinert-hit
                         (when (and (= len 2)
                                    (not (or resources-vocab custom-vocab
                                             comp-vocab compound proper-noun))
                                    (not (tibetan-enhanced-parser--case-particle-tail-p
                                          joined))
                                    ;; Reject `མ-V' / `མི-V' when V is a
                                    ;; Hill-DB-attested verb — the verb
                                    ;; extractor's `prev-word-negates-p'
                                    ;; handles the negation pattern when
                                    ;; the two are separate words, and
                                    ;; bundling them only hides the verb
                                    ;; from extraction.  Live test:
                                    ;; gotrapatala seg-008 `མ་ཡིན'
                                    ;; absorbing `ཡིན' (Hill-DB copula).
                                    (not (tibetan-enhanced-parser--negation-plus-hill-verb-p
                                          joined))
                                    (fboundp 'tibetan-lookup-word-in-steinert))
                           (ignore-errors
                             (let ((hit (tibetan-lookup-word-in-steinert
                                         joined)))
                               (when hit
                                 (let* ((shift-end (+ i 3))
                                        (shifted
                                         (when (<= shift-end (length words))
                                           (string-join
                                            (cl-subseq words (1+ i) shift-end)
                                            "་")))
                                        (shadow
                                         (and shifted
                                              (not (tibetan-enhanced-parser--case-particle-tail-p
                                                    shifted))
                                              ;; A `མ-V' / `མི-V' shifted
                                              ;; candidate (V in Hill-DB)
                                              ;; is rejected by the
                                              ;; primary-hit branch's
                                              ;; `--negation-plus-hill-
                                              ;; verb-p' guard, so it
                                              ;; must NOT shadow the
                                              ;; position-i candidate
                                              ;; either — otherwise we'd
                                              ;; defer to a candidate we
                                              ;; were already going to
                                              ;; reject, leaving NO MWU
                                              ;; at either position.
                                              ;; (uddāna seg-008
                                              ;; `…ཐ་མ་ཡིན…': `ཐ་མ'
                                              ;; was shadowed by `མ་ཡིན'
                                              ;; while `མ་ཡིན' itself
                                              ;; was rejected.)
                                              (not (tibetan-enhanced-parser--negation-plus-hill-verb-p
                                                    shifted))
                                              (tibetan-lookup-word-in-steinert
                                               shifted))))
                                   (unless shadow hit))))))))
                   (when (or resources-vocab custom-vocab
                             comp-vocab compound proper-noun steinert-hit)
                     ;; Upgrade rule: a 2-syllable Steinert MWU followed
                     ;; by a single-char case particle may extend to a
                     ;; 3-syllable MWU when the 3-syllable form is ALSO
                     ;; in Steinert *and* sourced from a curated
                     ;; dictionary (Hopkins / JimValby / IvesWaldo) —
                     ;; the 3-syllable form is then a lexicalised
                     ;; locative/terminative compound (e.g. `ཕ་རོལ' +
                     ;; `ན' → `ཕ་རོལ་ན' = "on the other side, beyond").
                     ;; Rangjung Yeshe 3-syllable entries ending in a
                     ;; particle (e.g. `འབའ་ཞིག་ཏུ' = "exclusively")
                     ;; are phrasal: they shouldn't swallow the 2-syll
                     ;; compound.  The source tag appears in the gloss
                     ;; string as `[NN-SourceName]'.
                     (let* ((effective-len len)
                            (effective-joined joined)
                            (effective-hit steinert-hit))
                       (when (and steinert-hit
                                  (= len 2)
                                  (< (+ i 2) (length words))
                                  (let ((next-word (nth (+ i 2) words)))
                                    (member next-word
                                            tibetan-enhanced-parser--case-particle-tails))
                                  (fboundp 'tibetan-lookup-word-in-steinert))
                         (let* ((upgraded-joined
                                 (string-join
                                  (cl-subseq words i (+ i 3)) "་"))
                                (upgraded-hit
                                 (ignore-errors
                                   (tibetan-lookup-word-in-steinert
                                    upgraded-joined))))
                           (when (and upgraded-hit
                                      (stringp upgraded-hit)
                                      ;; Exclude Rangjung-Yeshe phrasal
                                      ;; entries; accept curated
                                      ;; lexicographic sources.
                                      (not (string-match-p
                                            "\\[[0-9]+-RangjungYeshe\\]"
                                            upgraded-hit)))
                             (setq effective-len 3
                                   effective-joined upgraded-joined
                                   effective-hit upgraded-hit))))
                       ;; Verb-tail guard: don't let a 3+ syllable
                       ;; phrasal MWU absorb a finite verb (e.g. the
                       ;; Rangjung-Yeshe phrasal `དྲུང་དུ་ཕྱིན').  Skip →
                       ;; the loop falls through to a shorter length,
                       ;; leaving the verb separate for clause /
                       ;; sentence-structure analysis.  User-curated
                       ;; Resources / Custom MWUs are EXEMPT — if Carsten
                       ;; defined `ཆུང་མ་བྱེད' ("to take a wife") as a
                       ;; unit, honour it even though it ends in བྱེད.
                       (unless (and (>= effective-len 3)
                                    (not resources-vocab)
                                    (not custom-vocab)
                                    (tibetan-enhanced-parser--verb-tail-p
                                     effective-joined))
                         (let ((data (cond
                                     (resources-vocab
                                      `((english . ,resources-vocab)
                                        (category . "resources")))
                                     (custom-vocab
                                      `((english . ,custom-vocab)
                                        (category . "custom")))
                                     (compound compound)
                                     (proper-noun proper-noun)
                                     (comp-vocab
                                      `((english . ,comp-vocab)
                                        (category . "vocabulary")))
                                     (effective-hit
                                      `((english . ,effective-hit)
                                        (category . "steinert"))))))
                           (push (list i (+ i effective-len)
                                       effective-joined data)
                                 matches))
                         (setq found t)
                         (setq i (+ i effective-len)))))))
        (unless found
          (setq i (1+ i)))))
    (nreverse matches)))

;; ============================================================================
;; ENHANCED WORD ANALYSIS
;; ============================================================================

(defun tibetan-analyze-word-unit (word _prev-word _next-word)
  "Analyze single tsheg-delimited WORD with context.
PREV-WORD and NEXT-WORD provide context.
Returns alist with analysis data."
  (let ((result nil))

    ;; Check if word ends with common particle suffixes
    (cond
     ;; Genitive suffix: འི, གི, ཀྱི, ཡི
     ((string-match "\\([^་]+\\)\\(འི\\|གི\\|ཀྱི\\|ཡི\\)$" word)
      (let ((base (match-string 1 word))
            (particle (match-string 2 word)))
        (setq result `((type . "word+genitive")
                      (base . ,base)
                      (particle . ,particle)
                      (function . "Marks possessor or modifier")))))

     ;; Nominalizer: པ or བ at end
     ((string-match "\\([^་]+\\)\\([པབ]\\)$" word)
      (let ((base (match-string 1 word))
            (nominalizer (match-string 2 word)))
        (setq result `((type . "word+nominalizer")
                      (base . ,base)
                      (particle . ,nominalizer)
                      (function . "Nominalizes verb or creates agent noun")))))

     ;; Standalone case particle
     ((member word '("ན" "ལ" "ར" "སུ" "ཏུ" "དུ" "ནས" "ལས" "དང"))
      (setq result `((type . "case_particle")
                    (particle . ,word)
                    (function . ,(tibetan-particle-function word)))))

     ;; Default: just a word
     (t
      (setq result `((type . "word")
                    (form . ,word)))))

    result))

(defun tibetan-particle-function (particle)
  "Return function description for PARTICLE."
  (cond
   ((string= particle "ན") "Locative: marks location or temporal/conditional setting")
   ((string= particle "ལ") "Dative: marks recipient, indirect object, or location")
   ((string= particle "ར") "Terminative: marks direction, goal, manner, or result")
   ((string= particle "སུ") "Terminative: marks direction, goal, manner, or result")
   ((string= particle "ཏུ") "Terminative: marks direction, goal, manner, or result")
   ((string= particle "དུ") "Terminative: marks direction, goal, manner, or result")
   ((string= particle "ནས") "Ablative/converb: marks source or 'after V-ing'")
   ((string= particle "ལས") "Ablative: marks source, origin, or comparison")
   ((string= particle "དང") "Comitative: marks accompaniment, conjunction")
   (t "Case particle")))

;; ============================================================================
;; VERB+NOMINALIZER DETECTION
;; ============================================================================

(defun tibetan-find-verb-nominalizer-units (words)
  "Find verb+nominalizer constructions in WORDS list.
Patterns like སྨྲས་པ (said + nominalizer) should be grouped together.
Returns list of (start-index end-index form data) tuples."
  (let ((matches '())
        (i 0))
    (while (< (1+ i) (length words))
      (let* ((word1 (nth i words))
             (word2 (nth (1+ i) words))
             ;; Check if word1 is a verb and word2 is a nominalizer
             (verb-entry (when (fboundp 'tibetan-verb-lookup)
                           (tibetan-verb-lookup word1)))
             (is-nominalizer (member word2 '("པ" "བ" "པོ" "བོ" "མ" "མོ"))))
        (if (and verb-entry is-nominalizer)
            (let* ((joined (concat word1 "་" word2))
                   (meaning (alist-get 'meaning verb-entry))
                   (lemma (alist-get 'lemma verb-entry))
                   ;; Create appropriate English gloss
                   (english-gloss (cond
                                   ((member word2 '("པོ" "བོ"))
                                    (format "one who %s (agent)" (or meaning lemma)))
                                   ((member word2 '("མ" "མོ"))
                                    (format "she who %s / female %s-er" (or meaning lemma) (or meaning lemma)))
                                   (t  ; པ or བ
                                    (format "the %s-ing / having %s-ed (nominalized verb)" (or meaning lemma) (or meaning lemma))))))
              (push (list i (+ i 2) joined
                         `((english . ,english-gloss)
                           (wylie . ,(when (fboundp 'tibetan-to-wylie-fixed)
                                       (condition-case nil
                                           (tibetan-to-wylie-fixed joined)
                                         (error nil))))
                           (category . "verb+nominalizer")
                           (verb-lemma . ,lemma)
                           (verb-meaning . ,meaning)
                           (nominalizer . ,word2)))
                    matches)
              (setq i (+ i 2)))  ; Skip both words
          (setq i (1+ i)))))
    (nreverse matches)))

;; ============================================================================
;; ENHANCED PARSING PIPELINE
;; ============================================================================

(defun tibetan-parse-enhanced (text)
  "Enhanced parsing of TEXT.
Returns structured analysis with:
- Multi-word units (compounds, proper nouns)
- Verb+nominalizer constructions (སྨྲས་པ, etc.)
- Word-level analysis
- Particle identification (only at boundaries)
- Context-aware verb identification."
  (when (and text (stringp text) (not (string-empty-p text)))
    (let* ((words (tibetan-segment-text text))
         (multiword-units (tibetan-find-multiword-units words))
         ;; Also find verb+nominalizer constructions
         (verb-nom-units (tibetan-find-verb-nominalizer-units words))
         (analysis '())
         (covered-indices (make-hash-table :test 'equal)))

    ;; Merge verb+nominalizer units with multiword units
    ;; (verb-nom-units take precedence if not already covered by compounds)
    (dolist (vn-unit verb-nom-units)
      (let* ((start (nth 0 vn-unit))
             (end (nth 1 vn-unit))
             ;; Check if any index in this range is already claimed by a compound
             (already-claimed (cl-some (lambda (mw-unit)
                                         (let ((mw-start (nth 0 mw-unit))
                                               (mw-end (nth 1 mw-unit)))
                                           (or (and (>= start mw-start) (< start mw-end))
                                               (and (> end mw-start) (<= end mw-end)))))
                                       multiword-units)))
        (unless already-claimed
          (push vn-unit multiword-units))))
    ;; Sort by start index
    (setq multiword-units (sort multiword-units (lambda (a b) (< (nth 0 a) (nth 0 b)))))

    ;; Mark indices covered by multi-word units
    (dolist (unit multiword-units)
      (cl-loop for i from (nth 0 unit) below (nth 1 unit)
               do (puthash i t covered-indices)))

    ;; Process each position
    (cl-loop for i from 0 below (length words)
             do
             (if (gethash i covered-indices)
                 ;; Part of multi-word unit - find which one
                 (let ((unit (cl-find-if (lambda (u) (and (>= i (nth 0 u))
                                                         (< i (nth 1 u))))
                                        multiword-units)))
                   (when (and unit (= i (nth 0 unit)))  ; First word of unit
                     (push `((type . "compound")
                            (form . ,(nth 2 unit))
                            (data . ,(nth 3 unit))
                            (start-index . ,(nth 0 unit))
                            (end-index . ,(nth 1 unit)))
                           analysis)))
               ;; Single word - analyze it
               (let* ((word (nth i words))
                      (prev (when (> i 0) (nth (1- i) words)))
                      (next (when (< i (1- (length words))) (nth (1+ i) words)))
                      (word-analysis (tibetan-analyze-word-unit word prev next)))
                 (push `((type . "word")
                        (form . ,word)
                        (index . ,i)
                        (analysis . ,word-analysis))
                       analysis))))

    `((words . ,words)
      (analysis . ,(nreverse analysis))
      (multiword-units . ,multiword-units)))))

;; ============================================================================
;; HELPER FUNCTIONS
;; ============================================================================

(provide 'tibetan-enhanced-parser)
;;; tibetan-enhanced-parser.el ends here
