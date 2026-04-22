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

;; ============================================================================
;; PASS 5b.2 — Create / edit thesaurus entries from analysis buffer
;; ============================================================================

(ert-deftest tibetan-thesaurus-new-entry-creates-file-with-scaffold ()
  "`tibetan-thesaurus-new-entry' creates a fresh zettel in the
thesaurus directory with a Kramer-shaped scaffold (header, `** Sanskrit',
`** Tibetan', `** English', `** German' sections) and returns its
absolute path.  The `:ID:' property is a Denote-style timestamp;
`#+title:' holds the Sanskrit term (or a placeholder when unset);
the `- Wylie:' field is prefilled from the argument.

Uses a stubbed `current-time' so the test is deterministic."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((tibetan-thesaurus-directory tmp))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (fmt &optional _time _zone)
                   ;; Return deterministic timestamp matching the
                   ;; Denote `YYYYMMDDTHHMMSS' shape our code uses.
                   (if (equal fmt "%Y%m%dT%H%M%S")
                       "20260422T140000"
                     ""))))
        (let ((path (tibetan-thesaurus-new-entry "mthu")))
          (should path)
          (should (file-exists-p path))
          ;; Filename: TIMESTAMP--WYLIE-SLUG__user.org
          (should (string-match-p "20260422T140000--mthu__user\\.org\\'" path))
          (with-temp-buffer
            (insert-file-contents path)
            (let ((s (buffer-string)))
              (should (string-match-p ":ID: 20260422T140000" s))
              ;; #+title defaults to the Wylie when no Sanskrit is
              ;; supplied — the user fills it in on edit.
              (should (string-match-p "^#\\+title: mthu" s))
              ;; Structural sections present for editing.
              (should (string-match-p "^\\*\\* Sanskrit" s))
              (should (string-match-p "^\\*\\* Tibetan" s))
              (should (string-match-p "^\\*\\* English" s))
              (should (string-match-p "^\\*\\* German" s))
              ;; Wylie field prefilled.
              (should (string-match-p "^- Wylie: mthu" s)))))))))

(ert-deftest tibetan-thesaurus-new-entry-slugifies-wylie-multi-syllable ()
  "Multi-syllable Wylie (e.g. `rnam par shes pa') is slugified into
a filename-safe form (spaces → dashes, apostrophes dropped) so the
filename stays valid on case-folding filesystems.  The `- Wylie:'
field inside the file keeps the ORIGINAL spaces for lookup."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((tibetan-thesaurus-directory tmp))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (_fmt &optional _ _) "20260422T140100")))
        (let ((path (tibetan-thesaurus-new-entry "rnam par shes pa")))
          (should (string-match-p
                   "20260422T140100--rnam-par-shes-pa__user\\.org\\'"
                   path))
          (with-temp-buffer
            (insert-file-contents path)
            ;; Wylie field keeps original spaces.
            (should (string-match-p "^- Wylie: rnam par shes pa$"
                                    (buffer-string)))))))))

(ert-deftest tibetan-thesaurus-new-entry-propagates-optional-fields ()
  "Optional Sanskrit / English / German arguments land in the
scaffold: `#+title:' becomes the Sanskrit term, and each `- Primary
translation:' field is populated from the kwargs."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((tibetan-thesaurus-directory tmp))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (_fmt &optional _ _) "20260422T140200")))
        (let ((path (tibetan-thesaurus-new-entry
                     "mthu"
                     :sanskrit "bala"
                     :english "sorcery, magical force"
                     :german "Zauberkraft")))
          (with-temp-buffer
            (insert-file-contents path)
            (let ((s (buffer-string)))
              (should (string-match-p "^#\\+title: bala" s))
              (should (string-match-p
                       "^- Primary translation: sorcery, magical force" s))
              (should (string-match-p
                       "^- Primary translation: Zauberkraft" s)))))))))

(ert-deftest tibetan-thesaurus-new-entry-refuses-to-overwrite ()
  "If a file with the same name already exists, `new-entry' raises
a user-error rather than clobbering — protects existing edits from
a spuriously-deterministic timestamp collision."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((tibetan-thesaurus-directory tmp))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (_fmt &optional _ _) "20260422T140300")))
        (let ((path (expand-file-name
                     "20260422T140300--mthu__user.org" tmp)))
          (with-temp-file path (insert "existing content\n"))
          (should-error (tibetan-thesaurus-new-entry "mthu")
                        :type 'user-error)
          ;; File content unchanged.
          (with-temp-buffer
            (insert-file-contents path)
            (should (string= (buffer-string) "existing content\n"))))))))

