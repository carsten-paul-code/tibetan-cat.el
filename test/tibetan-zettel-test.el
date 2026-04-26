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

;; ============================================================================
;; Phase 2 — Multisource ranker integration
;;
;; The Zettel source appears at rank 2 in `tibetan-vocab-multisource-entries'
;; (after Resources/Custom in the rank band but before Corpus/Steinert).
;; The returned plist carries `:zettel-id' + `:zettel-path' extras so the
;; Interlinear renderer can build `[[id:ZETTEL-ID][wylie]]' links.
;; ============================================================================

(require 'tibetan-vocabulary-detailed nil t)

(ert-deftest tibetan-zettel-rank-source-is-2 ()
  "`Zettel' source ranks at 2 — same band as Resources/Custom, but
stable-sort puts it after them because the add-order places
Resources first in the loop.  Specifically NOT rank 1 (the
existing Thesaurus slot, retained for back-compat) and NOT rank
3+ (below corpus-specific)."
  (should (= 2 (tibetan-vocab-rank-source "Zettel"))))

(ert-deftest tibetan-zettel-multisource-injects-when-zettel-exists ()
  "When `tibetan-zettel-lookup' returns a plist for the word's Wylie,
`tibetan-vocab-multisource-entries' emits an entry with :source
\"Zettel\" carrying both :zettel-id and :zettel-path extras and
a bilingual `DE // EN' gloss."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (wylie)
               (and (equal wylie "bdag")
                    (list :id "20260424T000001"
                          :path "/tmp/fake-zettel.org"
                          :wylie "bdag"
                          :preferred-de "ich, Selbst"
                          :preferred-en "I, self"
                          :preferred-de-placeholder-p nil
                          :preferred-en-placeholder-p nil
                          :sanskrit "ātman"
                          :steinert-84000 nil
                          :claude-cached-p nil)))))
    (let* ((entries (tibetan-vocab-multisource-entries "bdag"))
           (zettel (cl-find-if
                    (lambda (e) (equal (plist-get e :source) "Zettel"))
                    entries)))
      (should zettel)
      (should (equal (plist-get zettel :zettel-id) "20260424T000001"))
      (should (equal (plist-get zettel :zettel-path) "/tmp/fake-zettel.org"))
      (should (equal (plist-get zettel :primary)  "ich, Selbst // I, self"))
      (should (equal (plist-get zettel :detailed) "ich, Selbst // I, self")))))

(ert-deftest tibetan-zettel-multisource-skip-when-no-zettel ()
  "When `tibetan-zettel-lookup' returns nil, no Zettel entry is
emitted in the multisource list (regression against the Zettel
source becoming sticky)."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (_w) nil)))
    (let* ((entries (tibetan-vocab-multisource-entries "nonexistent-term"))
           (zettel (cl-find-if
                    (lambda (e) (equal (plist-get e :source) "Zettel"))
                    entries)))
      (should-not zettel))))

(ert-deftest tibetan-zettel-multisource-placeholder-de-only-uses-en ()
  "When `:preferred-de:' is the `[to be researched]' placeholder,
the Zettel gloss falls back to `:preferred-en:' alone (no bilingual
`DE // EN' string with a placeholder stub)."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (_w)
               (list :id "x" :path "/tmp/x.org"
                     :wylie "foo"
                     :preferred-de "[to be researched]"
                     :preferred-de-placeholder-p t
                     :preferred-en "foo-in-english"
                     :preferred-en-placeholder-p nil))))
    (let* ((entries (tibetan-vocab-multisource-entries "foo"))
           (zettel (cl-find-if
                    (lambda (e) (equal (plist-get e :source) "Zettel"))
                    entries)))
      (should zettel)
      (should (equal (plist-get zettel :primary) "foo-in-english"))
      ;; Specifically NOT the string with the placeholder in it.
      (should-not (string-match-p "to be researched"
                                  (plist-get zettel :primary))))))

(ert-deftest tibetan-zettel-multisource-both-placeholder-skipped ()
  "When BOTH preferred fields are placeholders (empty zettel),
no Zettel source is emitted — nothing useful to show.  The zettel
is still indexed (user can edit it) but doesn't pollute the DD."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (_w)
               (list :id "x" :path "/tmp/x.org"
                     :wylie "foo"
                     :preferred-de "[to be researched]"
                     :preferred-de-placeholder-p t
                     :preferred-en "[to be researched]"
                     :preferred-en-placeholder-p t))))
    (let* ((entries (tibetan-vocab-multisource-entries "foo"))
           (zettel (cl-find-if
                    (lambda (e) (equal (plist-get e :source) "Zettel"))
                    entries)))
      (should-not zettel))))

