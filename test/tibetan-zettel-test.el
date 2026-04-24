;;; tibetan-zettel-test.el --- Tests for core/tibetan-zettel.el -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Phase 1 of the zettel-in-translation-workflow (see
;; docs/feature-zettel-workflow.org).  Tests pin:
;;   - File classification (__glossar tag OR :wylie: property, OR)
;;   - Parsing the new v2 schema (property drawer with
;;     :preferred-de: / :preferred-en: / :script: / :sanskrit: /
;;     :claude-cached: / :steinert-84000:)
;;   - Back-compat: parsing the Pass-5b Kramer schema (** English
;;     / ** German body sections with `- Primary translation: ...')
;;     into the same plist shape.
;;   - Index build across a mixed directory.
;;   - Wylie lookup (exact, case-insensitive).
;;   - Reload behaviour.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir)))

(require 'tibetan-zettel nil t)

;; ============================================================================
;; Fixture helpers
;; ============================================================================

(defvar tibetan-zettel-test--tempdir nil
  "Per-test temporary directory holding fixture zettels.")

(defmacro tibetan-zettel-test--with-fixture-dir (&rest body)
  "Execute BODY with `tibetan-zettel-test--tempdir' bound to a fresh
temp dir; clean up after."
  (declare (indent 0))
  `(let ((tibetan-zettel-test--tempdir
          (make-temp-file "tibetan-zettel-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory tibetan-zettel-test--tempdir t))))

(defun tibetan-zettel-test--write (filename content)
  "Write CONTENT to FILENAME inside the fixture tempdir; return the
absolute path."
  (let ((path (expand-file-name filename tibetan-zettel-test--tempdir)))
    (with-temp-file path (insert content))
    path))

(cl-defun tibetan-zettel-test--v2-fixture
    (&key id wylie script preferred-de preferred-en
          sanskrit steinert-84000 claude-cached claude-explanation)
  "Return a v2-schema zettel body string (new format, properties +
body sections).  Keyword args fill the respective slots; omit any
slot to leave it out of the drawer."
  (concat
   "#+TITLE: " (or wylie "test") " — test term\n"
   ":PROPERTIES:\n"
   (when id          (format ":ID:       %s\n" id))
   (when wylie       (format ":wylie:    %s\n" wylie))
   (when script      (format ":script:   %s\n" script))
   (when preferred-de (format ":preferred-de: %s\n" preferred-de))
   (when preferred-en (format ":preferred-en: %s\n" preferred-en))
   (when sanskrit    (format ":sanskrit: %s\n" sanskrit))
   (when steinert-84000 (format ":steinert-84000: %s\n" steinert-84000))
   (when claude-cached  (format ":claude-cached: %s\n" claude-cached))
   ":END:\n\n"
   "* Notes\n\n"
   (when claude-explanation
     (concat "* Claude Explanation\n:PROPERTIES:\n:TERM_CACHE: t\n:END:\n\n"
             claude-explanation "\n\n"))))

(cl-defun tibetan-zettel-test--v1-fixture
    (&key id wylie sanskrit primary-en primary-de)
  "Return a Pass-5b Kramer-schema zettel body string (body sections
with `- Primary translation: ...' fields)."
  (concat
   "#+title: " (or sanskrit "test") "\n"
   (when id (format ":PROPERTIES:\n:ID: %s\n:END:\n" id))
   "\n"
   "** Tibetan\n"
   (when wylie (format "- Wylie: %s\n" wylie))
   "\n"
   "** English\n"
   (when primary-en (format "- Primary translation: %s\n" primary-en))
   "\n"
   "** German\n"
   (when primary-de (format "- Primary translation: %s\n" primary-de))
   "\n"))

;; ============================================================================
;; File classification
;; ============================================================================