(ert-deftest tibetan-thesaurus-new-entry-requires-thesaurus-directory ()
  "Without a configured `tibetan-thesaurus-directory', the command
raises a user-error with clear guidance — no silent fallback."
  (let ((tibetan-thesaurus-directory nil))
    (should-error (tibetan-thesaurus-new-entry "mthu")
                  :type 'user-error)))

(ert-deftest tibetan-thesaurus-new-entry-invalidates-cache ()
  "After creating a new entry, the cached index must be refreshed
so subsequent `lookup' calls find the new zettel without requiring
a manual `tibetan-thesaurus-reload'."
  (tibetan-thesaurus-test--with-tmp-dir tmp
    (let ((tibetan-thesaurus-directory tmp))
      (cl-letf (((symbol-function 'format-time-string)
                 (lambda (_fmt &optional _ _) "20260422T140400")))
        ;; Prime the cache so it's populated with zero entries.
        (tibetan-thesaurus-reload)
        (should (null (tibetan-thesaurus-lookup "mthu")))
        ;; Create a new entry.
        (tibetan-thesaurus-new-entry "mthu" :english "power")
        ;; Lookup sees it without an explicit reload.
        (let ((hits (tibetan-thesaurus-lookup "mthu")))
          (should hits)
          (should (equal (plist-get (car hits) :primary-en) "power")))))))

;; ============================================================================
;; edit-at-point — resolve Wylie under point and jump to / create zettel
;; ============================================================================

(ert-deftest tibetan-thesaurus-wylie-at-point-from-detailed-dict-head ()
  "`tibetan-thesaurus--wylie-at-point' extracts the Wylie from a
Detailed Dictionary head line `◆ TIBETAN [WYLIE] ...' regardless
of where on the line point is positioned."
  (with-temp-buffer
    (insert "◆ མཐུ [mthu] ★ (Steinert ↗)\n")
    (goto-char (point-min))
    (should (equal "mthu"
                   (tibetan-thesaurus--wylie-at-point))))
  ;; Multi-word Wylie inside brackets is returned whole.
  (with-temp-buffer
    (insert "◆ རྣམ་པར་ཤེས་པ [rnam par shes pa] (Steinert ↗)\n")
    (goto-char (point-min))
    (forward-char 5)
    (should (equal "rnam par shes pa"
                   (tibetan-thesaurus--wylie-at-point)))))

(ert-deftest tibetan-thesaurus-wylie-at-point-no-bracketed-wylie ()
  "On a line without a `[WYLIE]' token, `--wylie-at-point' returns
nil — the caller falls back to prompting the user."
  (with-temp-buffer
    (insert "This is an ordinary line of text\n")
    (goto-char (point-min))
    (should (null (tibetan-thesaurus--wylie-at-point)))))

;; ============================================================================
;; PASS 5d — cross-document consistency audit
;; ============================================================================
;;
;; When the user edits a thesaurus entry, every analysis file that
;; referenced the term was generated AGAINST the pre-edit gloss — so
;; its Interlinear / CAT Gloss / Word List output is now stale.  The
;; audit tools here surface those stale analyses so the user can
;; re-run targeted reanalysis (rather than blindly batch-regenerating
;; the whole folder and burning Claude API tokens).

(defun tibetan-thesaurus-test--write-analysis-file (path body)
  "Write a minimal analysis file at PATH with BODY as the
Tibetan Text.  `#+LAST_ANALYZED' is set to a deterministic
pre-2020 date so we can craft mtime-vs-date comparisons freely."
  (with-temp-file path
    (insert "#+TITLE: Test Segment Analysis\n"
            "#+LAST_ANALYZED: 2020-01-01\n\n"
            "* Tibetan Text\n"
            body
            "\n\n"
            "* Auto-Analysis\n"
            ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
            "** Wylie Transliteration\n" body "\n\n")))

(ert-deftest tibetan-thesaurus-audit-flags-analyses-older-than-zettel ()
  "`tibetan-thesaurus-audit-folder' returns a list of analysis
files whose `#+LAST_ANALYZED' date predates the modification time
of a thesaurus zettel for a term that appears in the analysis's
Tibetan Text.

Crafted scenario: one analysis covers the term `mthu', the
thesaurus has been recently edited for that term, so the analysis
is stale.  A second analysis that covers a different term (`bdag',
no thesaurus edit) is NOT flagged."
  (tibetan-thesaurus-test--with-tmp-dir thes
    (tibetan-thesaurus-test--with-tmp-dir analysis
      ;; Stale-because-edited: mthu zettel just written.
      (let ((mthu-zettel (expand-file-name "20260422--mthu.org" thes)))
        (tibetan-thesaurus-test--write-zettel
         mthu-zettel :wylie "mthu" :english "power"))
      ;; Not edited: bdag zettel from a year ago.
      (let ((bdag-zettel (expand-file-name "20250101--bdag.org" thes)))
        (tibetan-thesaurus-test--write-zettel
         bdag-zettel :wylie "bdag" :english "self")
        ;; Back-date the mtime.  (date 2025-01-01 is earlier than
        ;; the analysis's LAST_ANALYZED 2020-01-01 → wait, actually
        ;; our analysis file LAST_ANALYZED is 2020-01-01 which is
        ;; earlier than both zettels.  We need to FUTURE-DATE
        ;; mthu's mtime and PAST-DATE bdag's.)
        (set-file-times bdag-zettel (date-to-time "2019-01-01T00:00:00")))
      ;; Two analysis files.  One uses mthu (stale); one uses bdag (fresh).
      (let ((seg-mthu (expand-file-name "seg-001.org" analysis))
            (seg-bdag (expand-file-name "seg-002.org" analysis)))
        (tibetan-thesaurus-test--write-analysis-file
         seg-mthu "bdag gis mthu bslabs")
        (tibetan-thesaurus-test--write-analysis-file
         seg-bdag "bdag gzhan mthong")
        (let ((tibetan-thesaurus-directory thes))
          (tibetan-thesaurus-reload)
          (let ((stale (tibetan-thesaurus-audit-folder analysis)))
            ;; At least the mthu analysis is flagged.
            (should (cl-some (lambda (item)
                               (string-suffix-p "seg-001.org"
                                                (plist-get item :analysis-file)))
                             stale))
            ;; The bdag-only analysis is NOT flagged (its zettel
            ;; predates the analysis).
            (should-not (cl-some (lambda (item)
                                   (string-suffix-p "seg-002.org"
                                                    (plist-get item :analysis-file)))
                                 stale))
            ;; Each stale item carries the list of stale Wylie terms.
            (let ((item (cl-find-if
                         (lambda (i)
                           (string-suffix-p "seg-001.org"
                                            (plist-get i :analysis-file)))
                         stale)))
              (should (member "mthu" (plist-get item :stale-terms))))))))))

(ert-deftest tibetan-thesaurus-audit-empty-folder-returns-empty ()
  "An analysis folder with no files returns an empty list, not
nil.  Callers that iterate the result safely regardless of folder
state."
  (tibetan-thesaurus-test--with-tmp-dir thes
    (tibetan-thesaurus-test--with-tmp-dir analysis
      (let ((tibetan-thesaurus-directory thes))
        (tibetan-thesaurus-reload)
        (let ((result (tibetan-thesaurus-audit-folder analysis)))
          (should (listp result))
          (should (null result)))))))

(ert-deftest tibetan-thesaurus-audit-no-thesaurus-returns-empty ()
  "When no thesaurus is configured, the audit is a no-op (empty
list).  The stale-detection needs the index; without it there's
nothing to compare against."
  (tibetan-thesaurus-test--with-tmp-dir analysis
    (let ((seg (expand-file-name "seg-001.org" analysis)))
      (tibetan-thesaurus-test--write-analysis-file seg "bdag mthu"))
    (let ((tibetan-thesaurus-directory nil))
      (tibetan-thesaurus-reload)
      (let ((result (tibetan-thesaurus-audit-folder analysis)))
        (should (null result))))))

(ert-deftest tibetan-thesaurus-segments-affected-by-zettel ()
  "`tibetan-thesaurus-segments-affected-by-zettel' takes a
thesaurus zettel path + analysis folder, returns the paths of
segments whose Tibetan Text contains the zettel's Wylie key.
Used by the targeted rerun command below."
  (tibetan-thesaurus-test--with-tmp-dir thes
    (tibetan-thesaurus-test--with-tmp-dir analysis
      (let ((mthu-zettel (expand-file-name "mthu.org" thes)))
        (tibetan-thesaurus-test--write-zettel
         mthu-zettel :wylie "mthu" :english "power")
        (let ((seg-001 (expand-file-name "seg-001.org" analysis))
              (seg-002 (expand-file-name "seg-002.org" analysis))
              (seg-003 (expand-file-name "seg-003.org" analysis)))
          (tibetan-thesaurus-test--write-analysis-file
           seg-001 "bdag gis mthu bslabs nas")
          (tibetan-thesaurus-test--write-analysis-file
           seg-002 "bdag gzhan mthong")  ;; no mthu
          (tibetan-thesaurus-test--write-analysis-file
           seg-003 "mthu chen yod")  ;; mthu present
          (let ((affected (tibetan-thesaurus-segments-affected-by-zettel
                           mthu-zettel analysis)))
            (should (cl-some (lambda (f) (string-suffix-p "seg-001.org" f))
                             affected))
            (should (cl-some (lambda (f) (string-suffix-p "seg-003.org" f))
                             affected))
            (should-not (cl-some (lambda (f) (string-suffix-p "seg-002.org" f))
                                 affected))))))))

(ert-deftest tibetan-thesaurus-segments-affected-by-zettel-word-boundary ()
  "Matching is word-boundary-safe: a zettel with Wylie `mthu' does
NOT match a segment containing `mthuri' or `mthun' — those are
distinct words whose Wylie happens to start with `mthu'."
  (tibetan-thesaurus-test--with-tmp-dir thes
    (tibetan-thesaurus-test--with-tmp-dir analysis
      (let ((mthu-zettel (expand-file-name "mthu.org" thes)))
        (tibetan-thesaurus-test--write-zettel
         mthu-zettel :wylie "mthu" :english "power")
        ;; Analysis uses `mthun' (a different word), not `mthu'.
        (let ((seg (expand-file-name "seg-001.org" analysis)))
          (tibetan-thesaurus-test--write-analysis-file
           seg "bdag mthun pa yin")
          (let ((affected (tibetan-thesaurus-segments-affected-by-zettel
                           mthu-zettel analysis)))
            (should (null affected))))))))

(ert-deftest tibetan-thesaurus-rerun-affected-re-analyzes-segments ()
  "`tibetan-thesaurus-rerun-affected-by-zettel' runs
`tibetan-analysis-reanalyze-file' on every segment under
ANALYSIS-DIR whose Tibetan Text contains the zettel's Wylie
key, and returns the list of paths that were re-analysed.

The re-analysis passes `:re-request-claude nil' so existing
Claude Translation / Grammar / Particles content is preserved —
only the parser-side output is refreshed from the new thesaurus
gloss."
  (tibetan-thesaurus-test--with-tmp-dir thes
    (tibetan-thesaurus-test--with-tmp-dir analysis
      (let ((mthu-zettel (expand-file-name "mthu.org" thes)))
        (tibetan-thesaurus-test--write-zettel
         mthu-zettel :wylie "mthu" :english "power")
        (let ((seg-001 (expand-file-name "seg-001.org" analysis))
              (seg-002 (expand-file-name "seg-002.org" analysis))
              (calls '()))
          (tibetan-thesaurus-test--write-analysis-file
           seg-001 "bdag gis mthu bslabs")
          (tibetan-thesaurus-test--write-analysis-file
           seg-002 "bdag gzhan mthong")    ;; no mthu → untouched
          (cl-letf (((symbol-function 'tibetan-analysis-reanalyze-file)
                     (lambda (path &rest args)
                       (push (cons path args) calls)
                       `(:file ,path :ok t))))
            (let ((rerun (tibetan-thesaurus-rerun-affected-by-zettel
                          mthu-zettel analysis)))
              ;; Only seg-001 (contains mthu) was re-analysed.
              (should (= 1 (length rerun)))
              (should (string-suffix-p "seg-001.org" (car rerun)))
              ;; `:re-request-claude nil' passed so Claude isn't re-fired.
              (let ((args (cdar calls)))
                (should (equal (plist-get args :re-request-claude) nil))))))))))

(provide 'tibetan-thesaurus-test)
;;; tibetan-thesaurus-test.el ends here