(ert-deftest tibetan-zettel-multisource-ordering-after-resources ()
  "Within rank-2 band (Resources, Custom, Zettel), stable sort preserves
add-order.  The loop adds Resources first, Custom second, Zettel last,
so the ranked output lists them in that order."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (_w)
               (list :id "x" :path "/tmp/x.org"
                     :wylie "foo"
                     :preferred-de "de-gloss" :preferred-de-placeholder-p nil
                     :preferred-en "en-gloss" :preferred-en-placeholder-p nil)))
            ;; Force Resources and Custom to also have a hit for this
            ;; token so the band is populated.
            (tibetan-current-resources-vocab
             (let ((h (make-hash-table :test 'equal)))
               (puthash "foo" "resources-gloss" h)
               h))
            (tibetan-current-custom-vocab
             (let ((h (make-hash-table :test 'equal)))
               (puthash "foo" "custom-gloss" h)
               h)))
    (let* ((entries (tibetan-vocab-multisource-entries "foo"))
           (sources (mapcar (lambda (e) (plist-get e :source)) entries))
           (resources-pos (cl-position "Resources (provided)" sources :test #'equal))
           (custom-pos    (cl-position "Custom" sources :test #'equal))
           (zettel-pos    (cl-position "Zettel" sources :test #'equal)))
      (should resources-pos)
      (should custom-pos)
      (should zettel-pos)
      (should (< resources-pos custom-pos))
      (should (< custom-pos zettel-pos)))))

;; ============================================================================
;; Phase 3 — Auto-creation for <term>-tagged missing tokens
;;
;; When U3's Buddhist Terms detection fires and no zettel yet exists for
;; a <term>-tagged token, a zettel scaffold is auto-created (gated by the
;; `tibetan-zettel-auto-create-on-buddhist-term' defcustom).  The scaffold
;; includes:
;;   · properties drawer with :wylie: / :script: / :sanskrit:, empty
;;     :preferred-de: ([to be researched]), auto :preferred-en: from the
;;     84000 short gloss, :steinert-84000: yes.
;;   · `* 84000 Definitions' body section, protected by :TERM_CACHE: t.
;;   · `* Notes', `* Claude Explanation', `* Back-links' scaffolds.
;;   · Initial back-link to the triggering segment's analysis file.
;; ============================================================================

;; -------- Slug + filename ---------------------------------------------------

(ert-deftest tibetan-zettel-slug-from-wylie-basic ()
  "Wylie → Denote filename slug: downcase, spaces → dashes, apostrophes → dashes."
  (should (equal "bdag" (tibetan-zettel--slug-from-wylie "bdag")))
  (should (equal "tshad-med-bzhi-po"
                 (tibetan-zettel--slug-from-wylie "tshad med bzhi po")))
  (should (equal "khor-ba"
                 (tibetan-zettel--slug-from-wylie "'khor ba")))
  (should (equal "byang-chub-kyi-sems"
                 (tibetan-zettel--slug-from-wylie "Byang Chub Kyi Sems"))))

(ert-deftest tibetan-zettel-denote-timestamp-format ()
  "Denote timestamps match the canonical `YYYYMMDDTHHMMSS' shape."
  (let ((ts (tibetan-zettel--denote-timestamp)))
    (should (stringp ts))
    (should (= 15 (length ts)))
    (should (string-match-p "\\`[0-9]\\{8\\}T[0-9]\\{6\\}\\'" ts))))

(ert-deftest tibetan-zettel-denote-filename-assembly ()
  "Filename assembly: `<TIMESTAMP>--<slug>__glossar__buddhist-term.org'."
  (let ((name (tibetan-zettel--denote-filename
               "20260424T150000" "tshad-med-bzhi-po")))
    (should (equal name
                   "20260424T150000--tshad-med-bzhi-po__glossar__buddhist-term.org"))))

;; -------- Creator ------------------------------------------------------------

(ert-deftest tibetan-zettel-create-for-term-basic ()
  "Creator writes a zettel at the right path with the required fields."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term
                  :wylie "tshad med bzhi po"
                  :script "ཚད་མེད་བཞི་པོ"
                  :sanskrit "caturapramāṇa"
                  :84000-body "<term> four immeasurables (Skt: caturapramāṇa): the meditations on love, compassion, joy, equanimity."
                  :preferred-en "four immeasurables")))
      (should path)
      (should (file-exists-p path))
      ;; Filename contains the expected tags.
      (should (string-match-p "__glossar__buddhist-term\\.org\\'" path))
      ;; Content: properties drawer fields.
      (let ((content (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))))
        (should (string-match-p "^:wylie:[ \t]+tshad med bzhi po$" content))
        (should (string-match-p "^:script:[ \t]+ཚད་མེད་བཞི་པོ$" content))
        (should (string-match-p "^:sanskrit:[ \t]+caturapramāṇa$" content))
        (should (string-match-p "^:preferred-en:[ \t]+four immeasurables$" content))
        (should (string-match-p "^:preferred-de:[ \t]+\\[to be researched\\]$"
                                content))
        (should (string-match-p "^:steinert-84000:[ \t]+yes$" content))
        ;; 84000 Definitions body present.
        (should (string-match-p "^\\* 84000 Definitions$" content))
        (should (string-match-p ":TERM_CACHE:[ \t]+t" content))
        (should (string-match-p "meditations on love" content))
        ;; Scaffold sections.
        (should (string-match-p "^\\* Notes$" content))
        (should (string-match-p "^\\* Claude Explanation$" content))
        (should (string-match-p "^\\* Back-links$" content))
        ;; A valid :ID: property.
        (should (string-match-p "^:ID:[ \t]+[0-9]\\{8\\}T[0-9]\\{6\\}$"
                                content))))))

(ert-deftest tibetan-zettel-create-for-term-with-back-link ()
  "When SOURCE-ANALYSIS-FILE is given, a back-link is written into the
`* Back-links' section pointing at that file's id (or path when no
id available)."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (source-path (tibetan-zettel-test--write
                         "seg-016.org"
                         ":PROPERTIES:\n:ID: seg-016-id\n:END:\n"))
           (zettel-path (tibetan-zettel--create-for-term
                         :wylie "bdag"
                         :script "བདག"
                         :source-analysis-file source-path)))
      (let ((content (with-temp-buffer
                       (insert-file-contents zettel-path)
                       (buffer-string))))
        ;; Back-links section has a link pointing at the source seg.
        (should (string-match-p "\\* Back-links" content))
        (should (or (string-match-p "\\[\\[id:seg-016-id\\]" content)
                    (string-match-p "seg-016\\.org" content)))))))

(ert-deftest tibetan-zettel-create-for-term-idempotent-lookup ()
  "After creation, `tibetan-zettel-lookup' resolves the new wylie.
This confirms the index rebuild happens automatically on
creation, so a second attempt to auto-create the same term sees
the zettel and does nothing."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (should-not (tibetan-zettel-lookup "bdag"))
      (tibetan-zettel--create-for-term
       :wylie "bdag" :script "བདག" :preferred-en "I, self")
      (should (tibetan-zettel-lookup "bdag")))))

;; -------- defcustom gating --------------------------------------------------

(ert-deftest tibetan-zettel-auto-create-custom-nil ()
  "When `tibetan-zettel-auto-create-on-buddhist-term' is nil, the
maybe-create wrapper returns nil without writing anything."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
          (tibetan-zettel-auto-create-on-buddhist-term nil))
      (should-not (tibetan-zettel-maybe-create-for-buddhist-term
                   :wylie "bdag" :script "བདག"))
      (should (null (directory-files tibetan-zettel-directory nil "\\.org\\'"))))))

