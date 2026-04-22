;;; tibetan-vocab-multisource-test.el --- Multi-source dictionary tests -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for `tibetan-vocab-multisource-entries' in
;; `core/tibetan-vocabulary-detailed.el'.
;;
;; Contract under test:
;;   1. Provided list (Resources) entry appears first.
;;   2. Steinert rows are included, deduplicated internally.
;;   3. Near-duplicate glosses across sources are collapsed
;;      (dedup-fingerprint heuristic).
;;   4. Sanskrit is only surfaced when the source entry itself
;;      carries it — no synthesis from sanskrit-indexed tables.
;;
;; All external lookups are stubbed so the test does not depend on
;; SQLite or any glossary files being present.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-vocabulary-detailed)

;; ----------------------------------------------------------------------------
;; Fingerprint-level checks
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-vocab-dedup-fingerprint-collapses-whitespace ()
  "Extra whitespace and punctuation do not affect the fingerprint."
  (should (equal (tibetan-vocab--dedup-fingerprint "object; place")
                 (tibetan-vocab--dedup-fingerprint "OBJECT , PLACE"))))

(ert-deftest tibetan-vocab-dedup-fingerprint-distinguishes-content ()
  "Genuinely different glosses produce different fingerprints."
  (should-not (equal
               (tibetan-vocab--dedup-fingerprint "object, place, domain")
               (tibetan-vocab--dedup-fingerprint
                "country of origin; homeland"))))

;; ----------------------------------------------------------------------------
;; Multi-source ordering + dedup
;; ----------------------------------------------------------------------------

