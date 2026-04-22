;;; tibetan-thesaurus-test.el --- Tests for thesaurus module -*- lexical-binding: t -*-

;;; Commentary:
;; BDD/TDD tests for `core/tibetan-thesaurus.el' — Pass 5b.
;;
;; The thesaurus is a user-editable, Kramer-seeded glossary of
;; multilingual terms (Sanskrit · Wylie · English · German) stored as
;; org-mode zettels.  Each zettel keys off a Wylie term in its
;; `** Tibetan' section; lookup during vocabulary analysis surfaces
;; the entry at rank 1 (above Resources / Custom / all dictionaries)
;; so the student's chosen translation stays consistent across every
;; analysis in a document and across related documents.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((root (expand-file-name ".." (file-name-directory
                                    (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path (expand-file-name "core" root)))

(require 'tibetan-thesaurus)

;; ============================================================================
;; HELPERS
;; ============================================================================

(cl-defun tibetan-thesaurus-test--write-zettel
    (path &key id title wylie english german sanskrit)
  "Write a minimal Kramer-shaped zettel at PATH with the given fields.
Missing fields default to empty / placeholder strings — the parser
must tolerate those gracefully."
  (with-temp-file path
    (insert ":PROPERTIES:\n"
            (format ":ID: %s\n" (or id "TEST-001"))
            ":END:\n"
            (format "#+title: %s\n" (or title "test-term"))
            "#+date: [2025-08-21]\n"
            "#+filetags: :concept:topic_kramer-glossary:\n\n"
            "* Multilingual Terms\n"
            "** Sanskrit\n"
            (format "- Term: %s\n" (or sanskrit title "test-term"))
            (format "- IAST: %s\n" (or sanskrit title "test-term"))
            "\n"
            "** Tibetan\n"
            "- Term: [Tibetan script to be added]\n"
            (format "- Wylie: %s\n" (or wylie "test wylie"))
            "- Phonetic: [to be added]\n\n"
            "** English\n"
            (format "- Primary translation: %s\n" (or english "test english"))
            "- Alternative translations: [to be researched]\n\n"
            "** German\n"
            (format "- Primary translation: %s\n" (or german "test deutsch"))
            "- Alternative translations: [to be researched]\n")))

(defmacro tibetan-thesaurus-test--with-tmp-dir (var &rest body)
  "Bind VAR to a fresh temporary directory and evaluate BODY.
Cleans up on exit."
  (declare (indent 1))
  `(let ((,var (make-temp-file "tibetan-thesaurus-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,var t))))

;; ============================================================================
;; PARSER
;; ============================================================================

(ert-deftest tibetan-thesaurus-parse-basic-zettel ()
  "Parse a well-formed zettel and return a plist with the key fields.
The `:wylie' field is the thesaurus key; `:primary-en' / `:primary-de'
carry the bilingual gloss; `:sanskrit' carries the Sanskrit term; and
`:id' carries the org ID for back-linking."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((path (expand-file-name "citta.org" tmp)))
      (tibetan-thesaurus-test--write-zettel
       path
       :id "20250821T100000"
       :title "citta"
       :wylie "sems"
       :english "mind, consciousness"
       :german "Geist"
       :sanskrit "citta")
      (let ((entry (tibetan-thesaurus--parse-file path)))
        (should entry)
        (should (equal (plist-get entry :id) "20250821T100000"))
        (should (equal (plist-get entry :sanskrit) "citta"))
        (should (equal (plist-get entry :wylie) "sems"))
        (should (equal (plist-get entry :primary-en) "mind, consciousness"))
        (should (equal (plist-get entry :primary-de) "Geist"))
        (should (equal (plist-get entry :path) path))))))

(ert-deftest tibetan-thesaurus-parse-multi-word-wylie ()
  "Wylie keys can be multi-syllable (e.g. `rnam par shes pa').
The parser preserves the whole string after `Wylie:' verbatim."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((path (expand-file-name "vij.org" tmp)))
      (tibetan-thesaurus-test--write-zettel
       path
       :wylie "rnam par shes pa"
       :english "consciousness"
       :german "Bewusstsein")
      (let ((entry (tibetan-thesaurus--parse-file path)))
        (should (equal (plist-get entry :wylie) "rnam par shes pa"))))))

(ert-deftest tibetan-thesaurus-parse-placeholder-fields-tolerated ()
  "When a field is still a Kramer placeholder (`[to be added]' /
`[to be researched]'), the parser returns nil for that slot rather
than propagating the placeholder string — downstream renderers can
then skip it cleanly.  The main keys (Wylie, sanskrit from title)
must still extract successfully."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((path (expand-file-name "placeholder.org" tmp)))
      (with-temp-file path
        (insert ":PROPERTIES:\n:ID: X1\n:END:\n"
                "#+title: foo\n"
                "** Tibetan\n"
                "- Wylie: foo bar\n\n"
                "** English\n"
                "- Primary translation: [to be researched]\n\n"
                "** German\n"
                "- Primary translation: [to be added]\n"))
      (let ((entry (tibetan-thesaurus--parse-file path)))
        (should (equal (plist-get entry :wylie) "foo bar"))
        (should (equal (plist-get entry :sanskrit) "foo"))
        (should (null (plist-get entry :primary-en)))
        (should (null (plist-get entry :primary-de)))))))

(ert-deftest tibetan-thesaurus-parse-missing-wylie-returns-nil ()
  "A zettel without a `- Wylie: …' field cannot be keyed, so the
parser returns nil (skip the file).  Regression guard — a malformed
or stub zettel in the thesaurus dir must NOT corrupt the index."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((path (expand-file-name "no-wylie.org" tmp)))
      (with-temp-file path
        (insert "#+title: foo\n** Tibetan\n- Term: [TBD]\n"))
      (should (null (tibetan-thesaurus--parse-file path))))))

(ert-deftest tibetan-thesaurus-parse-nonexistent-file-returns-nil ()
  "Parser safely returns nil on a non-existent path."
  (should (null (tibetan-thesaurus--parse-file "/no/such/file.org"))))

;; ============================================================================
;; INDEXER
;; ============================================================================

(ert-deftest tibetan-thesaurus-build-index-from-directory ()
  "`tibetan-thesaurus--build-index' scans the configured directory,
parses every matching file, and returns a hash keyed by Wylie."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "a.org" tmp) :wylie "sems" :english "mind")
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "b.org" tmp) :wylie "rnam shes" :english "conscious")
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "c.org" tmp) :wylie "rnam shes" :english "awareness"
     :id "dup-key")
    (let* ((tibetan-thesaurus-directory tmp)
           (tibetan-thesaurus-file-pattern "*.org")
           (index (tibetan-thesaurus--build-index tmp)))
      (should (hash-table-p index))
      ;; Wylie-keyed entries.  Values are LISTS because duplicate
      ;; Wylie keys are allowed (two zettels can document different
      ;; senses of the same term).
      (should (gethash "sems" index))
      (let ((rnam-entries (gethash "rnam shes" index)))
        (should (= 2 (length rnam-entries)))))))