(ert-deftest tibetan-zettel-auto-create-custom-always ()
  "When the defcustom is `always', the wrapper creates without
prompting."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
          (tibetan-zettel-auto-create-on-buddhist-term 'always))
      (let ((path (tibetan-zettel-maybe-create-for-buddhist-term
                   :wylie "bdag" :script "བདག")))
        (should path)
        (should (file-exists-p path))))))

(ert-deftest tibetan-zettel-auto-create-custom-ask-yes ()
  "When the defcustom is `ask' and the prompt returns y, a zettel is
created.  We stub `y-or-n-p' to return t."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
          (tibetan-zettel-auto-create-on-buddhist-term 'ask))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (let ((path (tibetan-zettel-maybe-create-for-buddhist-term
                     :wylie "bdag" :script "བདག")))
          (should path)
          (should (file-exists-p path)))))))

(ert-deftest tibetan-zettel-auto-create-custom-ask-no ()
  "When the defcustom is `ask' and the prompt returns n, NO zettel is
created (stub y-or-n-p to return nil)."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
          (tibetan-zettel-auto-create-on-buddhist-term 'ask))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should-not (tibetan-zettel-maybe-create-for-buddhist-term
                     :wylie "bdag" :script "བདག"))
        (should (null (directory-files tibetan-zettel-directory nil
                                       "\\.org\\'")))))))

(ert-deftest tibetan-zettel-auto-create-skips-when-zettel-exists ()
  "Before prompting or creating, the wrapper checks lookup-hit.
When a zettel for the wylie already exists, it returns nil
without prompting — the `y-or-n-p' stub must NOT be called."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
          (tibetan-zettel-auto-create-on-buddhist-term 'ask)
          (prompt-called nil))
      (tibetan-zettel-test--write
       "20260424T090000--bdag__glossar.org"
       (tibetan-zettel-test--v2-fixture :wylie "bdag" :preferred-en "I, self"))
      (tibetan-zettel-reload)
      (cl-letf (((symbol-function 'y-or-n-p)
                 (lambda (&rest _) (setq prompt-called t) t)))
        (should-not (tibetan-zettel-maybe-create-for-buddhist-term
                     :wylie "bdag" :script "བདག")))
      (should-not prompt-called))))

;; -------- Phase 3 — interactive walker over analysis buffer ---------------

(defun tibetan-zettel-test--analysis-fixture (&rest buddhist-terms)
  "Write a minimal analysis-buffer body string containing a
`*** Buddhist Terms' subsection populated with BUDDHIST-TERMS.
Each argument is a (SCRIPT WYLIE BODY) triple."
  (concat
   ":PROPERTIES:\n:ID: test-seg-id\n:END:\n"
   "#+TITLE: Segment 1 Analysis\n\n"
   "* Tibetan Text\nསངས་རྒྱས།\n\n"
   "* Auto-Analysis\n"
   "** Grammar\n"
   "*** Particle Map\n=CASE=\n\n"
   "*** Buddhist Terms\n"
   (mapconcat
    (lambda (term)
      (let ((script (nth 0 term)) (wylie (nth 1 term)) (body (nth 2 term)))
        (format "- %s [%s]\n  %s\n" script wylie body)))
    buddhist-terms "")
   "\n*** Particles in This Segment\n[none]\n"))