(defmacro tibetan-mst--with-stubs (bindings &rest body)
  "Run BODY with the multi-source lookup dependencies stubbed.
BINDINGS is a plist: :resources ENTRY-STR :custom ENTRY-STR
:steinert HITS :rangjung ENTRY-STR :bundled ENTRY-STR
:dharmamitra ENTRY-STR."
  (declare (indent 1))
  `(let ((tibetan-current-resources-vocab
          (let ((h (make-hash-table :test 'equal)))
            (when ,(plist-get bindings :resources)
              (puthash "ཡུལ" ,(plist-get bindings :resources) h))
            h))
         (tibetan-current-custom-vocab
          (let ((h (make-hash-table :test 'equal)))
            (when ,(plist-get bindings :custom)
              (puthash "ཡུལ" ,(plist-get bindings :custom) h))
            h))
         (tibetan-comprehensive-vocabulary
          (let ((h (make-hash-table :test 'equal)))
            (when ,(plist-get bindings :bundled)
              (puthash "ཡུལ" ,(plist-get bindings :bundled) h))
            h)))
     (cl-letf (((symbol-function 'tibetan-steinert-lookup)
                (lambda (_word &optional _lim) ,(plist-get bindings :steinert)))
               ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
                (lambda (_word) ,(plist-get bindings :rangjung)))
               ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
                (lambda (_word) ,(plist-get bindings :dharmamitra)))
               ;; Wylie conversion: keep it identity-ish so tests don't
               ;; need a full Wylie engine.
               ((symbol-function 'tibetan-vocab--get-wylie)
                (lambda (_w) "yul"))
               ((symbol-function 'tibetan-vocab--tibetan-from-wylie)
                (lambda (_w) "ཡུལ")))
       ,@body)))

(ert-deftest tibetan-vocab-multisource-resources-comes-first ()
  "When a provided vocabulary list has the word, it is entry #1."
  (tibetan-mst--with-stubs
      (:resources "Land, Gebiet // country, region"
       :steinert (list (list :source "02-RangjungYeshe"
                             :gloss "country, place, object"
                             :sanskrit nil))
       :rangjung nil :bundled nil :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
      (should entries)
      (should (string-prefix-p "Resources"
                               (plist-get (car entries) :source))))))

(ert-deftest tibetan-vocab-multisource-steinert-before-rangjung-standalone ()
  "Steinert rows precede the Rangjung-Yeshe-standalone block."
  (tibetan-mst--with-stubs
      (:resources nil
       :steinert (list (list :source "02-RangjungYeshe"
                             :gloss "place, region, object of cognition"
                             :sanskrit nil))
       :rangjung "homeland, ancestral region"
       :bundled nil :dharmamitra nil)
    (let* ((entries (tibetan-vocab-multisource-entries "ཡུལ"))
           (sources (mapcar (lambda (e) (plist-get e :source)) entries)))
      (should (> (length entries) 1))
      (should (string-prefix-p "Steinert" (car sources)))
      (should (cl-some (lambda (s) (string= s "Rangjung Yeshe")) sources))
      ;; Steinert first, Rangjung Yeshe later
      (should (< (cl-position (car sources) sources :test #'string=)
                 (cl-position "Rangjung Yeshe" sources :test #'string=))))))

(ert-deftest tibetan-vocab-multisource-dedupes-near-duplicates ()
  "Two sources with near-identical glosses only produce one entry."
  (tibetan-mst--with-stubs
      (:resources nil
       :steinert (list (list :source "02-RangjungYeshe"
                             :gloss "object; place; domain"
                             :sanskrit nil))
       :rangjung "OBJECT, PLACE, DOMAIN"   ; same content, different shape
       :bundled nil :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
      (should (= (length entries) 1))
      (should (string-prefix-p "Steinert"
                               (plist-get (car entries) :source))))))

(ert-deftest tibetan-vocab-multisource-keeps-serious-deviation ()
  "Two sources with substantially different glosses are BOTH kept."
  (tibetan-mst--with-stubs
      (:resources nil
       :steinert (list (list :source "02-RangjungYeshe"
                             :gloss "object of cognition; sense field"
                             :sanskrit nil))
       :rangjung "country of origin; homeland; ancestral land"
       :bundled nil :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
      (should (= (length entries) 2)))))

(ert-deftest tibetan-vocab-multisource-sanskrit-only-when-native ()
  "Sanskrit appears only for sources that carry it natively."
  (tibetan-mst--with-stubs
      (:resources nil
       :steinert (list (list :source "21-Mahavyutpatti-Skt"
                             :gloss "viṣaya — object, sphere"
                             :sanskrit "viṣaya")
                       (list :source "02-RangjungYeshe"
                             :gloss "home country; native land"
                             :sanskrit nil))
       :rangjung nil :bundled nil :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
      (should (= (length entries) 2))
      ;; Sanskrit carried only on the Mahāvyutpatti entry
      (let ((with-skt (cl-remove-if-not
                       (lambda (e) (plist-get e :sanskrit))
                       entries)))
        (should (= (length with-skt) 1))
        (should (string= (plist-get (car with-skt) :sanskrit) "viṣaya"))))))

(ert-deftest tibetan-vocab-multisource-caps-steinert-volume ()
  "Multisource does not return more than the configured Steinert cap
even when the backend returns many rows.  The cap is the single source
of truth: `tibetan-vocab--steinert-cap'."
  (let ((many (cl-loop for i from 1 to 20
                       collect (list :source (format "src-%02d" i)
                                     :gloss (format "gloss variant number %d \
with enough distinct text to survive the fingerprint" i)
                                     :sanskrit nil))))
    (tibetan-mst--with-stubs
        (:resources nil :steinert many
         :rangjung nil :bundled nil :dharmamitra nil)
      (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
        (should (<= (length entries) tibetan-vocab--steinert-cap))))))

(ert-deftest tibetan-vocab-multisource-custom-appears ()
  "A Custom-vocab entry is surfaced when no Resources entry shadows it,
and is labelled accordingly."
  (tibetan-mst--with-stubs
      (:resources nil
       :custom "object, domain (user note)"
       :steinert nil :rangjung nil :bundled nil :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
      (should (= (length entries) 1))
      (should (string= (plist-get (car entries) :source) "Custom")))))