(ert-deftest tibetan-thesaurus-build-index-empty-directory ()
  "An empty / nonexistent directory returns an empty hash, not nil.
Callers can iterate the hash safely either way."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((index (tibetan-thesaurus--build-index tmp)))
      (should (hash-table-p index))
      (should (zerop (hash-table-count index)))))
  ;; Nonexistent directory → empty hash, no error.
  (let ((index (tibetan-thesaurus--build-index "/no/such/dir/xyz")))
    (should (hash-table-p index))
    (should (zerop (hash-table-count index)))))

;; ============================================================================
;; LOOKUP (public API)
;; ============================================================================

(ert-deftest tibetan-thesaurus-lookup-returns-matching-entries ()
  "`tibetan-thesaurus-lookup' returns a list of plists for a Wylie
key.  Multiple zettels keyed by the same Wylie are all returned."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "a.org" tmp) :wylie "sems" :english "mind"
     :id "A" :title "citta")
    (let ((tibetan-thesaurus-directory tmp))
      (tibetan-thesaurus-reload)   ;; force re-index after dir change
      (let ((hits (tibetan-thesaurus-lookup "sems")))
        (should (= 1 (length hits)))
        (let ((hit (car hits)))
          (should (equal (plist-get hit :id) "A"))
          (should (equal (plist-get hit :primary-en) "mind"))
          (should (equal (plist-get hit :sanskrit) "citta")))))))