(ert-deftest tibetan-zettel-auto-create-command-walks-buddhist-terms ()
  "The interactive command walks every `- SCRIPT [wylie]' line under
`*** Buddhist Terms' and offers each to the user.  Terms already
in the zettelkasten are silently skipped; terms absent are
prompted per the defcustom."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (tibetan-zettel-auto-create-on-buddhist-term 'always)
           (analysis-path
            (tibetan-zettel-test--write
             "seg-001.org"
             (tibetan-zettel-test--analysis-fixture
              '("ཚད་མེད་བཞི་པོ" "tshad med bzhi po"
                "four immeasurables: the meditations …")
              '("བྱང་ཆུབ་ཀྱི་སེམས" "byang chub kyi sems"
                "bodhicitta: the mind of awakening …")))))
      (with-current-buffer (find-file-noselect analysis-path)
        (unwind-protect
            (progn
              (tibetan-zettel-reload)
              (should-not (tibetan-zettel-lookup "tshad med bzhi po"))
              (should-not (tibetan-zettel-lookup "byang chub kyi sems"))
              (tibetan-zettel-auto-create-from-current-analysis)
              ;; Both zettels got created.
              (should (tibetan-zettel-lookup "tshad med bzhi po"))
              (should (tibetan-zettel-lookup "byang chub kyi sems")))
          (kill-buffer))))))

(ert-deftest tibetan-zettel-auto-create-command-skips-existing ()
  "Terms that already have a zettel in the zettelkasten are left
alone — no prompt, no duplicate file."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (tibetan-zettel-auto-create-on-buddhist-term 'ask)
           (prompt-called nil))
      ;; Pre-create one of the two zettels.
      (tibetan-zettel-test--write
       "20260101T000000--tshad-med-bzhi-po__glossar.org"
       (tibetan-zettel-test--v2-fixture
        :wylie "tshad med bzhi po" :preferred-en "four immeasurables"))
      (tibetan-zettel-reload)
      (let ((analysis-path
             (tibetan-zettel-test--write
              "seg-001.org"
              (tibetan-zettel-test--analysis-fixture
               '("ཚད་མེད་བཞི་པོ" "tshad med bzhi po"
                 "four immeasurables: …")))))
        (with-current-buffer (find-file-noselect analysis-path)
          (unwind-protect
              (cl-letf (((symbol-function 'y-or-n-p)
                         (lambda (&rest _) (setq prompt-called t) t)))
                (tibetan-zettel-auto-create-from-current-analysis)
                ;; Prompt must NOT have been called — the zettel existed.
                (should-not prompt-called))
            (kill-buffer)))))))

(ert-deftest tibetan-zettel-auto-create-command-no-section ()
  "When the buffer has no `*** Buddhist Terms' section (either the
analysis hasn't run yet, or the segment has no <term>-tagged
tokens), the command signals a clear user-error."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (analysis-path
            (tibetan-zettel-test--write
             "seg-001.org"
             "#+TITLE: Segment 1 Analysis\n* Tibetan Text\nསངས་རྒྱས།\n")))
      (with-current-buffer (find-file-noselect analysis-path)
        (unwind-protect
            (should-error
             (tibetan-zettel-auto-create-from-current-analysis)
             :type 'user-error)
          (kill-buffer))))))