(ert-deftest tibetan-vocab-multisource-custom-after-resources ()
  "When both Resources and Custom carry the word, Resources is #1
and Custom only appears if its gloss is a serious deviation."
  (tibetan-mst--with-stubs
      (:resources "Land, Gebiet // country"
       :custom "completely different user-note content for this term"
       :steinert nil :rangjung nil :bundled nil :dharmamitra nil)
    (let* ((entries (tibetan-vocab-multisource-entries "ཡུལ"))
           (sources (mapcar (lambda (e) (plist-get e :source)) entries)))
      (should (>= (length entries) 1))
      (should (string-prefix-p "Resources" (car sources)))
      (when (> (length entries) 1)
        (should (string= (nth 1 sources) "Custom"))))))

(ert-deftest tibetan-vocab-multisource-bundled-appears ()
  "A Bundled-glossary entry surfaces when nothing earlier covers it."
  (tibetan-mst--with-stubs
      (:resources nil :custom nil :steinert nil :rangjung nil
       :bundled "territory, jurisdiction, realm"
       :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
      (should (= (length entries) 1))
      (should (string= (plist-get (car entries) :source) "Bundled")))))

(ert-deftest tibetan-vocab-multisource-dharmamitra-fallback ()
  "DharmaMitra entries surface last and only when they add new content."
  (tibetan-mst--with-stubs
      (:resources nil :custom nil
       :steinert (list (list :source "02-RangjungYeshe"
                             :gloss "object of cognition"
                             :sanskrit nil))
       :rangjung nil :bundled nil
       :dharmamitra "completely distinct DharmaMitra phrasing here")
    (let* ((entries (tibetan-vocab-multisource-entries "ཡུལ"))
           (sources (mapcar (lambda (e) (plist-get e :source)) entries)))
      (should (= (length entries) 2))
      (should (string-prefix-p "Steinert" (car sources)))
      (should (string= (cadr sources) "DharmaMitra")))))

;; ----------------------------------------------------------------------------
;; Edge-case inputs and error paths
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-vocab-multisource-nil-or-empty-input ()
  "Calling with nil or empty string returns nil without error."
  (should (null (tibetan-vocab-multisource-entries nil)))
  (should (null (tibetan-vocab-multisource-entries ""))))

(ert-deftest tibetan-vocab-multisource-wylie-input-resolves-to-tibetan ()
  "Passing a Wylie string resolves to the Tibetan form for hash lookup.
The Resources hash is keyed by the Tibetan form; a Wylie-input call
must still find it via the Wylie→Tibetan converter."
  (tibetan-mst--with-stubs
      (:resources "Land, Gebiet // country"
       :custom nil :steinert nil :rangjung nil
       :bundled nil :dharmamitra nil)
    (let ((entries (tibetan-vocab-multisource-entries "yul")))
      (should (= (length entries) 1))
      (should (string-prefix-p "Resources"
                               (plist-get (car entries) :source))))))

(ert-deftest tibetan-vocab-multisource-resources-keyed-by-wylie-fallback ()
  "If the Resources hash is keyed only by the Wylie form, the lookup
still finds the entry via the wylie-fallback branch."
  (let ((tibetan-current-resources-vocab
         (let ((h (make-hash-table :test 'equal)))
           (puthash "yul" "Land // country" h)
           h))
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'tibetan-steinert-lookup)
               (lambda (_w &optional _l) nil))
              ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
               (lambda (_w) nil))
              ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
               (lambda (_w) nil))
              ((symbol-function 'tibetan-vocab--get-wylie)
               (lambda (_w) "yul"))
              ((symbol-function 'tibetan-vocab--tibetan-from-wylie)
               (lambda (_w) "ཡུལ")))
      (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
        (should (= (length entries) 1))
        (should (string-prefix-p "Resources"
                                 (plist-get (car entries) :source)))))))

(ert-deftest tibetan-vocab-multisource-steinert-error-is-swallowed ()
  "A Steinert backend that throws is caught; other sources still return."
  (let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
        (tibetan-current-custom-vocab nil)
        (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'tibetan-steinert-lookup)
               (lambda (_w &optional _l) (error "DB unavailable")))
              ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
               (lambda (_w) "homeland, native region"))
              ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
               (lambda (_w) nil))
              ((symbol-function 'tibetan-vocab--get-wylie)
               (lambda (_w) "yul"))
              ((symbol-function 'tibetan-vocab--tibetan-from-wylie)
               (lambda (_w) "ཡུལ")))
      (let ((entries (tibetan-vocab-multisource-entries "ཡུལ")))
        (should (= (length entries) 1))
        (should (string= (plist-get (car entries) :source)
                         "Rangjung Yeshe"))))))