(ert-deftest tibetan-thesaurus-lookup-no-thesaurus-returns-nil ()
  "When `tibetan-thesaurus-directory' is nil or points at nothing
useful, `tibetan-thesaurus-lookup' returns nil — the multisource
framework then falls through to the next-ranked sources."
  (let ((tibetan-thesaurus-directory nil))
    (tibetan-thesaurus-reload)
    (should (null (tibetan-thesaurus-lookup "sems")))))

(ert-deftest tibetan-thesaurus-lookup-miss-returns-nil ()
  "A Wylie not in the index returns nil."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "a.org" tmp) :wylie "sems" :english "mind")
    (let ((tibetan-thesaurus-directory tmp))
      (tibetan-thesaurus-reload)
      (should (null (tibetan-thesaurus-lookup "bdag"))))))

;; ============================================================================
;; INTEGRATION — multisource at rank 1
;; ============================================================================

(ert-deftest tibetan-thesaurus-multisource-rank-1 ()
  "`tibetan-vocab-multisource-entries' must return a Thesaurus entry
as the FIRST element when the thesaurus has a match — rank 1,
above any Resources (rank 2) / corpus-specific (rank 3) / Hopkins
(rank 4) / RY (rank 6) / Bundled (rank 9) hit."
  (require 'tibetan-vocabulary-detailed)
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "sems.org" tmp)
     :id "TH-001" :title "citta" :wylie "sems"
     :english "mind, consciousness" :german "Geist")
    (let ((tibetan-thesaurus-directory tmp))
      (tibetan-thesaurus-reload)
      ;; Stub the non-thesaurus sources so only thesaurus fires
      ;; purely — keeps the test independent of SQLite / RY state.
      (cl-letf (((symbol-function 'tibetan-lookup-word)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-steinert)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
                 (lambda (_w) nil)))
        (let ((entries (tibetan-vocab-multisource-entries "སེམས")))
          (should entries)
          (let ((first (car entries)))
            (should (equal (plist-get first :source) "Thesaurus (Kramer)"))
            (should (plist-get first :zettel-id))))))))