;; ============================================================================
;; Phase 4 — Claude-cache write path (2026-04-24)
;;
;; When a Claude response carries a `## Vocabulary' block (parsed by
;; `tibetan-analysis--parse-claude-vocabulary' into (wylie-key . full-line)
;; pairs), each line whose wylie-key matches a zettel gets its gloss
;; written into that zettel's `* Claude Explanation' section, gated by:
;;   · the zettel must exist (no creation here — Phase 3 handles that).
;;   · the section's body must be empty / placeholder
;;     (`[awaiting first analysis]') — never overwrite user edits or
;;     a populated cache.
;;
;; Writes also stamp three properties for Phase 5's invalidation:
;;   :claude-cached:   YYYY-MM-DD  (today's date)
;;   :claude-model:    the gptel model name in use, or `(unknown)'
;;   :prompt-version:  first 12 chars of (sha256 of system prompt)
;; ============================================================================

(ert-deftest tibetan-zettel-prompt-version-hash-stable ()
  "The prompt-version hash is deterministic for a given input."
  (let ((h1 (tibetan-zettel--prompt-version-hash "system prompt body"))
        (h2 (tibetan-zettel--prompt-version-hash "system prompt body"))
        (h3 (tibetan-zettel--prompt-version-hash "different prompt")))
    (should (equal h1 h2))
    (should-not (equal h1 h3))
    ;; Hash is short enough to be useful as a property value.
    (should (= 12 (length h1)))))

(ert-deftest tibetan-zettel-cache-claude-explanation-writes-to-empty ()
  "Cache writer fills an empty `* Claude Explanation' section.
Properties get stamped; the explanation text replaces the
`[awaiting first analysis]' placeholder."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term
                  :wylie "bdag"
                  :script "བདག"
                  :preferred-en "I, self")))
      (tibetan-zettel--cache-claude-explanation
       path
       "First-person pronoun; functions as the absolutive subject in this clause."
       :model "claude-opus-test"
       :prompt-version "abc123def456")
      (let ((content (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))))
        (should (string-match-p "absolutive subject" content))
        (should-not (string-match-p "awaiting first analysis" content))
        (should (string-match-p "^:claude-cached:[ \t]+[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
                                content))
        (should (string-match-p "^:claude-model:[ \t]+claude-opus-test$"
                                content))
        (should (string-match-p "^:prompt-version:[ \t]+abc123def456$"
                                content))))))

(ert-deftest tibetan-zettel-cache-claude-skips-populated ()
  "When the `* Claude Explanation' section is already populated AND
the cached prompt-version matches what the writer is being asked
to stamp, the writer LEAVES THE BODY UNTOUCHED — idempotent re-run
with same Claude prompt is a no-op.

Phase 5 (commit-after-2394c50) extended the writer with smart
invalidation on prompt-version MISMATCH; the
`overwrites-on-stale-version' test below covers that path.  This
test pins the SAME-version idempotent path."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term
                  :wylie "bdag" :script "བདག")))
      (tibetan-zettel--cache-claude-explanation
       path "ORIGINAL EXPLANATION"
       :model "claude-1" :prompt-version "same-version")
      ;; Re-run with the SAME prompt-version → must short-circuit.
      (tibetan-zettel--cache-claude-explanation
       path "OVERWRITE ATTEMPT"
       :model "claude-2" :prompt-version "same-version")
      (let ((content (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))))
        (should     (string-match-p "ORIGINAL EXPLANATION" content))
        (should-not (string-match-p "OVERWRITE ATTEMPT" content))
        (should     (string-match-p "claude-1" content))
        (should-not (string-match-p "claude-2" content))
        (should     (string-match-p "same-version" content))))))

(ert-deftest tibetan-zettel-cache-claude-vocabulary-walks-all ()
  "Given a parsed Claude Vocabulary alist + the current prompt
hash, the walker updates every zettel whose wylie-key matches.
Tokens with no zettel are silently skipped."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      ;; Two zettels exist; one tokenised in vocab; one absent.
      (tibetan-zettel--create-for-term :wylie "bdag" :script "བདག")
      (tibetan-zettel--create-for-term :wylie "chos" :script "ཆོས")
      (let* ((vocab '(("bdag" . "bdag, noun, \"first-person pronoun, absolutive subject\", marks the speaker")
                      ("chos" . "chos, noun, \"dharma, topic of the verse\", recurring theme")
                      ;; This entry has no matching zettel — skip silently.
                      ("xyz"  . "xyz, particle, \"unknown\", does not exist")))
             (updated (tibetan-zettel--cache-claude-vocabulary
                       vocab
                       :model "claude-test"
                       :prompt-version "phase4test1")))
        ;; Two updates reported.
        (should (= 2 updated))
        ;; Both zettels carry the cached body.
        (let ((bdag-content (with-temp-buffer
                              (insert-file-contents
                               (plist-get (tibetan-zettel-lookup "bdag") :path))
                              (buffer-string)))
              (chos-content (with-temp-buffer
                              (insert-file-contents
                               (plist-get (tibetan-zettel-lookup "chos") :path))
                              (buffer-string))))
          (should (string-match-p "absolutive subject" bdag-content))
          (should (string-match-p "topic of the verse" chos-content))
          (should (string-match-p "phase4test1" bdag-content))
          (should (string-match-p "phase4test1" chos-content)))))))

(ert-deftest tibetan-zettel-cache-claude-vocabulary-empty-input ()
  "Nil / empty vocab input → 0 updated, no error."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (should (= 0 (tibetan-zettel--cache-claude-vocabulary nil)))
      (should (= 0 (tibetan-zettel--cache-claude-vocabulary '()))))))

(ert-deftest tibetan-zettel-cache-claude-extracts-quoted-gloss ()
  "The walker extracts only the QUOTED short gloss field from each
Claude Vocabulary line — not the whole line.  Format Claude emits:
  wylie-key, part-of-speech, \"gloss\", commentary
Only the third (quoted) field is the cacheable explanation; the
commentary is too verbose for the cache."
  (tibetan-zettel-test--with-fixture-dir
    (let ((tibetan-zettel-directory tibetan-zettel-test--tempdir))
      (tibetan-zettel--create-for-term :wylie "bdag" :script "བདག")
      (tibetan-zettel--cache-claude-vocabulary
       '(("bdag" . "bdag, noun, \"first-person pronoun, I/self\", marks the speaker"))
       :model "x" :prompt-version "y")
      (let ((content (with-temp-buffer
                       (insert-file-contents
                        (plist-get (tibetan-zettel-lookup "bdag") :path))
                       (buffer-string))))
        ;; Quoted gloss is in the cache.
        (should (string-match-p "first-person pronoun, I/self" content))
        ;; The trailing commentary is NOT (overly verbose for the cache).
        (should-not (string-match-p "marks the speaker" content))))))

;; ============================================================================
;; Phase 5 — Cache reader + stale detection + writer-overwrite-on-stale
;;
;; The Buddhist Terms renderer consults the zettel's `* Claude Explanation'
;; section.  When fresh (cached prompt-version matches the current system
;; prompt's hash), the cached body is used; the rendering is suffixed with
;; `[via zettel cache]' for transparency.  When stale (prompt has changed
;; since the cache was written), the read returns nil and the renderer
;; falls back to the 84000Definitions body.  The writer is extended to
;; OVERWRITE populated entries when the cached prompt-version differs from
;; the current — so a system-prompt revision (e.g. the U1+U2 tightening
;; commit a1de885) auto-invalidates every cached entry on next reference.
;; ============================================================================

;; -------- Reader / stale-detector ------------------------------------------

(ert-deftest tibetan-zettel-read-claude-explanation-empty ()
  "A zettel that's never been Claude-cached returns nil from the
reader (no `* Claude Explanation' content beyond the placeholder)."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (let ((entry (tibetan-zettel-lookup "bdag")))
        (should entry)
        (should-not (tibetan-zettel--read-claude-explanation entry))))))