(ert-deftest tibetan-zettel-glossar-tagged-p-basic ()
  "A Denote filename with `__glossar' tag is detected."
  (should (tibetan-zettel--glossar-tagged-p
           "/somewhere/20260424T143022--tshad-med-bzhi-po__glossar.org"))
  (should (tibetan-zettel--glossar-tagged-p
           "/somewhere/20260424T143022--foo__glossar__buddhist-term.org"))
  (should (tibetan-zettel--glossar-tagged-p
           "/somewhere/20260424T143022--foo__bar__glossar.org")))

(ert-deftest tibetan-zettel-glossar-tagged-p-negative ()
  "A Denote filename WITHOUT `__glossar' tag is rejected."
  (should-not (tibetan-zettel--glossar-tagged-p
               "/somewhere/20260424T143022--foo.org"))
  (should-not (tibetan-zettel--glossar-tagged-p
               "/somewhere/20260424T143022--foo__dzogchen__quelle.org"))
  ;; Partial match like `__glossary' must NOT trigger (__glossar is
  ;; the exact Denote tag; must be followed by __ or .org).
  (should-not (tibetan-zettel--glossar-tagged-p
               "/somewhere/20260424T143022--foo__glossary.org")))

(ert-deftest tibetan-zettel-translation-relevant-p-via-tag ()
  "A file with __glossar tag is translation-relevant even if no
:wylie: property (degenerate case — real zettels always carry
both, but the OR semantics must permit either alone)."
  (tibetan-zettel-test--with-fixture-dir
    (let ((path (tibetan-zettel-test--write
                 "20260424T000001--alpha__glossar.org"
                 "no wylie property here\n")))
      (should (tibetan-zettel--translation-relevant-p path)))))

(ert-deftest tibetan-zettel-translation-relevant-p-via-property ()
  "A file WITHOUT __glossar tag but WITH :wylie: property is
translation-relevant."
  (tibetan-zettel-test--with-fixture-dir
    (let ((path (tibetan-zettel-test--write
                 "20260424T000002--alpha.org"
                 ":PROPERTIES:\n:wylie: bdag\n:END:\n")))
      (should (tibetan-zettel--translation-relevant-p path)))))

(ert-deftest tibetan-zettel-translation-relevant-p-both ()
  "Having both signals is still relevant (OR, not XOR)."
  (tibetan-zettel-test--with-fixture-dir
    (let ((path (tibetan-zettel-test--write
                 "20260424T000003--alpha__glossar.org"
                 ":PROPERTIES:\n:wylie: bdag\n:END:\n")))
      (should (tibetan-zettel--translation-relevant-p path)))))

(ert-deftest tibetan-zettel-translation-relevant-p-neither ()
  "Neither tag nor property → not translation-relevant."
  (tibetan-zettel-test--with-fixture-dir
    (let ((path (tibetan-zettel-test--write
                 "20260424T000004--some-seminar-note.org"
                 "#+TITLE: unrelated note\nfoo bar\n")))
      (should-not (tibetan-zettel--translation-relevant-p path)))))

;; ============================================================================
;; Parsing — v2 schema (properties)
;; ============================================================================

(ert-deftest tibetan-zettel-parse-v2-minimal ()
  "Minimal v2 zettel — :wylie: alone is enough to produce a plist."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((path (tibetan-zettel-test--write
                  "20260424T000010--bdag__glossar.org"
                  (tibetan-zettel-test--v2-fixture :wylie "bdag")))
           (plist (tibetan-zettel--parse-file path)))
      (should plist)
      (should (equal (plist-get plist :wylie) "bdag"))
      (should (equal (plist-get plist :path) path))
      (should-not (plist-get plist :preferred-de))
      (should-not (plist-get plist :preferred-en)))))

(ert-deftest tibetan-zettel-parse-v2-full ()
  "v2 zettel with every schema field populated."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((path (tibetan-zettel-test--write
                  "20260424T000011--tshad-med-bzhi-po__glossar__buddhist-term.org"
                  (tibetan-zettel-test--v2-fixture
                   :id "20260424T000011"
                   :wylie "tshad med bzhi po"
                   :script "ཚད་མེད་བཞི་པོ"
                   :preferred-de "die vier Unermesslichen"
                   :preferred-en "four immeasurables"
                   :sanskrit "caturapramāṇa"
                   :steinert-84000 "yes"
                   :claude-cached "2026-04-24"
                   :claude-explanation "The four immeasurables (apramāṇa) are the meditations…")))
           (plist (tibetan-zettel--parse-file path)))
      (should plist)
      (should (equal (plist-get plist :id) "20260424T000011"))
      (should (equal (plist-get plist :wylie) "tshad med bzhi po"))
      (should (equal (plist-get plist :script) "ཚད་མེད་བཞི་པོ"))
      (should (equal (plist-get plist :preferred-de) "die vier Unermesslichen"))
      (should (equal (plist-get plist :preferred-en) "four immeasurables"))
      (should (equal (plist-get plist :sanskrit) "caturapramāṇa"))
      (should (plist-get plist :steinert-84000))
      (should (plist-get plist :claude-cached-p)))))

(ert-deftest tibetan-zettel-parse-v2-placeholder-preferred-de ()
  "The `[to be researched]' placeholder is parsed as the literal
string, NOT normalised to nil — the translation-gaps report needs
to distinguish \"empty / unset\" from \"explicitly a placeholder\"."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((path (tibetan-zettel-test--write
                  "20260424T000012--alpha__glossar.org"
                  (tibetan-zettel-test--v2-fixture
                   :wylie "alpha"
                   :preferred-de "[to be researched]"
                   :preferred-en "foo")))
           (plist (tibetan-zettel--parse-file path)))
      (should (equal (plist-get plist :preferred-de) "[to be researched]"))
      (should (plist-get plist :preferred-de-placeholder-p)))))

