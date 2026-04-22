;;; tibetan-vocabulary-detailed.el --- Detailed dictionary-style vocabulary lookup -*- lexical-binding: t -*-

;;; Commentary:
;; Provides enhanced vocabulary lookup that returns detailed dictionary entries
;; with primary translation, detailed explanation, Sanskrit terms, and source info.
;;
;; Entry format:
;;   ((primary . "main translation")
;;    (detailed . "full detailed explanation with all meanings")
;;    (sanskrit . "Sanskrit term if available")
;;    (wylie . "Wylie transliteration")
;;    (source . "source glossary name")
;;    (compound-p . t/nil))
;;
;; Used by both C-c u i and C-c u A for consistent output.

;;; Code:

(require 'cl-lib)
;; Soft dependency: verb classifier provides authoritative verb meanings,
;; used by stem-reference enrichment. Load if available.
(require 'tibetan-verb-classifier nil t)
;; Soft dependency: Steinert SQLite dictionary supplies Sanskrit
;; equivalents and a broad fallback gloss source. Load if available.
(require 'tibetan-steinert nil t)
;; Soft dependency: user-editable multilingual thesaurus (Pass 5b).
;; When loaded, `tibetan-thesaurus-lookup' is consulted at rank 1 of
;; `tibetan-vocab-multisource-entries'.  Missing module → no
;; thesaurus hits; the rest of the pipeline is unaffected.
(require 'tibetan-thesaurus nil t)

;; ============================================================================
;; DETAILED VOCABULARY CACHE
;; ============================================================================

(defvar tibetan-detailed-vocab-cache (make-hash-table :test 'equal)
  "Cache for detailed vocabulary entries.
Key: Tibetan or Wylie term
Value: plist with :primary :detailed :sanskrit :wylie :source")

;;;###autoload
(defun tibetan-vocab-clear-cache ()
  "Clear the detailed vocabulary cache.
Use this after reloading vocabulary code so that updated lookup logic
(e.g. verb-stem enrichment) takes effect for already-queried words."
  (interactive)
  (let ((n (hash-table-count tibetan-detailed-vocab-cache)))
    (clrhash tibetan-detailed-vocab-cache)
    (message "Cleared %d cached vocabulary entries" n)))

;; ============================================================================
;; ENTRY PARSING - Extract structured info from raw glossary entries
;; ============================================================================

(defun tibetan-vocab--first-sense-bracket-aware (text)
  "Return the prefix of TEXT up to the first `;', `,', or `.' that
appears at bracket-depth zero.  `[]' and `()' nest, so a comma
inside `[accusative, adverbial …]' does NOT terminate the sense.

Returns the full TEXT if no terminator is found at depth zero."
  (if (or (null text) (not (stringp text)) (string-empty-p text))
      text
    (let ((depth 0)
          (end (length text))
          (i 0)
          (len (length text)))
      (catch 'done
        (while (< i len)
          (let ((c (aref text i)))
            (cond
             ((or (= c ?\[) (= c ?\()) (cl-incf depth))
             ((or (= c ?\]) (= c ?\))) (when (> depth 0) (cl-decf depth)))
             ((and (= depth 0)
                   (or (= c ?\;) (= c ?,) (= c ?.)))
              (setq end i)
              (throw 'done nil))))
          (cl-incf i)))
      (substring text 0 end))))

(defun tibetan-vocab--parse-entry (raw-entry)
  "Parse RAW-ENTRY string into structured format.
Returns plist with :primary :detailed :sanskrit."
  (when (and raw-entry (stringp raw-entry) (not (string-empty-p raw-entry)))
    (let ((primary nil)
          (detailed raw-entry)
          (sanskrit nil))

      ;; Extract Sanskrit term if present (common patterns)
      ;; Pattern: {Skt. term} or (Skt: term) or [Sanskrit: term]
      (when (string-match "{\\([^}]+\\)}" raw-entry)
        (let ((match (match-string 1 raw-entry)))
          (when (or (string-match-p "^[A-Za-z]" match)
                    (string-match-p "skt\\|Skt\\|SKT\\|sanskrit\\|Sanskrit" match))
            (setq sanskrit (replace-regexp-in-string "^[Ss]kt\\.?:?\\s-*" "" match)))))

      ;; Also check for Skt. or Sanskrit: patterns
      (unless sanskrit
        (when (string-match "[Ss]anskrit:?\\s-*\\([A-Za-z][a-z]*\\)" raw-entry)
          (setq sanskrit (match-string 1 raw-entry))))

      ;; Extract primary meaning: text up to the first `;' / `,' / `.'
      ;; at BRACKET-DEPTH ZERO.  A naive split would chop `(1) [accusative,
      ;; adverbial accusative, …' at the first comma inside `[accusative,
      ;; …]', producing a useless `(1) [accusative' fragment for words
      ;; like `ལ' whose gloss starts with a bracketed list.
      (let ((first-meaning raw-entry))
        ;; Remove leading numbers like "1) " or "1. ".
        (setq first-meaning (replace-regexp-in-string "^[0-9]+[.):]\\s-*" "" first-meaning))
        (setq primary (tibetan-vocab--first-sense-bracket-aware first-meaning))
        (when primary
          (setq primary (string-trim primary))
          ;; Remove "to " prefix for verbs if it makes it cleaner
          ;; (setq primary (replace-regexp-in-string "^to " "" primary))
          ))

      (list :primary (or primary detailed)
            :detailed detailed
            :sanskrit sanskrit))))

(defun tibetan-vocab--get-wylie (tibetan-word)
  "Get Wylie transliteration for TIBETAN-WORD."
  (when (and tibetan-word (string-match-p "^[ༀ-࿿]" tibetan-word))
    (condition-case nil
        (when (fboundp 'tibetan-to-wylie-fixed)
          (tibetan-to-wylie-fixed tibetan-word))
      (error nil))))

(defun tibetan-vocab--tibetan-from-wylie (wylie)
  "Get Tibetan script from WYLIE transliteration."
  (when (and wylie (string-match-p "^[a-z]" wylie))
    (condition-case nil
        (when (fboundp 'tibetan-wylie-to-tibetan)
          (tibetan-wylie-to-tibetan wylie))
      (error nil))))

;; ============================================================================
;; VERB-STEM REFERENCE FOLLOWING
;; ============================================================================

(defconst tibetan-vocab--stem-ref-pattern
  "\\b\\(?:pf\\.\\|Pf\\.\\|pres\\.\\|pres\\|fut\\.\\|Fut\\.\\|ft\\.\\|imp\\.\\|Imp\\.\\)[ \t]+\\(?:of\\|von\\|zu\\)[ \t]+\\([a-zA-Z' ]+?\\)\\(?:[;,.]\\|//\\|$\\)"
  "Regex matching verb-stem references in vocabulary entries.
Matches patterns such as \\=`pf. of byed\\=', \\=`Pf. von rgyal du dzugs\\=',
\\=`fut. of sleb pa\\=', \\=`Imp. von gtong\\='.  The base Wylie form is
captured in group 1.")

(defun tibetan-vocab--extract-stem-reference (text)
  "Return the base Wylie form referenced in TEXT.
For example \\=`byed\\=' for input containing \\=`pf. of byed\\='.
Returns nil if no stem reference is found."
  (when (and text (stringp text))
    (save-match-data
      (when (string-match tibetan-vocab--stem-ref-pattern text)
        (let ((base (string-trim (match-string 1 text))))
          (unless (or (string-empty-p base)
                      ;; Filter junk captures: must look like Wylie (letters/spaces/apostrophe)
                      (not (string-match-p "^[a-zA-Z][a-zA-Z' ]*$" base)))
            base))))))

(defun tibetan-vocab--already-has-gloss-p (text)
  "Return non-nil if TEXT already contains a gloss after the stem reference,
i.e. a semicolon or the German//English separator following the reference."
  (and text
       (stringp text)
       (string-match-p
        "\\b\\(?:pf\\.\\|Pf\\.\\|pres\\.\\|pres\\|fut\\.\\|Fut\\.\\|ft\\.\\|imp\\.\\|Imp\\.\\)[ \t]+\\(?:of\\|von\\|zu\\)[ \t]+[^;]*;"
        text)))

;; ============================================================================
;; COMPREHENSIVE LOOKUP - Try all sources
;; ============================================================================

(defvar tibetan-vocab--enriching nil
  "Non-nil while a stem-reference base lookup is in progress; disables
further enrichment to prevent recursion cycles.")

(defun tibetan-vocab--lookup-base-meaning (wylie-base)
  "Return a short English meaning for WYLIE-BASE.
Prefers the Hill 2010 verb table (authoritative for common verbs like
byed/gtong/dzugs), then falls back to `tibetan-vocab-lookup-detailed'.
The verb table is consulted first because general dictionaries (RY,
DharmaMitra) often return idiomatic senses for bare verbs."
  (let* ((tibetan (tibetan-vocab--tibetan-from-wylie wylie-base))
         (verb-entry (and tibetan
                          (fboundp 'tibetan-verb-lookup)
                          (tibetan-verb-lookup tibetan)))
         (verb-meaning (and verb-entry
                            (cdr (assoc 'meaning verb-entry)))))
    (cond
     (verb-meaning (string-trim verb-meaning))
     (t
      (let ((dict-entry (tibetan-vocab-lookup-detailed wylie-base)))
        (when dict-entry
          (plist-get dict-entry :primary)))))))

(defun tibetan-vocab--enrich-with-base (entry)
  "If ENTRY's :primary is a bare stem reference (e.g. \"pf. of byed\"),
look up the base form and append its primary meaning.
Returns a possibly-modified copy of ENTRY. Recursion-safe via a
dynamic flag `tibetan-vocab--enriching'."
  (if tibetan-vocab--enriching
      entry
    (let* ((primary (plist-get entry :primary))
           (detailed (plist-get entry :detailed))
           ;; `parse-entry' truncates at the first period, so for input
           ;; "pf. of byed" :primary becomes just "pf". Fall back to
           ;; :detailed to recover the full stem reference.
           (base (or (tibetan-vocab--extract-stem-reference primary)
                     (tibetan-vocab--extract-stem-reference detailed))))
      (if (and base
               (not (tibetan-vocab--already-has-gloss-p primary))
               (not (tibetan-vocab--already-has-gloss-p detailed)))
          (let* ((tibetan-vocab--enriching t)
                 (base-primary (tibetan-vocab--lookup-base-meaning base)))
            (if (and base-primary (not (string-empty-p base-primary)))
                (if (tibetan-vocab--extract-stem-reference base-primary)
                    entry
                  ;; Use " — " (em dash) instead of ";" so the appended
                  ;; base meaning survives downstream "first sense"
                  ;; splitters that cut on semicolons.
                  ;; For :primary, use :detailed as the base text (since
                  ;; parse-entry may have truncated :primary at a period),
                  ;; so the user sees the full "pf. of byed — to do, to make".
                  (let* ((primary-base (if (tibetan-vocab--extract-stem-reference primary)
                                           primary
                                         detailed))
                         (new-primary (format "%s — %s" primary-base base-primary))
                         (new-detailed (if (and detailed
                                                (not (string= detailed primary))
                                                (not (tibetan-vocab--already-has-gloss-p detailed)))
                                           (format "%s — %s" detailed base-primary)
                                         detailed))
                         (enriched (copy-sequence entry)))
                    (setq enriched (plist-put enriched :primary new-primary))
                    (setq enriched (plist-put enriched :detailed new-detailed))
                    enriched))
              entry))
        entry))))

(defun tibetan-vocab-lookup-detailed (word)
  "Look up WORD and return detailed dictionary entry.
Tries: Resources vocab, custom vocab, bundled glossaries, DharmaMitra.
WORD can be Tibetan script or Wylie.
Returns plist with :primary :detailed :sanskrit :wylie :source, or nil."
  (when (and word (stringp word) (not (string-empty-p word)))
    ;; Check cache first
    (let ((cached (gethash word tibetan-detailed-vocab-cache)))
      (if cached
          cached
        ;; Not cached - do full lookup
        (let ((result nil)
              (wylie (if (string-match-p "^[ༀ-࿿]" word)
                         (tibetan-vocab--get-wylie word)
                       word))
              (tibetan (if (string-match-p "^[a-z]" word)
                           (tibetan-vocab--tibetan-from-wylie word)
                         word)))

          ;; Try Resources vocabulary first (highest priority)
          (unless result
            (when (and (boundp 'tibetan-current-resources-vocab)
                       tibetan-current-resources-vocab)
              (let ((entry (or (gethash tibetan tibetan-current-resources-vocab)
                               (and wylie (gethash wylie tibetan-current-resources-vocab)))))
                (when entry
                  (let ((parsed (tibetan-vocab--parse-entry entry)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Resources")))))))

          ;; Try custom vocabulary
          (unless result
            (when (and (boundp 'tibetan-current-custom-vocab)
                       tibetan-current-custom-vocab)
              (let ((entry (or (gethash tibetan tibetan-current-custom-vocab)
                               (and wylie (gethash wylie tibetan-current-custom-vocab)))))
                (when entry
                  (let ((parsed (tibetan-vocab--parse-entry entry)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Custom")))))))

          ;; Try bundled glossaries (Hopkins, etc.)
          (unless result
            (when (and (boundp 'tibetan-comprehensive-vocabulary)
                       tibetan-comprehensive-vocabulary)
              (let ((entry (or (gethash tibetan tibetan-comprehensive-vocabulary)
                               (and wylie (gethash wylie tibetan-comprehensive-vocabulary)))))
                (when entry
                  (let ((parsed (tibetan-vocab--parse-entry entry)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Bundled")))))))

          ;; Try Rangjung Yeshe dictionary (162k entries, lazy-loaded)
          (unless result
            (when (fboundp 'tibetan-lookup-word-in-rangjung-yeshe)
              (let ((ry-result (tibetan-lookup-word-in-rangjung-yeshe (or tibetan word))))
                (when ry-result
                  (let ((parsed (tibetan-vocab--parse-entry ry-result)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source "Rangjung Yeshe")))))))

          ;; Try DharmaMitra as fallback
          (unless result
            (when (fboundp 'tibetan-lookup-word-in-dharmamitra)
              (let ((dm-result (tibetan-lookup-word-in-dharmamitra (or tibetan word))))
                (when dm-result
                  (let ((parsed (tibetan-vocab--parse-entry dm-result)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit nil
                                       :wylie wylie
                                       :source "DharmaMitra")))))))

          ;; Steinert fallback: if nothing else matched, pull the best
          ;; available gloss from Christian Steinert's aggregated DB.
          (unless result
            (when (fboundp 'tibetan-steinert-lookup)
              (let ((hits (tibetan-steinert-lookup (or tibetan word) 5)))
                (when hits
                  (let* ((preferred (or (cl-find-if
                                         (lambda (h)
                                           (let ((src (plist-get h :source)))
                                             (member src
                                                     '("02-RangjungYeshe"
                                                       "01-Hopkins2015"
                                                       "43-84000Dict"
                                                       "07-JimValby"
                                                       "08-IvesWaldo"))))
                                         hits)
                                        (car hits)))
                         (gloss (plist-get preferred :gloss))
                         (parsed (tibetan-vocab--parse-entry gloss)))
                    (setq result (list :primary (plist-get parsed :primary)
                                       :detailed (plist-get parsed :detailed)
                                       :sanskrit (plist-get parsed :sanskrit)
                                       :wylie wylie
                                       :source (format "Steinert/%s"
                                                       (plist-get preferred :source)))))))))

          ;; Sanskrit enrichment: if we have a result with no Sanskrit,
          ;; probe Steinert's Sanskrit-indexed sources so the Detailed
          ;; Dictionary can surface the Sanskrit equivalent.
          (when (and result
                     (not (plist-get result :sanskrit))
                     (fboundp 'tibetan-steinert-sanskrit-for))
            (let ((skt (tibetan-steinert-sanskrit-for (or tibetan word))))
              (when (and skt (not (string-empty-p skt)))
                (setq result (plist-put result :sanskrit skt)))))

          ;; Follow stem references like "pf. of byed" -> append base meaning
          (when result
            (setq result (tibetan-vocab--enrich-with-base result)))

          ;; Cache and return
          (when result
            (puthash word result tibetan-detailed-vocab-cache))
          result)))))

;; ============================================================================
;; COMPOUND-AWARE VOCABULARY EXTRACTION
;; ============================================================================

(defun tibetan-vocab-extract-detailed (tibetan-text)
  "Extract detailed vocabulary from TIBETAN-TEXT.
Returns list of plists, each with keys
:tibetan :wylie :primary :detailed :sanskrit :source.
Uses greedy matching: tries longer compounds first (4, 3, 2 syllables)
before falling back to single syllables.  Provides a consistent
format for both the classroom view (C-c u i) and the persistent
analysis (C-c u A)."
  (when (and tibetan-text (not (string-empty-p tibetan-text)))
    ;; Load vocabularies
    (when (fboundp 'tibetan-load-resources-vocab)
      (tibetan-load-resources-vocab))
    (when (fboundp 'tibetan-load-custom-vocab)
      (tibetan-load-custom-vocab))

    ;; Normalize text
    (setq tibetan-text (replace-regexp-in-string " " "་" tibetan-text))
    (setq tibetan-text (replace-regexp-in-string "།+" "།" tibetan-text))

    (let* ((syllables (split-string tibetan-text "་" t))
           (num-syllables (length syllables))
           (vocab-list '())
           (i 0)
           (seen (make-hash-table :test 'equal)))  ; Avoid duplicates

      (while (< i num-syllables)
        (let* ((syl (string-trim (nth i syllables)))
               (syl-clean (replace-regexp-in-string "[།༎༏]" "" syl))
               (found nil)
               (matched-len 1))  ; How many syllables were matched

          (unless (or (string-empty-p syl-clean)
                      (gethash syl-clean seen))

            ;; Greedy matching: try 4, 3, 2 syllable compounds first.
            ;;
            ;; Reject any compound whose head OR tail syllable is a
            ;; case / converb particle — those should be tokenised
            ;; separately so the Detailed Dictionary shows the stem
            ;; and the particle as their own entries, matching the
            ;; Word / Particle List and Particle Map.  Without this,
            ;; dictionary idioms like `བདག་ལ' ("to me", Skt. naḥ) and
            ;; `སྟོད་ནས' ("from above", Skt. uparimāt) would be picked
            ;; up as single lexical units, hiding the grammatical
            ;; split that downstream sections (Clause Structure,
            ;; Grammatical Markers) otherwise render correctly.
            ;;
            ;; See `tibetan-extract-vocab--tail-is-particle-p' +
            ;; `--head-is-particle-p' in `core/tibetan-vocabulary.el'
            ;; for the sibling Word/Particle List code path kept in
            ;; sync with this one.
            (cl-loop for compound-len from 4 downto 2
                     until found
                     when (<= (+ i compound-len) num-syllables)
                     do
                     (let* ((syls (cl-loop for j from i below (+ i compound-len)
                                           collect (replace-regexp-in-string
                                                    "[།༎༏]" ""
                                                    (string-trim (nth j syllables)))))
                            (compound (mapconcat #'identity syls "་")))
                       (unless (or (and (fboundp 'tibetan-extract-vocab--tail-is-particle-p)
                                        (tibetan-extract-vocab--tail-is-particle-p compound))
                                   (and (fboundp 'tibetan-extract-vocab--head-is-particle-p)
                                        (tibetan-extract-vocab--head-is-particle-p compound)))
                         (let ((entry (tibetan-vocab-lookup-detailed compound)))
                           (when entry
                             (puthash compound t seen)
                             (push (list :tibetan compound
                                         :wylie (plist-get entry :wylie)
                                         :primary (plist-get entry :primary)
                                         :detailed (plist-get entry :detailed)
                                         :sanskrit (plist-get entry :sanskrit)
                                         :source (plist-get entry :source)
                                         :compound-p t)
                                   vocab-list)
                             (setq found t)
                             (setq matched-len compound-len))))))

            ;; Try single syllable if no compound found
            (unless found
              (let ((entry (tibetan-vocab-lookup-detailed syl-clean)))
                (when entry
                  (puthash syl-clean t seen)
                  (push (list :tibetan syl-clean
                              :wylie (plist-get entry :wylie)
                              :primary (plist-get entry :primary)
                              :detailed (plist-get entry :detailed)
                              :sanskrit (plist-get entry :sanskrit)
                              :source (plist-get entry :source)
                              :compound-p nil)
                        vocab-list))
                ;; Even if not found, add placeholder
                (unless entry
                  (let ((wylie (tibetan-vocab--get-wylie syl-clean)))
                    (puthash syl-clean t seen)
                    (push (list :tibetan syl-clean
                                :wylie wylie
                                :primary "[not found]"
                                :detailed nil
                                :sanskrit nil
                                :source nil
                                :compound-p nil)
                          vocab-list))))))

          ;; Advance by the number of syllables matched
          (setq i (+ i matched-len))))

      (nreverse vocab-list))))

;; ============================================================================
;; FORMATTED OUTPUT - For display in analysis
;; ============================================================================

(defun tibetan-vocab-format-entry-short (entry)
  "Format ENTRY plist as short one-line summary.
Format: ཚིག /*wylie*/ — primary meaning"
  (let ((tibetan (plist-get entry :tibetan))
        (wylie (plist-get entry :wylie))
        (primary (plist-get entry :primary)))
    (format "%s /*%s*/ — %s"
            tibetan
            (or wylie "?")
            (or primary "[not found]"))))

(defun tibetan-vocab-format-entry-full (entry)
  "Format ENTRY plist as full dictionary entry.
Format:
  ཚིག /*wylie*/
    Primary: meaning
    Full: detailed explanation
    Sanskrit: term (if available)
    Source: glossary name"
  (let ((tibetan (plist-get entry :tibetan))
        (wylie (plist-get entry :wylie))
        (primary (plist-get entry :primary))
        (detailed (plist-get entry :detailed))
        (sanskrit (plist-get entry :sanskrit))
        (source (plist-get entry :source)))
    (concat
     (format "◆ %s" tibetan)
     (when wylie (format "  [%s]" wylie))
     "\n"
     (format "  %s\n" (or primary "[not found]"))
     (when (and detailed (not (equal detailed primary)))
       (format "  Full: %s\n"
               (if (> (length detailed) 200)
                   (concat (substring detailed 0 197) "...")
                 detailed)))
     (when sanskrit (format "  Sanskrit: %s\n" sanskrit))
     (when source (format "  Source: %s\n" source)))))

(defun tibetan-vocab-format-list-short (vocab-list)
  "Format VOCAB-LIST as short vocabulary section for analysis files."
  (mapconcat #'tibetan-vocab-format-entry-short vocab-list "\n"))

(defun tibetan-vocab-format-list-full (vocab-list)
  "Format VOCAB-LIST as full dictionary section."
  (mapconcat #'tibetan-vocab-format-entry-full vocab-list "\n"))

;; ============================================================================
;; MULTI-SOURCE LOOKUP — for the Detailed Dictionary section
;; ============================================================================
;;
;; `tibetan-vocab-lookup-detailed' returns a single "best" entry (first
;; source that matches), which is right for the short Word / Particle
;; List.  The Detailed Dictionary section wants the opposite: show every
;; source that carries non-redundant information, in a consistent order.
;;
;; Order (rule A, as agreed with the user):
;;
;;   1. Provided vocabulary list (Resources folder, per-document)
;;   2. Custom vocabulary (user's own list)
;;   3. Steinert aggregated DB (top hits)
;;   4. Rangjung Yeshe standalone
;;   5. Bundled glossaries (Hopkins/Bialek)
;;   6. DharmaMitra
;;
;; Within this order, near-duplicate entries are suppressed — we only
;; keep a later source if its gloss differs substantially from what
;; earlier sources already said ("serious deviation").  Sanskrit is
;; surfaced ONLY when the source entry carries it natively; we do not
;; synthesise Sanskrit from separate Sanskrit-indexed tables.

(defconst tibetan-vocab--steinert-cap 5
  "Maximum number of Steinert rows surfaced per word in the multi-source
Detailed Dictionary block.  Lower values produce tighter blocks at the
cost of variety for deeply polysemous terms; higher values restore the
wider coverage.  Tuned down from the original 8 after real-segment
review showed words like ཡུལ / ཤོ / ལ producing overly long blocks.")

(defun tibetan-vocab--dedup-fingerprint (text)
  "Return a normalised fingerprint of TEXT for gloss deduplication.
Lower-cases, collapses whitespace, strips punctuation, and truncates
to 80 chars.  Two entries with the same fingerprint are treated as
near-duplicates and only the first is shown."
  (let* ((s (or text ""))
         (s (downcase s))
         (s (replace-regexp-in-string "[].;:,!?(){}/—–[-]" " " s))
         (s (replace-regexp-in-string "[[:space:]]+" " " s))
         (s (string-trim s)))
    (if (> (length s) 80) (substring s 0 80) s)))

(defconst tibetan-vocab--sanskrit-diacritics
  '(?ā ?ī ?ū ?ṛ ?ṝ ?ḷ ?ḹ ?ṁ ?ṃ ?ḥ ?ṇ ?ṅ ?ñ ?ṭ ?ḍ ?ś ?ṣ
    ?Ā ?Ī ?Ū ?Ṛ ?Ṇ ?Ṅ ?Ñ ?Ṭ ?Ḍ ?Ś ?Ṣ ?Ṃ ?Ḥ)
  "Characters that signal IAST-transliterated Sanskrit.
Used by `tibetan-vocab--looks-like-sanskrit-p' as a quick filter to
distinguish real Sanskrit (e.g. `pāramitā', `ātman', `uparimāt')
from Wylie cross-references that sometimes end up in the `Sanskrit'
field (e.g. `ste', `{gzhi yis/}', `bdag nyid').")

(defun tibetan-vocab--looks-like-sanskrit-p (text)
  "Return non-nil when TEXT appears to be genuine Sanskrit content
rather than a Wylie cross-reference masquerading in the Sanskrit field.

Heuristic:
  1. Devanāgarī characters (U+0900–U+097F) → Sanskrit.  True positive.
  2. Any IAST diacritic (see `tibetan-vocab--sanskrit-diacritics') →
     Sanskrit.  Real Sanskrit transliteration nearly always has them.
  3. Curly-brace Wylie citation `{...}' → Wylie cross-ref, not Sanskrit.
  4. Leading `=' sign — common Steinert convention for Wylie
     cross-references (`= {gzhi yis/}', `= ste') — not Sanskrit.
  5. Otherwise, if every token is ASCII lowercase without diacritics,
     assume Wylie (e.g. `ste', `bdag nyid').

False positives are cheaper than false negatives (losing real Sanskrit),
so when in doubt we fall through to `t'."
  (when (and text (stringp text))
    (let ((s (string-trim text)))
      (cond
       ((string-empty-p s) nil)
       ;; Wylie cross-refs via curly-brace citation.
       ((string-match-p "{[^}]*}" s) nil)
       ;; Steinert's leading-= Wylie cross-ref marker.
       ((string-match-p "\\`[ \t]*=[ \t]" s) nil)
       ;; Devanāgarī block — definitely Sanskrit.
       ((string-match-p "[ऀ-ॿ]" s) t)
       ;; IAST diacritic character — strong Sanskrit signal.
       ((cl-some (lambda (c) (memq c tibetan-vocab--sanskrit-diacritics))
                 (string-to-list s))
        t)
       ;; Plain ASCII lowercase without any diacritics looks like Wylie.
       ((string-match-p "\\`[-a-z0-9 '/]+\\'" s) nil)
       ;; Anything else — probably safe to display.
       (t t)))))

(defun tibetan-vocab--make-source-entry (seen source-name raw-gloss
                                              native-sanskrit wylie)
  "Build a source-entry plist for RAW-GLOSS, or return nil to skip.

SEEN is a hash-table tracking gloss fingerprints already emitted; if
the fingerprint of this entry is present (or empty), nil is returned
and SEEN is left untouched.  On success, the fingerprint is recorded
in SEEN and a plist (:source :primary :detailed :sanskrit :wylie)
is returned.

Sanskrit is preferred from NATIVE-SANSKRIT (the source row's own
field), falling back to whatever the parser extracts from the gloss
text — never synthesised from elsewhere."
  (when (and raw-gloss
             (stringp raw-gloss)
             (not (string-empty-p (string-trim raw-gloss))))
    (let* ((parsed (tibetan-vocab--parse-entry raw-gloss))
           (primary (plist-get parsed :primary))
           (detailed (plist-get parsed :detailed))
           (skt (let ((s (or native-sanskrit (plist-get parsed :sanskrit))))
                  (and s (stringp s)
                       (not (string-empty-p (string-trim s)))
                       ;; Only surface the field if it's genuine Sanskrit —
                       ;; not a Wylie cross-reference that happens to be
                       ;; stored in this slot (e.g. `ste', `{gzhi yis/}').
                       ;; See `tibetan-vocab--looks-like-sanskrit-p'.
                       (tibetan-vocab--looks-like-sanskrit-p s)
                       (string-trim s))))
           (fp (tibetan-vocab--dedup-fingerprint
                (or detailed primary ""))))
      (unless (or (string-empty-p fp)
                  (gethash fp seen))
        (puthash fp t seen)
        (list :source source-name
              :primary primary
              :detailed detailed
              :sanskrit skt
              :wylie wylie)))))

(defvar-local tibetan-vocab--corpus nil
  "Per-buffer corpus-specific Steinert sub-dictionary promoted by the
ranker to rank-2 slot (below Thesaurus / Resources / Custom).  Set
by the reader from the source file's `#+TIBETAN_CORPUS:' header —
e.g. `Yogacarabhumi' picks `22-Yoghacharabhumi-glossary' as the
corpus source.  Unset: the ranker still works, just without the
corpus boost.")

(defconst tibetan-vocab--corpus-source-map
  '(("Yogacarabhumi" . "22-Yoghacharabhumi-glossary")
    ("YBh"           . "22-Yoghacharabhumi-glossary")
    ("Mahavyutpatti" . "21-Mahavyutpatti-Skt")
    ("84000"         . "43-84000Dict"))
  "Map of `#+TIBETAN_CORPUS:' values to Steinert source names.
The ranker promotes the matching source to rank 2 (just below the
user-curated sources).  Add entries here when you want a new corpus
identifier to be recognised.")

(defun tibetan-vocab-rank-source (source)
  "Return an integer rank for SOURCE (a :source plist value).  Lower
is better.  Used by `tibetan-vocab--sort-entries-by-rank' to pick the
best dictionary entry per term — the one whose gloss is surfaced by
the Interlinear Gloss and appears first in the Detailed Dictionary.

Rank layers (2026-04-22):

  1 — Thesaurus (user-curated via zettelkasten — reserved for Pass 5b).
  2 — Resources / Custom (per-document vocabulary list).
  3 — Corpus-specific (e.g. `22-Yoghacharabhumi-glossary' when
      reading a YBh text — set via `tibetan-vocab--corpus').
  4 — `Steinert/01-Hopkins2015' (modern scholarly Buddhist).
  5 — `Steinert/43-84000Dict' (84000 canonical translations).
  6 — `Steinert/02-RangjungYeshe' (Buddhist practice vocabulary).
  7 — `Rangjung Yeshe' (standalone, separate integration).
  8 — `Steinert/08-IvesWaldo', `Steinert/07-JimValby',
      `Steinert/09-DanMartin', `Steinert/10-RichardBarron' etc.
  9 — `Bundled' (synthetic local glossary).
 10 — `DharmaMitra' (last-resort API fallback).
 99 — any unrecognised source."
  (cond
   ((null source) 99)
   ((string-prefix-p "Thesaurus" source) 1)
   ((or (string-prefix-p "Resources" source)
        (string-prefix-p "Custom" source))
    2)
   ((and tibetan-vocab--corpus
         (let ((corpus-src (cdr (assoc tibetan-vocab--corpus
                                        tibetan-vocab--corpus-source-map))))
           (and corpus-src
                (string= source (format "Steinert/%s" corpus-src)))))
    3)
   ((string= source "Steinert/01-Hopkins2015") 4)
   ((string= source "Steinert/43-84000Dict") 5)
   ((string= source "Steinert/02-RangjungYeshe") 6)
   ((string= source "Rangjung Yeshe") 7)
   ((string-prefix-p "Steinert/" source) 8)
   ((string= source "Bundled") 9)
   ((string= source "DharmaMitra") 10)
   (t 99)))

(defun tibetan-vocab--sort-entries-by-rank (entries)
  "Return ENTRIES sorted by source rank, preserving original order
within ties.  Emacs' `sort' is stable, so two entries with the same
rank stay in insertion order."
  (sort (copy-sequence entries)
        (lambda (a b)
          (< (tibetan-vocab-rank-source (plist-get a :source))
             (tibetan-vocab-rank-source (plist-get b :source))))))

(defun tibetan-vocab-find-sanskrit (entries)
  "Return the first genuine Sanskrit gloss found in ENTRIES, or nil.
Walks the ranked list (or any list) and returns the first `:sanskrit'
field that passes `tibetan-vocab--looks-like-sanskrit-p' — filtering
out Wylie cross-references that masquerade in the Sanskrit slot."
  (catch 'found
    (dolist (e entries)
      (let ((s (plist-get e :sanskrit)))
        (when (and s (stringp s) (not (string-empty-p (string-trim s)))
                   (tibetan-vocab--looks-like-sanskrit-p s))
          (throw 'found (string-trim s)))))
    nil))

(defun tibetan-vocab-best-entry (entries)
  "Return the top-ranked entry from ENTRIES (or nil).  Shortcut for
`(car (tibetan-vocab--sort-entries-by-rank ENTRIES))'."
  (car (tibetan-vocab--sort-entries-by-rank entries)))

(defun tibetan-vocab-term-anchor (wylie)
  "Return a stable org-mode anchor slug for WYLIE.
Used by the Interlinear Gloss renderer as the target of its internal
link (`[[term-bdag-la][bdag la]]') pointing at the matching
`<<term-bdag-la>>' target in the Detailed Dictionary section below.

The slug is lowercased, spaces and apostrophes become dashes, and
anything outside `[-a-z0-9]' is dropped.  Prefixed with `term-' so
the namespace doesn't collide with user-defined org targets.

Examples:
  (tibetan-vocab-term-anchor \"bdag la\")     \\=> \"term-bdag-la\"
  (tibetan-vocab-term-anchor \"rnal \\='byor\")  \\=> \"term-rnal-byor\"
  (tibetan-vocab-term-anchor \"byang chub sems dpa\\='\") \\=>
    \"term-byang-chub-sems-dpa\""
  (when (and wylie (stringp wylie))
    (let* ((s (downcase (string-trim wylie)))
           (s (replace-regexp-in-string "[ '’]" "-" s))
           (s (replace-regexp-in-string "[^-a-z0-9]" "" s))
           (s (replace-regexp-in-string "-+" "-" s))
           (s (replace-regexp-in-string "\\`-\\|-\\'" "" s)))
      (if (string-empty-p s) nil
        (concat "term-" s)))))

(defcustom tibetan-vocab-detailed-max-sources 3
  "Maximum number of source entries emitted per term in the Detailed
Dictionary.  Resources and Custom entries are ALWAYS preserved — the
cap only trims subsequent automatic-dictionary hits (Steinert /
Rangjung Yeshe / Bundled / DharmaMitra).  Raise this to see the
underlying polysemy in full; lower it to compact the section.

Default 3 strikes a balance: one curated source (if present) + up to
three reference glosses covers the sense space for class reading
without turning each entry into a wall of near-duplicates."
  :type 'integer
  :group 'tibetan-cat)

(defun tibetan-vocab-detailed-cap-entries (entries)
  "Return ENTRIES trimmed per `tibetan-vocab-detailed-max-sources'.
Resources and Custom entries (user-curated) are always kept; the cap
only applies to subsequent automatic-dictionary sources.  Order is
preserved.

Example: with max=3 and entries
  (Resources Custom Steinert/01 Steinert/02 Rangjung DharmaMitra)
returns
  (Resources Custom Steinert/01 Steinert/02 Rangjung)
(2 curated kept + 3 automatic = 5 total)."
  (when entries
    (let ((curated '())
          (others '())
          (cap (or tibetan-vocab-detailed-max-sources 3)))
      (dolist (e entries)
        (let ((src (plist-get e :source)))
          (if (and src (or (string-prefix-p "Resources" src)
                           (string-prefix-p "Custom" src)))
              (push e curated)
            (push e others))))
      (append (nreverse curated)
              (seq-take (nreverse others) cap)))))

(defun tibetan-vocab-multisource-entries (word)
  "Return an ordered, deduplicated list of dictionary entries for WORD.
Each element is a plist (:source :primary :detailed :sanskrit :wylie).

Priority order:
  1. Resources (provided per-document vocabulary list)
  2. Custom (user list)
  3. Steinert aggregated DB — several top hits
  4. Rangjung Yeshe standalone
  5. Bundled glossaries (Hopkins / Bialek)
  6. DharmaMitra

Near-duplicates are skipped, so polysemous entries like ཡུལ do not
produce ten variants of the same gloss.  Sanskrit is emitted only
when the source entry carries it natively."
  (when (and word (stringp word) (not (string-empty-p word)))
    (let* ((wylie (if (string-match-p "^[ༀ-࿿]" word)
                      (tibetan-vocab--get-wylie word)
                    word))
           (tibetan (if (string-match-p "^[a-z]" word)
                        (tibetan-vocab--tibetan-from-wylie word)
                      word))
           (results '())
           (seen (make-hash-table :test 'equal)))
      (cl-flet ((add (source-name raw-gloss &optional native-skt &rest extras)
                  (let ((e (tibetan-vocab--make-source-entry
                            seen source-name raw-gloss native-skt wylie)))
                    (when e
                      ;; Merge any extra plist fields from EXTRAS onto
                      ;; the entry (e.g. `:zettel-id' for Thesaurus)
                      ;; so downstream renderers can surface them.
                      (while extras
                        (setq e (plist-put e (car extras) (cadr extras)))
                        (setq extras (cddr extras)))
                      (push e results)))))
        ;; 0. Thesaurus (Kramer-seeded, user-editable) — rank 1.
        ;;    The student's chosen rendering wins over Resources, all
        ;;    Steinert sub-dictionaries, RY, and Bundled.  Lookup uses
        ;;    the Wylie key from the zettel's `- Wylie: ...' field.
        (when (fboundp 'tibetan-thesaurus-lookup)
          (let ((th-entries (ignore-errors
                              (tibetan-thesaurus-lookup wylie))))
            (dolist (th th-entries)
              (let* ((de (plist-get th :primary-de))
                     (en (plist-get th :primary-en))
                     ;; Bilingual gloss format matches the existing
                     ;; `tibetan-analysis--format-bilingual-gloss'
                     ;; expectation (DE // EN); either half may be
                     ;; nil if the zettel hasn't filled it in yet.
                     (gloss (cond
                             ((and de en) (format "%s // %s" de en))
                             (de de)
                             (en en)
                             (t nil))))
                (when gloss
                  ;; Override `:primary' and `:detailed' AFTER the
                  ;; add so the full bilingual `DE // EN' string
                  ;; survives — the default `parse-entry' would trim
                  ;; `:primary' at the first comma, losing the
                  ;; English half and breaking the Interlinear's
                  ;; `prefer-english' split.
                  (add "Thesaurus (Kramer)"
                       gloss
                       (plist-get th :sanskrit)
                       :zettel-id   (plist-get th :id)
                       :zettel-path (plist-get th :path)
                       :primary     gloss
                       :detailed    gloss))))))
        ;; 1. Resources (provided per-document list)
        (when (and (boundp 'tibetan-current-resources-vocab)
                   tibetan-current-resources-vocab)
          (let ((entry (or (and tibetan (gethash tibetan
                                                 tibetan-current-resources-vocab))
                           (and wylie (gethash wylie
                                               tibetan-current-resources-vocab)))))
            (when entry (add "Resources (provided)" entry))))
        ;; 2. Custom vocabulary
        (when (and (boundp 'tibetan-current-custom-vocab)
                   tibetan-current-custom-vocab)
          (let ((entry (or (and tibetan (gethash tibetan
                                                 tibetan-current-custom-vocab))
                           (and wylie (gethash wylie
                                               tibetan-current-custom-vocab)))))
            (when entry (add "Custom" entry))))
        ;; 3. Steinert aggregated DB — top hits, deduped by fingerprint.
        ;; We pass the cap to the lookup AND trim defensively on our side,
        ;; so the bound holds even if a backend ignores the limit arg.
        (when (fboundp 'tibetan-steinert-lookup)
          (let* ((cap tibetan-vocab--steinert-cap)
                 (hits (condition-case nil
                           (tibetan-steinert-lookup (or tibetan word) cap)
                         (error nil)))
                 (hits (if (and hits (> (length hits) cap))
                           (cl-subseq hits 0 cap)
                         hits)))
            (dolist (h hits)
              (add (format "Steinert/%s" (or (plist-get h :source) "?"))
                   (plist-get h :gloss)
                   (plist-get h :sanskrit)))))
        ;; 4. Rangjung Yeshe standalone — surfaces only if it adds new content.
        (when (fboundp 'tibetan-lookup-word-in-rangjung-yeshe)
          (let ((ry (condition-case nil
                        (tibetan-lookup-word-in-rangjung-yeshe (or tibetan word))
                      (error nil))))
            (when ry (add "Rangjung Yeshe" ry))))
        ;; 5. Bundled glossaries (Hopkins, Bialek, …)
        (when (and (boundp 'tibetan-comprehensive-vocabulary)
                   tibetan-comprehensive-vocabulary)
          (let ((entry (or (and tibetan (gethash tibetan
                                                 tibetan-comprehensive-vocabulary))
                           (and wylie (gethash wylie
                                               tibetan-comprehensive-vocabulary)))))
            (when entry (add "Bundled" entry))))
        ;; 6. DharmaMitra fallback
        (when (fboundp 'tibetan-lookup-word-in-dharmamitra)
          (let ((dm (condition-case nil
                        (tibetan-lookup-word-in-dharmamitra (or tibetan word))
                      (error nil))))
            (when dm (add "DharmaMitra" dm)))))
      ;; 1. Rank the full list (Thesaurus → Resources → Corpus-specific
      ;;    → Hopkins2015 → 84000 → RY → others → Bundled → DharmaMitra)
      ;;    so callers that take `(car …)' get the quality-best entry.
      ;; 2. Apply the cap: Resources / Custom always kept (user-curated,
      ;;    never trimmed), automatic-dictionary hits trimmed to
      ;;    `tibetan-vocab-detailed-max-sources' (default 3).
      (tibetan-vocab-detailed-cap-entries
       (tibetan-vocab--sort-entries-by-rank (nreverse results))))))

;; ============================================================================
;; INTEGRATION FUNCTION - For analysis generation
;; ============================================================================


(provide 'tibetan-vocabulary-detailed)
;;; tibetan-vocabulary-detailed.el ends here