;; ----------------------------------------------------------------------------
;; Fingerprint bounds
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-vocab-dedup-fingerprint-caps-at-80-chars ()
  "Fingerprint never exceeds 80 characters, even for long glosses."
  (let* ((long (mapconcat #'identity
                          (make-list 40 "object place domain") " "))
         (fp (tibetan-vocab--dedup-fingerprint long)))
    (should (<= (length fp) 80))))

;; ============================================================================
;; Bracket-aware first-sense extraction
;; ============================================================================
;; Regression guard for `tibetan-vocab--first-sense-bracket-aware'.
;; The naive regex split (`[^;.,]+') chops `(1) [accusative, adverbial …'
;; at the comma inside the bracket, producing a nonsense `(1) [accusative'
;; fragment.  The bracket-aware scanner must keep the bracketed block
;; intact and only split at top-level punctuation.

(ert-deftest tibetan-vocab-first-sense-keeps-bracketed-comma ()
  "Commas inside `[…]' don't terminate the first sense."
  (should (string= (tibetan-vocab--first-sense-bracket-aware
                    "(1) [accusative, adverbial accusative, dative, and locative particle:] to; as; -ly")
                   "(1) [accusative, adverbial accusative, dative, and locative particle:] to")))

(ert-deftest tibetan-vocab-first-sense-keeps-paren-comma ()
  "Commas inside `(…)' don't terminate either."
  (should (string= (tibetan-vocab--first-sense-bracket-aware
                    "verb (do, make, fabricate); noun (action)")
                   "verb (do, make, fabricate)")))

(ert-deftest tibetan-vocab-first-sense-splits-at-toplevel-comma ()
  "A top-level comma DOES terminate, preserving the legacy behaviour
for short multi-sense glosses."
  (should (string= (tibetan-vocab--first-sense-bracket-aware
                    "to do, to make")
                   "to do")))

(ert-deftest tibetan-vocab-first-sense-splits-at-toplevel-semicolon ()
  "A top-level semicolon also terminates."
  (should (string= (tibetan-vocab--first-sense-bracket-aware
                    "first sense; second sense")
                   "first sense")))

(ert-deftest tibetan-vocab-first-sense-no-terminator-returns-all ()
  "If no terminator at depth zero, return the whole string."
  (should (string= (tibetan-vocab--first-sense-bracket-aware
                    "single sense no punctuation")
                   "single sense no punctuation")))

(ert-deftest tibetan-vocab-first-sense-handles-nil-and-empty ()
  "Nil / empty inputs are returned untouched (no error)."
  (should (null (tibetan-vocab--first-sense-bracket-aware nil)))
  (should (string= (tibetan-vocab--first-sense-bracket-aware "") "")))