;; ============================================================================
;; Parsing — Pass-5b Kramer schema (back-compat)
;; ============================================================================

(ert-deftest tibetan-zettel-parse-v1-full ()
  "Pass-5b Kramer zettel — :primary-en / :primary-de map to
:preferred-en / :preferred-de in the returned plist."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((path (tibetan-zettel-test--write
                  "kramer-ātman.org"
                  (tibetan-zettel-test--v1-fixture
                   :id "20250522T144759"
                   :wylie "bdag"
                   :sanskrit "ātman"
                   :primary-en "I, self"
                   :primary-de "ich, Selbst")))
           (plist (tibetan-zettel--parse-file path)))
      (should plist)
      (should (equal (plist-get plist :wylie) "bdag"))
      (should (equal (plist-get plist :preferred-en) "I, self"))
      (should (equal (plist-get plist :preferred-de) "ich, Selbst"))
      (should (equal (plist-get plist :sanskrit) "ātman"))
      ;; v1 zettels don't carry these — must default to nil.
      (should-not (plist-get plist :steinert-84000))
      (should-not (plist-get plist :claude-cached-p)))))

(ert-deftest tibetan-zettel-parse-v1-missing-wylie ()
  "Pass-5b zettel with no `- Wylie:' field → parser returns nil
 (can't index without a lookup key).  Same contract as the
legacy tibetan-thesaurus--parse-file."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((path (tibetan-zettel-test--write
                  "bad-kramer.org"
                  (tibetan-zettel-test--v1-fixture
                   :sanskrit "foo"
                   :primary-en "bar")))
           (plist (tibetan-zettel--parse-file path)))
      (should-not plist))))

(ert-deftest tibetan-zettel-parse-non-translation-file ()
  "A non-translation-relevant file (no tag, no :wylie:) returns nil
without blowing up."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((path (tibetan-zettel-test--write
                  "20260424T999999--seminar-note.org"
                  "#+TITLE: unrelated\n* some content\n"))
           (plist (tibetan-zettel--parse-file path)))
      (should-not plist))))

;; ============================================================================
;; Index build + lookup
;; ============================================================================