(ert-deftest tibetan-zettel-read-claude-explanation-fresh ()
  "A zettel cached at the CURRENT prompt-version returns its body.
The reader matches `:prompt-version:' against the prompt-hash arg
the caller passes (the analysis flow passes the live system-prompt
hash)."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (tibetan-zettel--cache-claude-explanation
       path "Cached body for bdag."
       :model "claude-test"
       :prompt-version "fresh-hash-001")
      (let ((entry (tibetan-zettel-lookup "bdag")))
        (should (equal "Cached body for bdag."
                       (tibetan-zettel--read-claude-explanation
                        entry :current-prompt-version "fresh-hash-001")))))))

(ert-deftest tibetan-zettel-read-claude-explanation-stale ()
  "A zettel whose cached `:prompt-version:' DOESN'T match the
current prompt-hash returns nil — caller falls back to the 84000
body and a re-write replaces the cache."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (tibetan-zettel--cache-claude-explanation
       path "Old body cached against the old prompt."
       :model "claude-test" :prompt-version "old-hash")
      (let ((entry (tibetan-zettel-lookup "bdag")))
        (should-not (tibetan-zettel--read-claude-explanation
                     entry :current-prompt-version "new-hash"))))))

(ert-deftest tibetan-zettel-read-claude-explanation-no-version-arg ()
  "When the caller doesn't pass `:current-prompt-version', the
reader uses the live system prompt's hash (default fallback to
the zettel-module's own default)."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           ;; Stub the prompt symbol so the hash is predictable.
           (tibetan-analysis--claude-system-prompt "predictable")
           (live-hash (tibetan-zettel--prompt-version-hash
                       "predictable"))
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (tibetan-zettel--cache-claude-explanation
       path "Body."
       :prompt-version live-hash)
      (let ((entry (tibetan-zettel-lookup "bdag")))
        ;; No :current-prompt-version arg → reader picks live-hash → match.
        (should (equal "Body."
                       (tibetan-zettel--read-claude-explanation entry)))))))

(ert-deftest tibetan-zettel-cache-stale-p-fresh-and-stale ()
  "The stale-p predicate distinguishes fresh from stale caches."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (tibetan-zettel--cache-claude-explanation
       path "Body." :prompt-version "v1")
      (let ((entry (tibetan-zettel-lookup "bdag")))
        (should-not (tibetan-zettel--cache-stale-p
                     entry :current-prompt-version "v1"))
        (should (tibetan-zettel--cache-stale-p
                 entry :current-prompt-version "v2"))))))

;; -------- Writer overwrite-on-stale -----------------------------------------

(ert-deftest tibetan-zettel-cache-claude-overwrites-on-stale-version ()
  "When the writer is invoked with a prompt-version that DIFFERS
from the cached one, it OVERWRITES the populated section and
re-stamps the properties.  This is the smart-invalidation branch
that complements Phase 4's idempotent write."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (tibetan-zettel--cache-claude-explanation
       path "OLD BODY" :model "claude-1" :prompt-version "v1")
      (tibetan-zettel--cache-claude-explanation
       path "NEW BODY" :model "claude-2" :prompt-version "v2")
      (let ((content (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))))
        (should     (string-match-p "NEW BODY" content))
        (should-not (string-match-p "OLD BODY" content))
        (should     (string-match-p "claude-2" content))
        (should-not (string-match-p "claude-1" content))
        (should     (string-match-p ":prompt-version:[ \t]+v2" content))))))

(ert-deftest tibetan-zettel-cache-claude-no-overwrite-on-same-version ()
  "When the writer is invoked with the SAME prompt-version that's
already cached, it leaves the body alone (idempotent — Phase 4
behaviour preserved)."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((tibetan-zettel-directory tibetan-zettel-test--tempdir)
           (path (tibetan-zettel--create-for-term :wylie "bdag")))
      (tibetan-zettel--cache-claude-explanation
       path "FIRST BODY" :model "claude-1" :prompt-version "v1")
      (tibetan-zettel--cache-claude-explanation
       path "SECOND BODY" :model "claude-1" :prompt-version "v1")
      (let ((content (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))))
        (should     (string-match-p "FIRST BODY" content))
        (should-not (string-match-p "SECOND BODY" content))))))

;; -------- Renderer integration: Buddhist Terms reads from cache ------------