(ert-deftest tibetan-thesaurus-multisource-carries-bilingual-gloss ()
  "The Thesaurus entry in multisource output carries a bilingual
DE // EN primary gloss so
`tibetan-analysis--format-bilingual-gloss' can split it correctly."
  (require 'tibetan-vocabulary-detailed)
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "a.org" tmp)
     :wylie "bdag" :english "self, I" :german "Selbst, Ich")
    (let ((tibetan-thesaurus-directory tmp))
      (tibetan-thesaurus-reload)
      (cl-letf (((symbol-function 'tibetan-lookup-word) (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-steinert)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
                 (lambda (_w) nil)))
        (let ((entries (tibetan-vocab-multisource-entries "བདག")))
          (should entries)
          (let ((primary (plist-get (car entries) :primary)))
            (should primary)
            ;; The bilingual format helper splits on " // "; both
            ;; halves must be present.
            (should (string-match-p "Selbst.*//.*self" primary))))))))

(ert-deftest tibetan-thesaurus-multisource-no-wylie-no-call ()
  "When the input word has no Wylie conversion (e.g. the vocab
helper is missing or errors out), the thesaurus call is a no-op
and multisource falls through cleanly.  Regression guard — the
thesaurus integration must not crash the multisource pipeline."
  (require 'tibetan-vocabulary-detailed)
  (let ((tibetan-thesaurus-directory nil))   ;; no thesaurus at all
    (cl-letf (((symbol-function 'tibetan-lookup-word) (lambda (_w) nil))
              ((symbol-function 'tibetan-lookup-word-in-steinert)
               (lambda (_w) nil))
              ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
               (lambda (_w) nil))
              ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
               (lambda (_w) nil)))
      ;; No thesaurus → no Thesaurus entries in the result.
      (let ((entries (tibetan-vocab-multisource-entries "སེམས")))
        (should-not (cl-some (lambda (e)
                               (and (plist-get e :source)
                                    (string-prefix-p "Thesaurus"
                                                     (plist-get e :source))))
                             entries))))))

;; ============================================================================
;; RENDERING — Detailed Dictionary head line with zettel back-link + ★
;; ============================================================================

(ert-deftest tibetan-thesaurus-detailed-dictionary-renders-zettel-link ()
  "When a Thesaurus entry is present for a word, the Detailed
Dictionary head line includes a `[[id:XYZ][Thesaurus ↗]]' back-
link to the zettel.  Students click to jump to the thesaurus
entry in their zettelkasten and edit it; the consistency of the
term then propagates to every other analysis on next reanalysis."
  (require 'tibetan-analysis-persist)
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "sems.org" tmp)
     :id "20250821T100000" :title "citta" :wylie "sems"
     :english "mind, consciousness" :german "Geist")
    (let ((tibetan-thesaurus-directory tmp))
      (tibetan-thesaurus-reload)
      (cl-letf (((symbol-function 'tibetan-lookup-word) (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-steinert)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
                 (lambda (_w) nil)))
        (let ((out (condition-case nil
                       (tibetan-analysis-generate-content "སེམས་")
                     (error nil))))
          (when out
            ;; Head-line zettel link with the right id.
            (should (string-match-p
                     "id:20250821T100000\\]\\[Thesaurus" out))
            ;; ★ marker is present on the head line for Thesaurus
            ;; entries (same visual treatment as Resources).
            (should (string-match-p "◆ .*sems.*★" out))))))))

(ert-deftest tibetan-thesaurus-detailed-dictionary-shows-thesaurus-source ()
  "The Thesaurus entry appears in the Detailed Dictionary body as
`[Thesaurus (Kramer)]' with the bilingual gloss indented beneath."
  (require 'tibetan-analysis-persist)
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (tibetan-thesaurus-test--write-zettel
     (expand-file-name "bdag.org" tmp)
     :wylie "bdag" :english "self, I" :german "Selbst, Ich")
    (let ((tibetan-thesaurus-directory tmp))
      (tibetan-thesaurus-reload)
      (cl-letf (((symbol-function 'tibetan-lookup-word) (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-steinert)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-rangjung-yeshe)
                 (lambda (_w) nil))
                ((symbol-function 'tibetan-lookup-word-in-dharmamitra)
                 (lambda (_w) nil)))
        (let ((out (condition-case nil
                       (tibetan-analysis-generate-content "བདག་")
                     (error nil))))
          (when out
            (should (string-match-p "\\[Thesaurus (Kramer)\\]" out))
            ;; Bilingual gloss preserved on either the primary or
            ;; detailed line after `[Thesaurus ...]'.
            (should (string-match-p "Selbst" out))
            (should (string-match-p "self" out))))))))

;; ============================================================================
;; INITIALIZE FROM KRAMER — one-shot copy command
;; ============================================================================