(ert-deftest tibetan-zettel-build-index-mixed-dir ()
  "Index builder walks a directory containing a v2 zettel, a v1
zettel whose filename has been renamed with Denote's `__glossar'
tag (the post-Phase-6-migration state for legacy Kramer files),
and an unrelated file.  Only the first two should appear in the
index.

Note: fully unmigrated Pass-5b Kramer files — no `__glossar' tag,
no `:wylie:' property, only a `- Wylie:' body field — are
INTENTIONALLY skipped by this detection pass.  Phase 6's
migration command adds the detection signal before files are
expected to appear here.  See docs/feature-zettel-workflow.org
§ Design decisions #1."
  (tibetan-zettel-test--with-fixture-dir
    (tibetan-zettel-test--write
     "20260424T000020--bdag__glossar.org"
     (tibetan-zettel-test--v2-fixture
      :wylie "bdag"
      :preferred-en "I, self"
      :preferred-de "ich, Selbst"))
    ;; Pass-5b Kramer body schema + post-migration Denote filename.
    ;; Represents a file mid-migration: filename has the detection
    ;; signal, body still uses v1 sections.
    (tibetan-zettel-test--write
     "20260424T000021--kramer-chos__glossar.org"
     (tibetan-zettel-test--v1-fixture
      :wylie "chos"
      :primary-en "dharma"
      :primary-de "Dharma"))
    (tibetan-zettel-test--write
     "20260424T000022--unrelated-seminar-note.org"
     "#+TITLE: unrelated\n")
    (let ((index (tibetan-zettel--build-index
                  tibetan-zettel-test--tempdir)))
      (should (hash-table-p index))
      (should (= (hash-table-count index) 2))
      (should (gethash "bdag" index))
      (should (gethash "chos" index)))))

(ert-deftest tibetan-zettel-lookup-exact ()
  "Exact Wylie lookup returns the plist."
  (tibetan-zettel-test--with-fixture-dir
    (tibetan-zettel-test--write
     "20260424T000030--bdag__glossar.org"
     (tibetan-zettel-test--v2-fixture
      :wylie "bdag" :preferred-en "I, self"))
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (tibetan-zettel-reload)
      (let ((plist (tibetan-zettel-lookup "bdag")))
        (should plist)
        (should (equal (plist-get plist :wylie) "bdag"))
        (should (equal (plist-get plist :preferred-en) "I, self"))))))

(ert-deftest tibetan-zettel-lookup-case-insensitive ()
  "Wylie lookup normalises to lowercase."
  (tibetan-zettel-test--with-fixture-dir
    (tibetan-zettel-test--write
     "20260424T000031--bdag__glossar.org"
     (tibetan-zettel-test--v2-fixture
      :wylie "bdag" :preferred-en "I, self"))
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (tibetan-zettel-reload)
      (should (tibetan-zettel-lookup "BDAG"))
      (should (tibetan-zettel-lookup "  bdag  ")))))

(ert-deftest tibetan-zettel-lookup-miss ()
  "Lookup for a Wylie not in the index returns nil."
  (tibetan-zettel-test--with-fixture-dir
    (tibetan-zettel-test--write
     "20260424T000032--bdag__glossar.org"
     (tibetan-zettel-test--v2-fixture :wylie "bdag"))
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (tibetan-zettel-reload)
      (should-not (tibetan-zettel-lookup "doesnotexist")))))

(ert-deftest tibetan-zettel-lookup-empty-index ()
  "Lookup before the index is built (or on an empty dir) returns
nil, not an error."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (tibetan-zettel-reload)
      (should-not (tibetan-zettel-lookup "bdag")))))

(ert-deftest tibetan-zettel-reload-picks-up-new-file ()
  "After a new zettel appears on disk, `tibetan-zettel-reload'
rebuilds the index and the lookup hits."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (tibetan-zettel-reload)
      (should-not (tibetan-zettel-lookup "chos"))
      ;; Add a zettel after the first reload.
      (tibetan-zettel-test--write
       "20260424T000040--chos__glossar.org"
       (tibetan-zettel-test--v2-fixture :wylie "chos"))
      (tibetan-zettel-reload)
      (should (tibetan-zettel-lookup "chos")))))

(provide 'tibetan-zettel-test)
;;; tibetan-zettel-test.el ends here