(ert-deftest tibetan-zettel-buddhist-terms-render-prefers-cache ()
  "When a Buddhist term has a fresh-cached zettel, the
`*** Buddhist Terms' rendering uses the zettel body and suffixes
the entry with `[via zettel cache]'.  When no cache, the
84000Definitions body is used as before (regression guard)."
  ;; Stub the zettel so the renderer's lookup returns a known fresh entry.
  (cl-letf* ((tibetan-analysis--claude-system-prompt "live-prompt")
             ((symbol-function 'tibetan-zettel-lookup)
              (lambda (wylie)
                (and (equal wylie "tshad med bzhi po")
                     (list :id "z-id"
                           :path "/tmp/z.org"
                           :wylie "tshad med bzhi po"
                           :preferred-en "four immeasurables"
                           :claude-cached-p t))))
             ((symbol-function 'tibetan-zettel--read-claude-explanation)
              (lambda (entry &rest _)
                (and (equal (plist-get entry :wylie) "tshad med bzhi po")
                     "Cached Claude body — pithy explanation."))))
    ;; The renderer takes (script wylie body) triples from
    ;; `--collect-buddhist-terms'; we pass them directly here to test
    ;; the rendering layer in isolation.
    (let ((rendered
           (with-temp-buffer
             (tibetan-analysis--render-buddhist-terms-section
              '(("ཚད་མེད་བཞི་པོ" "tshad med bzhi po"
                 "<term> four immeasurables: meditation on love, …")))
             (buffer-string))))
      (should (string-match-p "Cached Claude body" rendered))
      (should (string-match-p "via zettel cache" rendered))
      ;; The 84000 body is NOT in the rendered output — cache wins.
      (should-not (string-match-p "meditation on love" rendered)))))

(ert-deftest tibetan-zettel-buddhist-terms-render-fallback-to-84000 ()
  "When no zettel exists for the term (or the cache is empty), the
renderer falls back to the 84000 body — Phase 5 doesn't break the
pre-existing behaviour."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (_wylie) nil)))
    (let ((rendered
           (with-temp-buffer
             (tibetan-analysis--render-buddhist-terms-section
              '(("ཚད་མེད་བཞི་པོ" "tshad med bzhi po"
                 "<term> four immeasurables: meditation on love, …")))
             (buffer-string))))
      (should     (string-match-p "meditation on love" rendered))
      (should-not (string-match-p "via zettel cache" rendered)))))

(ert-deftest tibetan-zettel-buddhist-terms-render-fallback-on-stale ()
  "When the zettel has a STALE cache (prompt-version mismatch), the
reader returns nil and the renderer falls back to 84000 — the
zettel itself isn't shown as the source until a fresh Claude call
overwrites the cache."
  (cl-letf (((symbol-function 'tibetan-zettel-lookup)
             (lambda (wylie)
               (and (equal wylie "tshad med bzhi po")
                    (list :wylie "tshad med bzhi po"
                          :claude-cached-p t))))
            ((symbol-function 'tibetan-zettel--read-claude-explanation)
             (lambda (&rest _) nil)))   ; stale → nil
    (let ((rendered
           (with-temp-buffer
             (tibetan-analysis--render-buddhist-terms-section
              '(("ཚད་མེད་བཞི་པོ" "tshad med bzhi po"
                 "<term> four immeasurables: meditation on love, …")))
             (buffer-string))))
      (should     (string-match-p "meditation on love" rendered))
      (should-not (string-match-p "via zettel cache" rendered)))))

;; ============================================================================
;; Phase 6 — Migrate Pass-5b Thesaurus zettels into the main zettelkasten
;;
;; The Pass-5b Thesaurus stores zettels as Kramer-format files in
;; `~/Documents/tibetan-thesaurus/' with body fields:
;;   #+title: <Sanskrit>
;;   ** Tibetan
;;   - Wylie: <wylie>
;;   ** English / ** German
;;   - Primary translation: <gloss>
;;
;; Migration walks SOURCE-DIR, parses each via the Pass-5b reader, and
;; writes a v2-schema zettel into TARGET-DIR (default
;; `tibetan-zettel-directory') — properties drawer with `:wylie:',
;; `:preferred-de:', `:preferred-en:', etc., plus the Denote `__glossar'
;; tag in the filename so Phase-1 detection picks it up.
;;
;; Idempotent: when a zettel for the wylie already exists in the target,
;; the source file is left in place and skipped from the migration.
;; ============================================================================

(defun tibetan-zettel-test--write-pass5b-fixture (filename body)
  "Write a Pass-5b Kramer-format zettel into the fixture tempdir's
SOURCE/ subdir.  Returns absolute path."
  (let ((source-dir (expand-file-name "source"
                                      tibetan-zettel-test--tempdir)))
    (make-directory source-dir t)
    (let ((path (expand-file-name filename source-dir)))
      (with-temp-file path (insert body))
      path)))

(ert-deftest tibetan-zettel-migrate-thesaurus-creates-v2-zettel ()
  "A single Pass-5b file → one v2-schema zettel in TARGET-DIR with
the right properties drawer and the `__glossar' detection tag in
the filename."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((source-dir (file-name-as-directory
                        (expand-file-name "source"
                                          tibetan-zettel-test--tempdir)))
           (target-dir (file-name-as-directory
                        (expand-file-name "target"
                                          tibetan-zettel-test--tempdir)))
           (tibetan-zettel-directory target-dir))
      (make-directory target-dir t)
      (tibetan-zettel-test--write-pass5b-fixture
       "kramer-bdag.org"
       (tibetan-zettel-test--v1-fixture
        :id "20250522T144758"
        :wylie "bdag"
        :sanskrit "ātman"
        :primary-en "I, self"
        :primary-de "ich, Selbst"))
      (let* ((report (tibetan-zettel-migrate-thesaurus
                      source-dir target-dir)))
        (should (= 1 (plist-get report :migrated)))
        (should (= 0 (plist-get report :skipped)))
        ;; Reload index and confirm the migrated zettel is reachable.
        (tibetan-zettel-reload)
        (let ((entry (tibetan-zettel-lookup "bdag")))
          (should entry)
          (should (equal (plist-get entry :wylie) "bdag"))
          (should (equal (plist-get entry :preferred-en) "I, self"))
          (should (equal (plist-get entry :preferred-de) "ich, Selbst"))
          (should (equal (plist-get entry :sanskrit) "ātman"))
          (should (equal (plist-get entry :id) "20250522T144758"))
          ;; Filename carries the __glossar tag.
          (should (string-match-p "__glossar"
                                  (plist-get entry :path))))))))

(ert-deftest tibetan-zettel-migrate-thesaurus-idempotent ()
  "Running migration twice doesn't duplicate.  The second run sees
the wylie already in the target zettelkasten and skips."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((source-dir (file-name-as-directory
                        (expand-file-name "source"
                                          tibetan-zettel-test--tempdir)))
           (target-dir (file-name-as-directory
                        (expand-file-name "target"
                                          tibetan-zettel-test--tempdir)))
           (tibetan-zettel-directory target-dir))
      (make-directory target-dir t)
      (tibetan-zettel-test--write-pass5b-fixture
       "kramer-bdag.org"
       (tibetan-zettel-test--v1-fixture
        :wylie "bdag" :primary-en "I, self"))
      (tibetan-zettel-migrate-thesaurus source-dir target-dir)
      ;; Run again.
      (let ((report (tibetan-zettel-migrate-thesaurus
                     source-dir target-dir)))
        (should (= 0 (plist-get report :migrated)))
        (should (= 1 (plist-get report :skipped)))
        ;; Target dir has exactly one .org file.
        (should (= 1 (length (directory-files target-dir nil "\\.org\\'"))))))))

(ert-deftest tibetan-zettel-migrate-thesaurus-dry-run ()
  "Dry-run mode reports what WOULD happen but writes nothing.
Source and target dirs unchanged after the call."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((source-dir (file-name-as-directory
                        (expand-file-name "source"
                                          tibetan-zettel-test--tempdir)))
           (target-dir (file-name-as-directory
                        (expand-file-name "target"
                                          tibetan-zettel-test--tempdir)))
           (tibetan-zettel-directory target-dir))
      (make-directory target-dir t)
      (tibetan-zettel-test--write-pass5b-fixture
       "kramer-bdag.org"
       (tibetan-zettel-test--v1-fixture
        :wylie "bdag" :primary-en "I, self"))
      (let ((report (tibetan-zettel-migrate-thesaurus
                     source-dir target-dir t)))
        (should (= 1 (plist-get report :migrated))) ; would-have-migrated
        (should (plist-get report :dry-run))
        ;; Target dir is empty — nothing written.
        (should (null (directory-files target-dir nil "\\.org\\'")))))))

(ert-deftest tibetan-zettel-migrate-thesaurus-multiple-files ()
  "Migration walks every .org in SOURCE-DIR and aggregates counts."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((source-dir (file-name-as-directory
                        (expand-file-name "source"
                                          tibetan-zettel-test--tempdir)))
           (target-dir (file-name-as-directory
                        (expand-file-name "target"
                                          tibetan-zettel-test--tempdir)))
           (tibetan-zettel-directory target-dir))
      (make-directory target-dir t)
      (tibetan-zettel-test--write-pass5b-fixture
       "k1.org" (tibetan-zettel-test--v1-fixture
                 :wylie "bdag" :primary-en "self"))
      (tibetan-zettel-test--write-pass5b-fixture
       "k2.org" (tibetan-zettel-test--v1-fixture
                 :wylie "chos" :primary-en "dharma"))
      (tibetan-zettel-test--write-pass5b-fixture
       "k3.org" (tibetan-zettel-test--v1-fixture
                 :wylie "sangs rgyas" :primary-en "buddha"))
      ;; A non-.org file in source must be ignored.
      (with-temp-file (expand-file-name "README.txt" source-dir)
        (insert "not a zettel"))
      (let ((report (tibetan-zettel-migrate-thesaurus
                     source-dir target-dir)))
        (should (= 3 (plist-get report :migrated)))
        (should (= 0 (plist-get report :skipped)))
        (tibetan-zettel-reload)
        (should (tibetan-zettel-lookup "bdag"))
        (should (tibetan-zettel-lookup "chos"))
        (should (tibetan-zettel-lookup "sangs rgyas"))))))

(ert-deftest tibetan-zettel-migrate-thesaurus-skips-malformed ()
  "Malformed Pass-5b files (no `- Wylie:' field) are reported as
errors but don't abort the migration."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((source-dir (file-name-as-directory
                        (expand-file-name "source"
                                          tibetan-zettel-test--tempdir)))
           (target-dir (file-name-as-directory
                        (expand-file-name "target"
                                          tibetan-zettel-test--tempdir)))
           (tibetan-zettel-directory target-dir))
      (make-directory target-dir t)
      (tibetan-zettel-test--write-pass5b-fixture
       "k1.org" (tibetan-zettel-test--v1-fixture
                 :wylie "bdag" :primary-en "self"))
      ;; Malformed: no Wylie field at all.
      (tibetan-zettel-test--write-pass5b-fixture
       "broken.org" "#+title: bogus\nno wylie field here\n")
      (let ((report (tibetan-zettel-migrate-thesaurus
                     source-dir target-dir)))
        (should (= 1 (plist-get report :migrated)))
        (should (= 1 (plist-get report :errors)))))))

(ert-deftest tibetan-zettel-migrate-thesaurus-empty-source ()
  "Empty / non-existent source dir → all-zero report, no error."
  (tibetan-zettel-test--with-fixture-dir
    (let* ((source-dir (file-name-as-directory
                        (expand-file-name "source"
                                          tibetan-zettel-test--tempdir)))
           (target-dir (file-name-as-directory
                        (expand-file-name "target"
                                          tibetan-zettel-test--tempdir)))
           (tibetan-zettel-directory target-dir))
      (make-directory source-dir t)
      (make-directory target-dir t)
      (let ((report (tibetan-zettel-migrate-thesaurus
                     source-dir target-dir)))
        (should (= 0 (plist-get report :migrated)))
        (should (= 0 (plist-get report :skipped)))
        (should (= 0 (plist-get report :errors)))))))

(provide 'tibetan-zettel-test)
;;; tibetan-zettel-test.el ends here