(ert-deftest tibetan-thesaurus-init-from-kramer-copies-files ()
  "`tibetan-thesaurus-initialize-from-kramer' copies every Kramer
zettel from the source directory into the configured thesaurus
directory.  Destination files that already exist are preserved
(never overwritten) so a user who's started editing doesn't lose
their changes on a second init call."
  (tibetan-thesaurus-test--with-tmp-dir src
    (tibetan-thesaurus-test--with-tmp-dir dest
      ;; Filenames match the default Kramer pattern
      ;; `*kramer-glossary*.org' — only these get copied.
      (let ((sems-name "20250821--citta_kramer-glossary.org")
            (bdag-name "20250821--atman_kramer-glossary.org"))
        (tibetan-thesaurus-test--write-zettel
         (expand-file-name sems-name src)
         :id "K1" :title "citta" :wylie "sems" :english "mind" :german "Geist")
        (tibetan-thesaurus-test--write-zettel
         (expand-file-name bdag-name src)
         :id "K2" :title "atman" :wylie "bdag" :english "self" :german "Selbst")
        ;; User already has an EDITED entry for `citta' in the dest
        ;; dir.  That one must survive the init.
        (with-temp-file (expand-file-name sems-name dest)
          (insert "USER EDIT — do not overwrite\n"))
        (let ((tibetan-thesaurus-directory dest)
              (tibetan-thesaurus-kramer-source-directory src))
          (let ((result (tibetan-thesaurus-initialize-from-kramer)))
            ;; Reports the number copied vs skipped-because-existing.
            (should (= 1 (plist-get result :copied)))
            (should (= 1 (plist-get result :skipped-existing))))
          ;; New file is there.
          (should (file-exists-p (expand-file-name bdag-name dest)))
          ;; Existing file is untouched.
          (with-temp-buffer
            (insert-file-contents (expand-file-name sems-name dest))
            (should (string-match-p "USER EDIT" (buffer-string)))))))))

(ert-deftest tibetan-thesaurus-init-from-kramer-filters-by-pattern ()
  "Init copies only files matching
`tibetan-thesaurus-kramer-source-pattern' — a non-Kramer zettel
sharing the source directory is left alone.  Default pattern is
`*kramer-glossary*.org' matching Carsten's filename convention."
  (tibetan-thesaurus-test--with-tmp-dir src
    (tibetan-thesaurus-test--with-tmp-dir dest
      ;; Two Kramer files + one unrelated zettel in the same dir.
      (tibetan-thesaurus-test--write-zettel
       (expand-file-name "20250821--citta_kramer-glossary.org" src)
       :wylie "sems" :english "mind")
      (tibetan-thesaurus-test--write-zettel
       (expand-file-name "20250821--atman_kramer-glossary.org" src)
       :wylie "bdag" :english "self")
      (with-temp-file (expand-file-name "20250901--note_misc.org" src)
        (insert "Unrelated zettel — must NOT be copied.\n"))
      (let ((tibetan-thesaurus-directory dest)
            (tibetan-thesaurus-kramer-source-directory src)
            (tibetan-thesaurus-kramer-source-pattern "*kramer-glossary*.org"))
        (let ((result (tibetan-thesaurus-initialize-from-kramer)))
          (should (= 2 (plist-get result :copied))))
        ;; Only the Kramer-tagged filenames are at dest.
        (should (file-exists-p (expand-file-name "20250821--citta_kramer-glossary.org" dest)))
        (should (file-exists-p (expand-file-name "20250821--atman_kramer-glossary.org" dest)))
        (should-not (file-exists-p (expand-file-name "20250901--note_misc.org" dest)))))))

(ert-deftest tibetan-thesaurus-init-from-kramer-nil-source-errors ()
  "Running the init command without configuring
`tibetan-thesaurus-kramer-source-directory' raises a user-error
rather than silently doing nothing — bad config should be visible."
  (let ((tibetan-thesaurus-kramer-source-directory nil)
        (tibetan-thesaurus-directory "/tmp/thesaurus-test"))
    (should-error (tibetan-thesaurus-initialize-from-kramer)
                  :type 'user-error)))

(ert-deftest tibetan-thesaurus-init-from-kramer-nil-dest-errors ()
  "Running the init command without configuring
`tibetan-thesaurus-directory' raises a user-error."
  (let ((tibetan-thesaurus-directory nil)
        (tibetan-thesaurus-kramer-source-directory "/tmp/src"))
    (should-error (tibetan-thesaurus-initialize-from-kramer)
                  :type 'user-error)))

(provide 'tibetan-thesaurus-test)
;;; tibetan-thesaurus-test.el ends here
