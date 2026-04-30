;;; tibetan-enhanced-parser-test.el --- Tests for enhanced parser module -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for tibetan-enhanced-parser.el
;; Tests for:
;; - JSON dictionary loading
;; - Dictionary loading with missing files
;; - Text segmentation by tsheg
;; - Multi-word unit detection
;; - Word unit analysis
;; - Particle function mapping
;; - Verb+nominalizer detection

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-enhanced-parser)
;; Soft-require for the negation-MWU regression tests below — the
;; verb-classifier module populates `tibetan-verb-database' at load
;; time so `tibetan-verb-lookup' can answer Hill-DB queries.
(require 'tibetan-verb-classifier nil t)
;; The negation-MWU integration tests below exercise the MWU finder
;; against real Steinert data; soft-require the loaders so Steinert
;; lookups answer in batch mode when the SQLite DB is present.
;; Tests gate themselves on `tibetan-steinert-available-p' and
;; skip cleanly when the DB isn't reachable (CI / fresh checkout).
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../data" dir)))
(require 'tibetan-glossary-loader nil t)
(require 'tibetan-steinert nil t)

(defun tibetan-enhanced-parser-test--steinert-ready-p ()
  "t when the Steinert SQLite DB is available for live MWU lookups."
  (and (fboundp 'tibetan-steinert-available-p)
       (tibetan-steinert-available-p)))

;; ============================================================================
;; DICTIONARY LOADING TESTS
;; ============================================================================

(ert-deftest tibetan-load-json-dict-missing-file ()
  "Test that missing file returns nil gracefully."
  ;; Set data dir to non-existent location
  (let ((tibetan-cat-data-dir "/nonexistent/path"))
    (let ((result (tibetan-load-json-dict "data/missing.json")))
      (should-not result))))

(ert-deftest tibetan-load-json-dict-returns-hash-or-nil ()
  "Test that function returns hash table or nil."
  (let ((result (tibetan-load-json-dict "nonexistent.json")))
    ;; Should return nil for missing files
    (should (or (null result)
                (hash-table-p result)))))

(ert-deftest tibetan-load-dictionaries-creates-hashes ()
  "Test that load-dictionaries initializes hash tables."
  ;; Clear the dictionaries first
  (setq tibetan-compounds-dict nil)
  (setq tibetan-proper-nouns-dict nil)

  ;; Load dictionaries
  (tibetan-load-dictionaries)

  ;; Both should be hash tables now
  (should (hash-table-p tibetan-compounds-dict))
  (should (hash-table-p tibetan-proper-nouns-dict)))

(ert-deftest tibetan-load-dictionaries-idempotent ()
  "Test that calling load-dictionaries multiple times is safe."
  ;; First call
  (tibetan-load-dictionaries)
  (let ((count1 (hash-table-count tibetan-compounds-dict)))
    ;; Second call
    (tibetan-load-dictionaries)
    (let ((count2 (hash-table-count tibetan-compounds-dict)))
      ;; Counts should be the same (idempotent)
      (should (= count1 count2)))))

;; ============================================================================
;; TEXT SEGMENTATION TESTS
;; ============================================================================

(ert-deftest tibetan-segment-text-basic ()
  "Test basic text segmentation by tsheg."
  (let ((result (tibetan-segment-text "བྱང་ཆུབ་སེམས་དཔའ།")))
    (should result)
    (should (listp result))
    (should (> (length result) 0))))

(ert-deftest tibetan-segment-text-removes-punctuation ()
  "Test that punctuation is stripped during segmentation."
  (let ((result (tibetan-segment-text "བྱང་ཆུབ་སེམས་དཔའ།༎༏")))
    (should result)
    ;; Each element should be Tibetan syllables without punctuation
    (dolist (word result)
      (should-not (string-match-p "[།༎༏༐༑༔]" word)))))

(ert-deftest tibetan-segment-text-single-word ()
  "Test segmentation of single word."
  (let ((result (tibetan-segment-text "བོད")))
    (should result)
    (should (= 1 (length result)))
    (should (equal "བོད" (car result)))))

(ert-deftest tibetan-segment-text-multi-word ()
  "Test segmentation of multi-word phrase."
  (let ((result (tibetan-segment-text "བྱང་ཆུབ་སེམས་དཔའ།")))
    (should result)
    (should (= 4 (length result)))
    (should (equal "བྱང" (nth 0 result)))
    (should (equal "ཆུབ" (nth 1 result)))
    (should (equal "སེམས" (nth 2 result)))
    (should (equal "དཔའ" (nth 3 result)))))

(ert-deftest tibetan-segment-text-empty-input ()
  "Test segmentation of empty string."
  (let ((result (tibetan-segment-text "")))
    (should (or (null result) (listp result)))))

;; ============================================================================
;; MULTI-WORD UNIT DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-find-multiword-units-returns-list ()
  "Test that multiword unit detection returns a list."
  (let ((words (tibetan-segment-text "བྱང་ཆུབ་སེམས་དཔའ།")))
    (let ((result (tibetan-find-multiword-units words)))
      (should (listp result)))))

(ert-deftest tibetan-find-multiword-units-empty-list ()
  "Test with no matches."
  (let ((words (tibetan-segment-text "བོད་")))
    (let ((result (tibetan-find-multiword-units words)))
      ;; Should return a list (possibly empty)
      (should (listp result)))))

(ert-deftest tibetan-find-multiword-units-structure ()
  "Test structure of returned units."
  (let ((words '("གླེང" "གཞི")))
    (let ((result (tibetan-find-multiword-units words)))
      (should (listp result))
      ;; Each match should be a list with (start end joined-form data)
      (dolist (unit result)
        (should (listp unit))
        (should (>= (length unit) 3))
        (should (numberp (nth 0 unit)))  ; start index
        (should (numberp (nth 1 unit)))  ; end index
        (should (stringp (nth 2 unit)))))))  ; joined form

;; ============================================================================
;; Negation + Hill-DB-verb MWU rejection (uddāna seg-008 regression)
;; ============================================================================
;;
;; Live test on gotrapatala.org seg-008 (`སྤྱོད་དང་རབ་གནས་ཐ་མ་ཡིན་༎')
;; surfaced a verb-extraction failure: the copula `ཡིན' (Hill-DB-
;; attested copula `to be (equative)') was missing from the verb
;; list.  Root cause: the MWU finder bundled `མ་ཡིན' (Steinert
;; gloss `is not; not being') as a 2-syllable MWU at positions 5-7,
;; which:
;;   1. Made `ཡིན' look covered-by-MWU to the verb extractor.
;;   2. The MWU's `is not' gloss didn't match
;;      `tibetan-clause-seg--mwu-verbal-p' (no leading `to X' / `verb'
;;      / Sanskrit absolutive marker), so step 2 of the verb
;;      extractor also skipped it.
;;   3. `ཡིན' was thus invisible to verb extraction.
;;
;; In the live segment, `མ' grammatically belongs to `ཐ་མ' (`tha
;; ma' = `last/final'), NOT to `ཡིན'.  But even when `མ' IS the
;; negation (e.g. `སྨྲས་ པ་མ་ཡིན' = `did not say'), the verb
;; extractor's `prev-word-negates-p' logic already handles the
;; pattern correctly when `མ' and the verb are SEPARATE words —
;; bundling them as an MWU only hides the verb.
;;
;; Fix scope: the MWU finder rejects 2-syllable Steinert candidates
;; whose head is `མ' / `མི' AND tail is a Hill-DB-attested verb.
;; This frees the verb extractor to handle them via the negation
;; mechanism it already has.