(ert-deftest tibetan-vocab-parse-entry-la-gloss-keeps-bracket ()
  "End-to-end: parsing the full Steinert/Hopkins gloss for `ལ' must
yield a `:primary' that retains the bracketed list, not chop it
off as `(1) [accusative'."
  (let* ((entry (tibetan-vocab--parse-entry
                 "(1) [accusative, adverbial accusative, dative, and locative particle:] to; as; -ly; in; at; conjunction: and; but; (2) mountain pass"))
         (primary (plist-get entry :primary)))
    (should primary)
    (should (string-match-p "accusative, adverbial" primary))
    (should-not (string= primary "(1) [accusative"))))

;; ============================================================================
;; Pass B (2026-04-22) — Sanskrit detector, source cap, particle exemption
;; ============================================================================

(ert-deftest tibetan-vocab-looks-like-sanskrit-iast ()
  "IAST-transliterated Sanskrit (macrons, ṛ, ṃ, ś, ṣ, etc.) is
recognised as genuine Sanskrit."
  (should (tibetan-vocab--looks-like-sanskrit-p "pāramitā"))
  (should (tibetan-vocab--looks-like-sanskrit-p "ātman"))
  (should (tibetan-vocab--looks-like-sanskrit-p "uparimāt"))
  (should (tibetan-vocab--looks-like-sanskrit-p "dṛṣṭa"))
  (should (tibetan-vocab--looks-like-sanskrit-p "saṃsāra")))

(ert-deftest tibetan-vocab-looks-like-sanskrit-rejects-wylie-xref ()
  "Wylie cross-references that end up in the :sanskrit field are NOT
reported as Sanskrit — they're Tibetan romanisation, not Sanskrit.
Regression guard for 2026-04-22: entries like `Skt: ste',
`Skt: bdag nyid', `Skt: {gzhi yis/}' were surfacing as fake Sanskrit
in the Detailed Dictionary before this filter."
  ;; Pure ASCII lowercase, no diacritics — looks like Wylie.
  (should-not (tibetan-vocab--looks-like-sanskrit-p "ste"))
  (should-not (tibetan-vocab--looks-like-sanskrit-p "bdag nyid"))
  (should-not (tibetan-vocab--looks-like-sanskrit-p "byed pa"))
  ;; Curly-brace Wylie citation — common in Steinert output.
  (should-not (tibetan-vocab--looks-like-sanskrit-p "{gzhi yis/}"))
  ;; Leading `= ' marker — Steinert's Wylie cross-ref convention.
  (should-not (tibetan-vocab--looks-like-sanskrit-p "= {gzhi yis/}"))
  (should-not (tibetan-vocab--looks-like-sanskrit-p "= ste")))

(ert-deftest tibetan-vocab-looks-like-sanskrit-accepts-devanagari ()
  "Sanskrit in Devanāgarī is unambiguously accepted."
  (should (tibetan-vocab--looks-like-sanskrit-p "आत्मन्"))
  (should (tibetan-vocab--looks-like-sanskrit-p "संसार")))

(ert-deftest tibetan-vocab-looks-like-sanskrit-empty-nil ()
  "Empty or nil input returns nil without signalling."
  (should-not (tibetan-vocab--looks-like-sanskrit-p nil))
  (should-not (tibetan-vocab--looks-like-sanskrit-p ""))
  (should-not (tibetan-vocab--looks-like-sanskrit-p "   ")))

(ert-deftest tibetan-vocab-cap-entries-preserves-curated ()
  "Resources / Custom entries are always kept regardless of the cap —
only automatic-dictionary sources get trimmed."
  (let ((tibetan-vocab-detailed-max-sources 2))
    (let ((result (tibetan-vocab-detailed-cap-entries
                   (list (list :source "Resources (provided)" :primary "A")
                         (list :source "Custom" :primary "B")
                         (list :source "Steinert/01-Hopkins" :primary "C")
                         (list :source "Steinert/02-RY" :primary "D")
                         (list :source "Rangjung Yeshe" :primary "E")
                         (list :source "DharmaMitra" :primary "F")))))
      ;; 2 curated kept + 2 automatic (cap=2) = 4 total.
      (should (= 4 (length result)))
      ;; Curated come first.
      (should (string= "Resources (provided)"
                       (plist-get (nth 0 result) :source)))
      (should (string= "Custom" (plist-get (nth 1 result) :source))))))

(ert-deftest tibetan-vocab-cap-entries-trims-automatic-only ()
  "When there are no Resources / Custom entries, the cap applies to all."
  (let ((tibetan-vocab-detailed-max-sources 3))
    (let ((result (tibetan-vocab-detailed-cap-entries
                   (list (list :source "Steinert/01" :primary "A")
                         (list :source "Steinert/02" :primary "B")
                         (list :source "Steinert/08" :primary "C")
                         (list :source "Rangjung Yeshe" :primary "D")
                         (list :source "DharmaMitra" :primary "E")))))
      (should (= 3 (length result))))))

(ert-deftest tibetan-vocab-cap-entries-nil-input ()
  "Nil / empty input returns nil without error."
  (should (null (tibetan-vocab-detailed-cap-entries nil)))
  (should (null (tibetan-vocab-detailed-cap-entries '()))))

(ert-deftest tibetan-analysis-detailed-dict-particle-p ()
  "Single-syllable case/converb particles are detected as particles."
  (skip-unless (fboundp 'tibetan-analysis--detailed-dict-is-particle-p))
  (should (tibetan-analysis--detailed-dict-is-particle-p "ལ"))
  (should (tibetan-analysis--detailed-dict-is-particle-p "ནས"))
  (should (tibetan-analysis--detailed-dict-is-particle-p "ཏེ"))
  (should (tibetan-analysis--detailed-dict-is-particle-p "ནི"))
  (should (tibetan-analysis--detailed-dict-is-particle-p "གི"))
  (should (tibetan-analysis--detailed-dict-is-particle-p "ཀྱི")))

(ert-deftest tibetan-analysis-detailed-dict-content-word-not-particle ()
  "Multi-syllable content words and lexical items are NOT flagged as
particles (or they'd lose their dictionary entries)."
  (skip-unless (fboundp 'tibetan-analysis--detailed-dict-is-particle-p))
  (should-not (tibetan-analysis--detailed-dict-is-particle-p "བདག"))
  (should-not (tibetan-analysis--detailed-dict-is-particle-p "སྟོད"))
  (should-not (tibetan-analysis--detailed-dict-is-particle-p "འོངས"))
  (should-not (tibetan-analysis--detailed-dict-is-particle-p "བྱང་ཆུབ"))
  (should-not (tibetan-analysis--detailed-dict-is-particle-p "སངས་རྒྱས")))

;; ----------------------------------------------------------------------------
;; Pass 5a: dictionary ranker, Sanskrit finder, term-anchor slug
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-vocab-rank-source-orders-layers ()
  "Source ranker returns a strict ordering for the 10 documented layers,
independent of corpus setting."
  (skip-unless (fboundp 'tibetan-vocab-rank-source))
  (let ((tibetan-vocab--corpus nil))
    (should (= 1  (tibetan-vocab-rank-source "Thesaurus")))
    (should (= 2  (tibetan-vocab-rank-source "Resources/YBh")))
    (should (= 2  (tibetan-vocab-rank-source "Custom")))
    (should (= 4  (tibetan-vocab-rank-source "Steinert/01-Hopkins2015")))
    (should (= 5  (tibetan-vocab-rank-source "Steinert/43-84000Dict")))
    (should (= 6  (tibetan-vocab-rank-source "Steinert/02-RangjungYeshe")))
    (should (= 7  (tibetan-vocab-rank-source "Rangjung Yeshe")))
    (should (= 8  (tibetan-vocab-rank-source "Steinert/08-IvesWaldo")))
    (should (= 9  (tibetan-vocab-rank-source "Bundled")))
    (should (= 10 (tibetan-vocab-rank-source "DharmaMitra")))
    (should (= 99 (tibetan-vocab-rank-source "SomethingUnknown")))
    (should (= 99 (tibetan-vocab-rank-source nil)))))

(ert-deftest tibetan-vocab-rank-source-promotes-corpus-to-rank-3 ()
  "When `tibetan-vocab--corpus' matches an entry in
`tibetan-vocab--corpus-source-map', the corresponding Steinert
sub-dictionary is promoted to rank 3 (between user-curated and
Hopkins2015)."
  (skip-unless (fboundp 'tibetan-vocab-rank-source))
  (let ((tibetan-vocab--corpus "Yogacarabhumi"))
    (should (= 3 (tibetan-vocab-rank-source
                  "Steinert/22-Yoghacharabhumi-glossary")))
    ;; Without corpus matching, same source falls back to "other Steinert"
    (should (= 4 (tibetan-vocab-rank-source "Steinert/01-Hopkins2015"))))
  (let ((tibetan-vocab--corpus nil))
    (should (= 8 (tibetan-vocab-rank-source
                  "Steinert/22-Yoghacharabhumi-glossary"))))
  ;; Unknown corpus identifier does not crash, just no promotion
  (let ((tibetan-vocab--corpus "NotAKnownCorpus"))
    (should (= 8 (tibetan-vocab-rank-source
                  "Steinert/22-Yoghacharabhumi-glossary")))))

(ert-deftest tibetan-vocab-sort-entries-by-rank-is-stable ()
  "The sorter returns entries in rank order and preserves original order
for ties."
  (skip-unless (fboundp 'tibetan-vocab--sort-entries-by-rank))
  (let* ((entries
          (list (list :source "DharmaMitra" :tibetan "a")
                (list :source "Steinert/01-Hopkins2015" :tibetan "b")
                (list :source "Bundled" :tibetan "c")
                (list :source "Resources/x" :tibetan "d")
                (list :source "Steinert/02-RangjungYeshe" :tibetan "e")))
         (sorted (tibetan-vocab--sort-entries-by-rank entries)))
    (should (equal (mapcar (lambda (e) (plist-get e :tibetan)) sorted)
                   '("d" "b" "e" "c" "a")))))

(ert-deftest tibetan-vocab-find-sanskrit-rejects-wylie-crossrefs ()
  "`tibetan-vocab-find-sanskrit' walks entries and returns the first
Sanskrit that passes the diacritic filter; plain Wylie-looking strings
are rejected."
  (skip-unless (and (fboundp 'tibetan-vocab-find-sanskrit)
                    (fboundp 'tibetan-vocab--looks-like-sanskrit-p)))
  ;; Wylie cross-ref masquerading as Sanskrit is skipped in favour of
  ;; the real IAST entry below it.
  (should (equal "ātman"
                 (tibetan-vocab-find-sanskrit
                  '((:source "Bundled"  :sanskrit "bdag nyid")
                    (:source "Steinert/01-Hopkins2015"
                     :sanskrit "ātman")))))
  ;; Nothing plausible → nil.
  (should (null (tibetan-vocab-find-sanskrit
                 '((:source "Bundled" :sanskrit "")
                   (:source "Bundled" :sanskrit nil)))))
  ;; Devanāgarī is accepted.
  (should (equal "बुद्ध"
                 (tibetan-vocab-find-sanskrit
                  '((:source "Bundled" :sanskrit "बुद्ध"))))))

(ert-deftest tibetan-vocab-best-entry-returns-top-rank ()
  "`tibetan-vocab-best-entry' is shorthand for (car sort)."
  (skip-unless (fboundp 'tibetan-vocab-best-entry))
  (let* ((entries (list (list :source "Bundled"    :tibetan "a")
                        (list :source "Resources/x":tibetan "b")
                        (list :source "DharmaMitra":tibetan "c")))
         (best (tibetan-vocab-best-entry entries)))
    (should (equal "b" (plist-get best :tibetan)))))

(ert-deftest tibetan-vocab-term-anchor-slugs ()
  "Term-anchor slug helper produces stable `term-xxx' ids for org-mode
radio-target jumping."
  (skip-unless (fboundp 'tibetan-vocab-term-anchor))
  (should (equal "term-bdag-la"   (tibetan-vocab-term-anchor "bdag la")))
  (should (equal "term-rnal-byor" (tibetan-vocab-term-anchor "rnal 'byor")))
  (should (equal "term-byang-chub-sems-dpa"
                 (tibetan-vocab-term-anchor "byang chub sems dpa'")))
  ;; Mixed case is lowercased
  (should (equal "term-bdag" (tibetan-vocab-term-anchor "Bdag")))
  ;; Empty / nil / whitespace-only inputs return nil.
  (should (null (tibetan-vocab-term-anchor "")))
  (should (null (tibetan-vocab-term-anchor nil)))
  (should (null (tibetan-vocab-term-anchor "   "))))

(provide 'tibetan-vocab-multisource-test)
;;; tibetan-vocab-multisource-test.el ends here