(ert-deftest tibetan-mwu-finder-rejects-ma-yin-bundle ()
  "`tibetan-find-multiword-units' must NOT bundle `མ་ཡིན' as a
2-syllable MWU when `ཡིན' is a Hill-DB-attested verb.  Letting
the MWU win hides the copula from verb extraction.

Steinert-gated — the `མ་ཡིན' candidate only enters the MWU
finder when the Steinert SQLite DB is reachable."
  (skip-unless (fboundp 'tibetan-find-multiword-units))
  (skip-unless (fboundp 'tibetan-verb-lookup))
  (skip-unless (tibetan-enhanced-parser-test--steinert-ready-p))
  ;; Sanity: `ཡིན' must be in Hill-DB for the test premise to hold.
  (skip-unless (tibetan-verb-lookup "ཡིན"))
  (let* ((words '("སྨྲས" "པ" "མ" "ཡིན"))
         (mwus (tibetan-find-multiword-units words)))
    (should-not
     (cl-find-if (lambda (m)
                   (and (listp m) (>= (length m) 3)
                        (string= (nth 2 m) "མ་ཡིན")))
                 mwus))))

(ert-deftest tibetan-mwu-finder-rejects-mi-yin-bundle ()
  "Analogous to `མ་ཡིན': `མི་ཡིན' must not be bundled either —
the negation mechanism handles `མི' + verb correctly when they
are separate words.

Steinert-gated."
  (skip-unless (fboundp 'tibetan-find-multiword-units))
  (skip-unless (fboundp 'tibetan-verb-lookup))
  (skip-unless (tibetan-enhanced-parser-test--steinert-ready-p))
  (skip-unless (tibetan-verb-lookup "ཡིན"))
  (let* ((words '("བདག" "མི" "ཡིན"))
         (mwus (tibetan-find-multiword-units words)))
    (should-not
     (cl-find-if (lambda (m)
                   (and (listp m) (>= (length m) 3)
                        (string= (nth 2 m) "མི་ཡིན")))
                 mwus))))

(ert-deftest tibetan-mwu-finder-tha-ma-found-when-followed-by-yin ()
  "Direct consequence of the `མ་ཡིན'-rejection: in the seg-008
sequence `…ཐ་མ་ཡིན…', the MWU finder is now free to take
`ཐ་མ' (`tha ma' = `last') at i=4 because `མ་ཡིན' at i+1=5 is
no longer a competing Steinert candidate.

Before this fix, the shadow-check rejected `ཐ་མ' in favour of
the (about-to-be-found) `མ་ཡིན'; with `མ་ཡིན' rejected,
`ཐ་མ' wins.

Steinert-gated — both candidates are Steinert hits."
  (skip-unless (fboundp 'tibetan-find-multiword-units))
  (skip-unless (tibetan-enhanced-parser-test--steinert-ready-p))
  (let* ((words '("སྤྱོད" "དང" "རབ" "གནས" "ཐ" "མ" "ཡིན"))
         (mwus (tibetan-find-multiword-units words)))
    (should
     (cl-find-if (lambda (m)
                   (and (listp m) (>= (length m) 3)
                        (string= (nth 2 m) "ཐ་མ")))
                 mwus))))

(ert-deftest tibetan-mwu-finder-negation-predicate-recognises-ma-yin ()
  "`tibetan-enhanced-parser--negation-plus-hill-verb-p' recognises
`མ་ཡིན' / `མི་ཡིན' / `མ་བྱེད' (negation of Hill-DB verbs) and
returns nil for non-negation forms or non-Hill-DB second
syllables."
  (skip-unless (fboundp 'tibetan-enhanced-parser--negation-plus-hill-verb-p))
  (skip-unless (fboundp 'tibetan-verb-lookup))
  ;; Hill-DB verb under negation — should match.
  (when (tibetan-verb-lookup "ཡིན")
    (should (tibetan-enhanced-parser--negation-plus-hill-verb-p "མ་ཡིན"))
    (should (tibetan-enhanced-parser--negation-plus-hill-verb-p "མི་ཡིན")))
  (when (tibetan-verb-lookup "བྱེད")
    (should (tibetan-enhanced-parser--negation-plus-hill-verb-p "མ་བྱེད"))
    (should (tibetan-enhanced-parser--negation-plus-hill-verb-p "མི་བྱེད")))
  ;; Not a 2-syllable form, head not negation, or tail not Hill-DB —
  ;; should NOT match.
  (should-not (tibetan-enhanced-parser--negation-plus-hill-verb-p "བདག"))
  (should-not (tibetan-enhanced-parser--negation-plus-hill-verb-p "ཐ་མ"))
  (should-not (tibetan-enhanced-parser--negation-plus-hill-verb-p "མ་ཐ"))
  ;; Three syllables — out of scope.
  (should-not
   (tibetan-enhanced-parser--negation-plus-hill-verb-p "མ་ཡིན་པ")))

;; ============================================================================
;; WORD UNIT ANALYSIS TESTS
;; ============================================================================

(ert-deftest tibetan-analyze-word-unit-simple-word ()
  "Test analysis of simple word without particles."
  (let ((result (tibetan-analyze-word-unit "བོད" nil nil)))
    (should result)
    (should (alist-get 'type result))))

(ert-deftest tibetan-analyze-word-unit-genitive ()
  "Test analysis of genitive construction."
  (let ((result (tibetan-analyze-word-unit "བོདགི" nil nil)))
    (should result)
    (should (equal "word+genitive" (alist-get 'type result)))
    (should (alist-get 'particle result))))

(ert-deftest tibetan-analyze-word-unit-nominalizer ()
  "Test analysis of nominalized verb."
  (let ((result (tibetan-analyze-word-unit "སྨྲསཔ" nil nil)))
    (should result)
    (should (equal "word+nominalizer" (alist-get 'type result)))
    (should (alist-get 'particle result))))

(ert-deftest tibetan-analyze-word-unit-case-particle ()
  "Test analysis of standalone case particle."
  (let ((result (tibetan-analyze-word-unit "ན" nil nil)))
    (should result)
    (should (equal "case_particle" (alist-get 'type result)))
    (should (alist-get 'particle result))))

(ert-deftest tibetan-analyze-word-unit-preserves-context ()
  "Test that context words are accepted."
  (let ((result (tibetan-analyze-word-unit "བོད" "སངས་རྒྱས་" "ཀྱི")))
    (should result)
    ;; Should handle context gracefully
    (should (alist-get 'type result))))

;; ============================================================================
;; PARTICLE FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-particle-function-locative ()
  "Test locative particle (ན)."
  (let ((result (tibetan-particle-function "ན")))
    (should (stringp result))
    (should (string-match-p "locative" result))))

(ert-deftest tibetan-particle-function-dative ()
  "Test dative particle (ལ)."
  (let ((result (tibetan-particle-function "ལ")))
    (should (stringp result))
    (should (string-match-p "dative" result))))

(ert-deftest tibetan-particle-function-ablative ()
  "Test ablative particles (ནས/ལས)."
  (let ((result1 (tibetan-particle-function "ནས"))
        (result2 (tibetan-particle-function "ལས")))
    (should (stringp result1))
    (should (stringp result2))
    (should (string-match-p "ablative" result1))
    (should (string-match-p "ablative" result2))))

(ert-deftest tibetan-particle-function-comitative ()
  "Test comitative particle (དང)."
  (let ((result (tibetan-particle-function "དང")))
    (should (stringp result))
    (should (string-match-p "comitative" result))))

(ert-deftest tibetan-particle-function-terminative ()
  "Test terminative particles (ར/དུ/ཏུ)."
  (let ((result1 (tibetan-particle-function "ར"))
        (result2 (tibetan-particle-function "དུ")))
    (should (stringp result1))
    (should (stringp result2))
    (should (string-match-p "terminative" result1))
    (should (string-match-p "terminative" result2))))

(ert-deftest tibetan-particle-function-unknown ()
  "Test unknown particle returns generic description."
  (let ((result (tibetan-particle-function "unknown")))
    (should (stringp result))
    (should (string-match-p "particle" result))))

;; ============================================================================
;; VERB+NOMINALIZER DETECTION TESTS
;; ============================================================================

(ert-deftest tibetan-find-verb-nominalizer-units-returns-list ()
  "Test that verb+nominalizer detection returns a list."
  (let ((words '("སྨྲ" "པ")))
    (let ((result (tibetan-find-verb-nominalizer-units words)))
      (should (listp result)))))

(ert-deftest tibetan-find-verb-nominalizer-units-empty ()
  "Test with non-verb words."
  (let ((words '("བོད" "ི")))
    (let ((result (tibetan-find-verb-nominalizer-units words)))
      ;; Should return a list (possibly empty if verb classifier unavailable)
      (should (listp result)))))

(ert-deftest tibetan-find-verb-nominalizer-units-structure ()
  "Test structure of returned units."
  (let ((words '("སྨྲས" "པ" "གཞན" "དག")))
    (let ((result (tibetan-find-verb-nominalizer-units words)))
      (should (listp result))
      ;; Each match should have required fields
      (dolist (unit result)
        (should (listp unit))
        (should (>= (length unit) 2))))))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-segment-and-analyze-integration ()
  "Test full pipeline: segment then analyze."
  (let* ((text "བྱང་ཆུབ་སེམས་དཔའ།")
         (words (tibetan-segment-text text)))
    (should words)
    (should (> (length words) 0))

    ;; Should be able to analyze each word
    (dolist (word words)
      (let ((analysis (tibetan-analyze-word-unit word nil nil)))
        (should analysis)
        (should (alist-get 'type analysis))))))

(ert-deftest tibetan-parser-with-realistic-tibetan ()
  "Test parser with realistic Tibetan text."
  (let* ((text "སངས་རྒྱས་བྱང་ཆུབ་སེམས་དཔའ་དེ་དག")
         (words (tibetan-segment-text text)))
    (should (listp words))
    (should (> (length words) 0))

    ;; Spot check: first word should be "སངས"
    (should (string-match-p "སངས" (car words)))))

;; ============================================================================
;; ENHANCED PARSE TESTS
;; ============================================================================

(ert-deftest tibetan-parse-enhanced-nil-input ()
  "Test enhanced parser with nil input."
  (skip-unless (fboundp 'tibetan-parse-enhanced))
  (let ((result (tibetan-parse-enhanced nil)))
    (should (or (null result) (alist-get 'words result)))))

(ert-deftest tibetan-parse-enhanced-empty-string ()
  "Test enhanced parser with empty string.
Returns nil for empty input, same as nil input."
  (skip-unless (fboundp 'tibetan-parse-enhanced))
  (let ((result (tibetan-parse-enhanced "")))
    (should (or (null result) (alist-get 'words result)))))

(ert-deftest tibetan-parse-enhanced-returns-structure ()
  "Test that enhanced parser returns structured analysis.
`multiword-units' may be legitimately empty (e.g. for input
without compounds or verb+nominalizer constructions), so we
assert the key is present in the result rather than that its
value is truthy."
  (skip-unless (fboundp 'tibetan-parse-enhanced))
  (let ((result (tibetan-parse-enhanced "བདག་གིས")))
    (should result)
    (should (alist-get 'words result))
    (should (alist-get 'analysis result))
    (should (assq 'multiword-units result))))

(ert-deftest tibetan-parse-enhanced-segments-tibetan-text ()
  "Test enhanced parser segments Tibetan text correctly."
  (skip-unless (fboundp 'tibetan-parse-enhanced))
  (let ((result (tibetan-parse-enhanced "བྱང་ཆུབ་སེམས་དཔའ")))
    (should result)
    (let ((words (alist-get 'words result)))
      (should (listp words))
      (should (> (length words) 0)))))

(provide 'tibetan-enhanced-parser-test)

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(ert-deftest tibetan-enhanced-parser-mwu-includes-resources-vocab ()
  "`tibetan-find-multiword-units' must consult the per-document
`tibetan-current-resources-vocab' so user-supplied compound entries
(e.g. `ཆུང་མ་བྱེད') reach the parser's `multiword-units' output.
Otherwise downstream MWU-aware logic in the verb extractor and
clause segmenter has nothing to consult and the user's wordlist
silently fails to influence parsing."
  (let ((tibetan-current-resources-vocab
         (let ((h (make-hash-table :test 'equal)))
           (puthash "ཆུང་མ་བྱེད" "to become the wife of" h)
           h))
        (tibetan-current-custom-vocab nil))
    (cl-letf (((symbol-function 'tibetan-load-resources-vocab) (lambda () nil))
              ((symbol-function 'tibetan-load-custom-vocab) (lambda () nil)))
      (let* ((mwus (tibetan-find-multiword-units '("ཆུང" "མ" "བྱེད")))
             (chung (cl-find-if (lambda (m) (string= (nth 2 m) "ཆུང་མ་བྱེད"))
                                mwus)))
        (should chung)
        (should (= (nth 0 chung) 0))
        (should (= (nth 1 chung) 3))
        (let ((data (nth 3 chung)))
          (should (string= (alist-get 'english data)
                           "to become the wife of"))
          (should (string= (alist-get 'category data) "resources")))))))

(ert-deftest tibetan-enhanced-parser-mwu-includes-steinert-only ()
  "`tibetan-find-multiword-units' also consults Steinert so compounds
like `ནམ་ཞིག' / `ཀློག་སློབ' that live only in Steinert reach
`multiword-units'.  This keeps the parser in sync with
`tibetan-extract-vocabulary' (the Word/Particle List path), which
already finds them through `tibetan-lookup-word'."
  (cl-letf (((symbol-function 'tibetan-load-resources-vocab) (lambda () nil))
            ((symbol-function 'tibetan-load-custom-vocab) (lambda () nil))
            ((symbol-function 'tibetan-lookup-word-in-steinert)
             (lambda (w)
               (when (string= w "ནམ་ཞིག") "at the time"))))
    (let ((tibetan-current-resources-vocab nil)
          (tibetan-current-custom-vocab nil))
      (let* ((mwus (tibetan-find-multiword-units '("ནམ" "ཞིག" "X")))
             (nam-zhig (cl-find-if (lambda (m) (string= (nth 2 m) "ནམ་ཞིག"))
                                   mwus)))
        (should nam-zhig)
        (should (= (nth 0 nam-zhig) 0))
        (should (= (nth 1 nam-zhig) 2))
        (let ((data (nth 3 nam-zhig)))
          (should (string= (alist-get 'english data) "at the time"))
          (should (string= (alist-get 'category data) "steinert")))))))

(defun tibetan-enhanced-parser-run-tests ()
  "Run all enhanced parser tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-enhanced-parser-"))

;;; tibetan-enhanced-parser-test.el ends here
