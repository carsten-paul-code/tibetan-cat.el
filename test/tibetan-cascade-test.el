;;; tibetan-cascade-test.el --- Tests for the cascade layout (C1+) -*- lexical-binding: t -*-

;;; Commentary:
;;
;; CASCADE v2 (plan 2026-07-22): one file per sentence, shads as
;; nested subsegments.  C1 = the foundations: the explicit
;; `#+TIBETAN_LAYOUT: cascade' content marker (§2.8: explicit header,
;; never auto-detection), the `tibetan-analysis--cascade-p' predicate
;; (mirrors `--defer-mt-p' resolution), and the pure shad-unit
;; splitter in persist/tibetan-cascade.el.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-analysis-claude)
(require 'tibetan-cascade)
;; The defer-MT visibility tests assert the DM recognizer too; the
;; open-message test resolves the sentence through the §5.40 walker.
(require 'tibetan-dharmamitra-translation)
(require 'tibetan-sentence-persist)

;; ============================================================================
;; Fixture
;; ============================================================================

(defmacro tibetan-cascade-test--with-source (headers &rest body)
  "Write a temp source with HEADERS (string) and bind SOURCE-FILE,
ANALYSIS-FILE (a seg file whose #+SOURCE links to it), and DIR."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-cascade-" t))
          (source-file (expand-file-name "quelle.org" dir))
          (analysis-file (expand-file-name "seg-001.org" dir)))
     (ignore analysis-file)
     (unwind-protect
         (progn
           (with-temp-file source-file
             (insert "#+TITLE: Quelle\n" ,headers "\n* Tibetan Text\n"))
           (with-temp-file analysis-file
             (insert "#+TITLE: Segment 1 Analysis\n"
                     "#+SOURCE: [[file:quelle.org::*Segment 1][Segment 1]]\n"))
           ,@body)
       (delete-directory dir t))))

;; ============================================================================
;; C1 commit 1 — :layout metadata key + --cascade-p predicate
;; ============================================================================

(ert-deftest tibetan-cascade-metadata-layout-key ()
  "`#+TIBETAN_LAYOUT:' parses into the :layout plist key (downcased);
absent or empty header → nil."
  (tibetan-cascade-test--with-source "#+TIBETAN_LAYOUT: cascade\n"
    (should (equal "cascade"
                   (plist-get (tibetan-analysis--read-source-metadata
                               source-file)
                              :layout))))
  ;; Case-insensitive on read.
  (tibetan-cascade-test--with-source "#+TIBETAN_LAYOUT: Cascade\n"
    (should (equal "cascade"
                   (plist-get (tibetan-analysis--read-source-metadata
                               source-file)
                              :layout))))
  ;; Absent and empty both → nil (legacy two-file).
  (tibetan-cascade-test--with-source ""
    (should-not (plist-get (tibetan-analysis--read-source-metadata
                            source-file)
                           :layout)))
  (tibetan-cascade-test--with-source "#+TIBETAN_LAYOUT:\n"
    (should-not (plist-get (tibetan-analysis--read-source-metadata
                            source-file)
                           :layout))))

(ert-deftest tibetan-cascade-metadata-source-lang-key ()
  "B1 (Sanskrit-Kaskade, 2026-09-24): `#+SOURCE_LANG:' parst in den
:source-lang-Plist-Key (downcased); fehlend/leer → nil.  Bewusst
NICHT #+SOURCE_MODE (gehört dem Parallelmodus)."
  (tibetan-cascade-test--with-source "#+SOURCE_LANG: sa\n"
    (should (equal "sa"
                   (plist-get (tibetan-analysis--read-source-metadata
                               source-file)
                              :source-lang))))
  (tibetan-cascade-test--with-source "#+SOURCE_LANG: SA\n"
    (should (equal "sa"
                   (plist-get (tibetan-analysis--read-source-metadata
                               source-file)
                              :source-lang))))
  (tibetan-cascade-test--with-source ""
    (should-not (plist-get (tibetan-analysis--read-source-metadata
                            source-file)
                           :source-lang)))
  (tibetan-cascade-test--with-source "#+SOURCE_LANG:\n"
    (should-not (plist-get (tibetan-analysis--read-source-metadata
                            source-file)
                           :source-lang))))

(ert-deftest tibetan-analysis-resolve-source-lang ()
  "B1: `--resolve-source-lang' — Datei selbst zuerst, dann der
#+SOURCE-Link (Auflösungsordnung wie --cascade-p); Default \"bo\";
signalisiert nie."
  ;; Direct source file.
  (tibetan-cascade-test--with-source "#+SOURCE_LANG: sa\n"
    (should (equal "sa" (tibetan-analysis--resolve-source-lang
                         source-file)))
    ;; Analysis file resolves through the #+SOURCE link.
    (should (equal "sa" (tibetan-analysis--resolve-source-lang
                         analysis-file))))
  ;; No header → the Tibetan default, also via analysis file.
  (tibetan-cascade-test--with-source ""
    (should (equal "bo" (tibetan-analysis--resolve-source-lang
                         source-file)))
    (should (equal "bo" (tibetan-analysis--resolve-source-lang
                         analysis-file))))
  ;; Garbage input degrades to the default, never signals.
  (should (equal "bo" (tibetan-analysis--resolve-source-lang nil)))
  (should (equal "bo" (tibetan-analysis--resolve-source-lang
                       "/nonexistent/nowhere.org"))))

(ert-deftest tibetan-cascade-p-predicate ()
  "`--cascade-p' is t only for a cascade-layout document; resolves an
analysis file through its #+SOURCE link; never signals."
  ;; Direct source file.
  (tibetan-cascade-test--with-source "#+TIBETAN_LAYOUT: cascade\n"
    (should (tibetan-analysis--cascade-p source-file))
    ;; Analysis file resolves through the #+SOURCE link.
    (should (tibetan-analysis--cascade-p analysis-file)))
  ;; Legacy document (no header) → nil, also via analysis file.
  (tibetan-cascade-test--with-source ""
    (should-not (tibetan-analysis--cascade-p source-file))
    (should-not (tibetan-analysis--cascade-p analysis-file)))
  ;; A DIFFERENT layout value is NOT cascade (explicit marker only).
  (tibetan-cascade-test--with-source "#+TIBETAN_LAYOUT: two-file\n"
    (should-not (tibetan-analysis--cascade-p source-file)))
  ;; Garbage input degrades to nil, never signals.
  (should-not (tibetan-analysis--cascade-p nil))
  (should-not (tibetan-analysis--cascade-p 42))
  (should-not (tibetan-analysis--cascade-p "/nonexistent/nowhere.org")))

;; ============================================================================
;; C1 commit 2 — pure shad-unit splitter (persist/tibetan-cascade.el)
;; ============================================================================
;; Deterministic, mechanical, never wrong: all linguistic intelligence
;; lives at the sentence boundary; the subsegment generator just cuts
;; at shads.  Contract: concatenating the returned units reproduces
;; the input EXACTLY (separator whitespace stays with the preceding
;; unit, so units render cleanly).

(ert-deftest tibetan-cascade-split-shad-units-basic ()
  "Prose with internal shads splits into shad-terminated units."
  (let ((units (tibetan-cascade-split-shad-units
                "བདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན། མཐའ་མ་འདི་ཡིན།")))
    (should (equal '("བདག་གིས་ལས་བྱས། "
                     "ཆོས་ཟབ་མོ་ཡིན། "
                     "མཐའ་མ་འདི་ཡིན།")
                   units))))

(ert-deftest tibetan-cascade-split-shad-units-concat-identity ()
  "Concatenation of the units reproduces the input byte-for-byte."
  (dolist (text '("བདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན། མཐའ་མ།"
                  "ཤོག་གཅིག།། ཤོག་གཉིས།"
                  "ཚིག་དང་པོ། ། ཚིག་གཉིས་པ། །"
                  "line1།\nline2།\nline3།"
                  "ཤད་མེད་པའི་ཚིག"))
    (should (equal text
                   (apply #'concat
                          (tibetan-cascade-split-shad-units text))))))

(ert-deftest tibetan-cascade-split-shad-units-shadless-single-unit ()
  "Text without any shad is ONE unit (the §5.32 seg-137 fused case
becomes a single subsegment, not zero)."
  (should (equal '("ཤད་མེད་པའི་ཚིག")
                 (tibetan-cascade-split-shad-units "ཤད་མེད་པའི་ཚིག"))))

(ert-deftest tibetan-cascade-split-shad-units-double-shad ()
  "`།།' and the pecha-style spaced `། །' both close ONE unit and stay
attached to it whole — a bare double shad never yields an empty unit."
  (should (equal '("ཤོག་གཅིག།། " "ཤོག་གཉིས།")
                 (tibetan-cascade-split-shad-units
                  "ཤོག་གཅིག།། ཤོག་གཉིས།")))
  (should (equal '("ཚིག་དང་པོ། ། " "ཚིག་གཉིས་པ། །")
                 (tibetan-cascade-split-shad-units
                  "ཚིག་དང་པོ། ། ཚིག་གཉིས་པ། །"))))

(ert-deftest tibetan-cascade-split-shad-units-trailing-and-newlines ()
  "A final shad (with or without trailing whitespace) stays with the
last unit; newlines act as ordinary separator whitespace."
  (should (equal '("ཚིག་དང་པོ། " "ཚིག་གཉིས་པ།")
                 (tibetan-cascade-split-shad-units
                  "ཚིག་དང་པོ། ཚིག་གཉིས་པ།")))
  (should (equal '("line1།\n" "line2།\n" "line3།")
                 (tibetan-cascade-split-shad-units
                  "line1།\nline2།\nline3།"))))

(ert-deftest tibetan-cascade-split-shad-units-degenerate-input ()
  "nil / empty / blank input → nil, never signals."
  (should-not (tibetan-cascade-split-shad-units nil))
  (should-not (tibetan-cascade-split-shad-units ""))
  (should-not (tibetan-cascade-split-shad-units "   \n  ")))

;; ============================================================================
;; C2.1 — cascade sent-file scaffold + create-file
;; ============================================================================
;; One file per sentence: user slots on top, sentence-level analysis,
;; `* Subsegments' keyed by the source's GLOBAL segment numbers with
;; :SUBSEG: ordinals, per-unit deterministic sections extracted from
;; the segment renderer, Footnotes at the bottom.

(defmacro tibetan-cascade-test--with-stub-renderer (&rest body)
  "Run BODY with `tibetan-analysis-generate-content' stubbed to a
canned, text-parameterized segment layout (deterministic extraction
checks, no dictionary machinery)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'tibetan-analysis-generate-content)
              ;; (Phonetics line dropped from the canned layout
              ;; 2026-09-15 — the real renderer no longer emits it.)
              (lambda (text &rest _)
                (format (concat "** Wylie Transliteration\nWYLIE(%s)\n\n"
                                "** Interlinear Gloss\nGLOSS(%s)\n\n"
                                "** Translation\n[Requesting translation...]\n\n"
                                "** Grammar\n*** Particles\nPART(%s)\n\n"
                                "*** Claude Grammar\n\n"
                                "** Provided Translations\n\n")
                        text text text))))
     ,@body))

(ert-deftest tibetan-cascade-scaffold-structure ()
  "R8: layout, header marker, per-layer Reading section with one
line per shad unit, ⟦N⟧ rendering keys, no Subsegments tree, no
Phonetics, and top/bottom user-slot ordering."
  (tibetan-cascade-test--with-stub-renderer
    (let ((s (tibetan-cascade--scaffold
              4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
              "/tmp/doc.org")))
      ;; Header marker + segments line.
      (should (string-match-p "^#\\+TIBETAN_LAYOUT: cascade$" s))
      (should (string-match-p "^#\\+SEGMENTS: 105, 106$" s))
      ;; Top-level ordering — Reading directly after Tibetan Text.
      (let ((notes (string-match "^\\* My Notes$" s))
            (wt    (string-match "^\\* Working Translation$" s))
            (tt    (string-match "^\\* Tibetan Text$" s))
            (rd    (string-match "^\\* Reading$" s))
            (ta    (string-match "^\\* Tibetan Analysis$" s))
            (foot  (string-match "^\\* Footnotes$" s)))
        (should (and notes wt tt rd ta foot))
        (should (< notes wt tt rd ta foot)))
      ;; Reading layers (combined): ** Interlinear then Renderings.
      (let ((il (string-match "^\\*\\* Interlinear$" s))
            (re (string-match "^\\*\\* Renderings$" s)))
        (should (and il re))
        (should (< il re)))
      (should-not (string-match-p "^\\*\\* Wylie$" s))
      (should (string-match-p "^- ⟦105⟧ " s))
      (should (string-match-p "^- ⟦106⟧ " s))
      (should (string-match-p "\\[Awaiting sentence translation…\\]" s))
      ;; Two combined lines, one per unit, each shad rendered ` /'.
      (let* ((il-start (string-match "^\\*\\* Interlinear$" s))
             (il-end (string-match "^\\*\\* Renderings$" s))
             (body (substring s il-start il-end))
             (lines (cl-remove-if #'string-empty-p
                                  (cdr (split-string body "\n")))))
        (should (= 2 (length lines)))
        (should (cl-every (lambda (l) (string-suffix-p " /" l))
                          lines)))
      ;; The Subsegments tree and Phonetics are RETIRED.
      (should-not (string-match-p "^\\* Subsegments$" s))
      (should-not (string-match-p "^\\*+ Phonetics$" s))
      (should-not (string-match-p "^\\*\\* Segment 105$" s))
      ;; The full sentence text sits under * Tibetan Text.
      (should (string-match-p
               (regexp-quote "བདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན།") s)))))

(ert-deftest tibetan-cascade-create-file-writes-marked-sent-file ()
  "C2.1: create-file writes the suffix-aware sent path with the
cascade marker + #+SOURCE link and returns the path."
  (tibetan-cascade-test--with-stub-renderer
    (let* ((dir (make-temp-file "cascade-create-" t))
           (src (expand-file-name "doc.org" dir)))
      (unwind-protect
          (progn
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                      "* Tibetan Text\n*** Sentence 4\n"
                      "**** Segment 105\nབདག\n\n**** Segment 106\nཆོས\n"))
            (let* ((default-directory dir)
                   (path (tibetan-cascade--create-file
                          4 '((105 . "བདག") (106 . "ཆོས")) src)))
              (should (file-exists-p path))
              (should (string-match-p "sent-004"
                                      (file-name-nondirectory path)))
              (with-temp-buffer
                (insert-file-contents path)
                (let ((c (buffer-string)))
                  (should (string-match-p "^#\\+TIBETAN_LAYOUT: cascade$" c))
                  (should (string-match-p "^#\\+SOURCE: \\[\\[file:" c))
                  (should (string-match-p "^\\* Reading$" c))))))
        (delete-directory dir t)))))

;; ============================================================================
;; C2.2 — subsegment subtree I/O (keyed by GLOBAL segment number)
;; ============================================================================

(defmacro tibetan-cascade-test--with-cascade-file (&rest body)
  "Create a scaffolded 2-unit cascade file (CURRENT layout — since
R8 that is the Reading layout); bind CASCADE-FILE and DIR."
  (declare (indent 0))
  `(tibetan-cascade-test--with-stub-renderer
     (let* ((dir (make-temp-file "cascade-io-" t))
            (src (expand-file-name "doc.org" dir)))
       (unwind-protect
           (progn
             (with-temp-file src
               (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                       "* Tibetan Text\n*** Sentence 4\n"
                       "**** Segment 105\nབདག\n\n**** Segment 106\nཆོས\n"))
             (let ((cascade-file
                    (tibetan-cascade--create-file
                     4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
                     src)))
               ,@body))
         (delete-directory dir t)))))

(defmacro tibetan-cascade-test--with-legacy-cascade-file (&rest body)
  "Hand-written OLD-layout (pre-R8 * Subsegments) cascade file;
bind LEGACY-FILE and DIR.  The legacy READ/WRITE primitives and the
migration path are exercised against this fixture — the scaffold no
longer produces it."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "cascade-legacy-" t))
          (src (expand-file-name "doc.org" dir))
          (legacy-file (expand-file-name "sent-004-doc.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file src
             (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                     "* Tibetan Text\n*** Sentence 4\n"
                     "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"
                     "**** Segment 106\nཆོས་ཟབ་མོ་ཡིན།\n\n"))
           (with-temp-file legacy-file
             (insert "#+TITLE: Sentence 4 Analysis\n"
                     "#+TIBETAN_LAYOUT: cascade\n"
                     "#+SOURCE: [[file:../doc.org::*Sentence 4]"
                     "[doc.org / Sentence 4]]\n"
                     "#+SEGMENTS: 105, 106\n\n"
                     "* My Notes\n\n\n"
                     "* Working Translation\n\n\n"
                     "* Tibetan Text\nབདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན།\n\n"
                     "* Tibetan Analysis\n"
                     ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                     "** Translation\n[Requesting translation...]\n\n"
                     "** DharmaMitra Translation\n[Awaiting DharmaMitra…]\n\n"
                     "* Subsegments\n\n"
                     "** Segment 105\n:PROPERTIES:\n:SUBSEG: 1\n:END:\n\n"
                     "བདག་གིས་ལས་བྱས།\n\n"
                     "*** Rendering\n"
                     tibetan-cascade-rendering-placeholder "\n\n"
                     "*** Wylie\nWYLIE(བདག་གིས་ལས་བྱས། )\n\n"
                     "*** Phonetics\nPHON\n\n"
                     "*** Interlinear Gloss\nGLOSS(བདག་གིས་ལས་བྱས། )\n\n"
                     "*** Particles\nPART\n\n"
                     "** Segment 106\n:PROPERTIES:\n:SUBSEG: 2\n:END:\n\n"
                     "ཆོས་ཟབ་མོ་ཡིན།\n\n"
                     "*** Rendering\n"
                     tibetan-cascade-rendering-placeholder "\n\n"
                     "*** Wylie\nWYLIE(ཆོས་ཟབ་མོ་ཡིན།)\n\n"
                     "*** Phonetics\nPHON\n\n"
                     "*** Interlinear Gloss\nGLOSS(ཆོས་ཟབ་མོ་ཡིན།)\n\n"
                     "*** Particles\nPART\n\n"
                     "* Footnotes\n\n"))
           ,@body)
       (delete-directory dir t))))

(ert-deftest tibetan-cascade-subsegment-numbers ()
  "The ordered global segment numbers under * Subsegments (LEGACY
layout — the primitives stay readable for unmigrated files)."
  (tibetan-cascade-test--with-legacy-cascade-file
    (should (equal '(105 106)
                   (tibetan-cascade--subsegment-numbers legacy-file)))
    ;; Degenerate inputs → nil, never signals.
    (should-not (tibetan-cascade--subsegment-numbers nil))
    (should-not (tibetan-cascade--subsegment-numbers
                 "/nonexistent/nowhere.org"))))

(ert-deftest tibetan-cascade-subsegment-section-read ()
  "Read a LEGACY subsegment's L3 section body by number + heading."
  (tibetan-cascade-test--with-legacy-cascade-file
    (should (equal tibetan-cascade-rendering-placeholder
                   (tibetan-cascade--read-subsegment-section
                    legacy-file 105 "Rendering")))
    (should (equal "WYLIE(བདག་གིས་ལས་བྱས། )"
                   (tibetan-cascade--read-subsegment-section
                    legacy-file 105 "Wylie")))
    (should (equal "GLOSS(ཆོས་ཟབ་མོ་ཡིན།)"
                   (tibetan-cascade--read-subsegment-section
                    legacy-file 106 "Interlinear Gloss")))
    ;; Absent subsegment / heading → nil.
    (should-not (tibetan-cascade--read-subsegment-section
                 legacy-file 107 "Rendering"))
    (should-not (tibetan-cascade--read-subsegment-section
                 legacy-file 105 "No Such Heading"))))

(ert-deftest tibetan-cascade-subsegment-section-write ()
  "LEGACY write replaces exactly ONE section body; the rest is
byte-identical.  Re-read returns the new body; the needs-request
predicate flips."
  (tibetan-cascade-test--with-legacy-cascade-file
    (should (tibetan-cascade--subsegment-rendering-needs-request-p
             legacy-file 105))
    (let ((before (with-temp-buffer
                    (insert-file-contents legacy-file)
                    (buffer-string))))
      (should (tibetan-cascade--write-subsegment-section
               legacy-file 105 "Rendering" "⟪He went⟫ and asked."))
      (let ((after (with-temp-buffer
                     (insert-file-contents legacy-file)
                     (buffer-string))))
        ;; Only the one body changed: replacing new-body -> placeholder
        ;; reproduces the BEFORE image byte-for-byte.
        (should (equal before
                       (replace-regexp-in-string
                        (regexp-quote "⟪He went⟫ and asked.")
                        tibetan-cascade-rendering-placeholder
                        after t t))))
      (should (equal "⟪He went⟫ and asked."
                     (tibetan-cascade--read-subsegment-section
                      legacy-file 105 "Rendering")))
      (should-not (tibetan-cascade--subsegment-rendering-needs-request-p
                   legacy-file 105))
      ;; The sibling subsegment still needs its rendering.
      (should (tibetan-cascade--subsegment-rendering-needs-request-p
               legacy-file 106))
      ;; Writing to an absent subsegment fails soft (nil, no file touch).
      (should-not (tibetan-cascade--write-subsegment-section
                   legacy-file 107 "Rendering" "x")))))

;; ============================================================================
;; C2.3 — regenerate with preservation (the §5.26 discipline)
;; ============================================================================

(defun tibetan-cascade-test--set-l1-body (file heading body)
  "Test helper: crudely replace the body of `* HEADING' in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward (format "^\\* %s$" (regexp-quote heading)))
    (forward-line 1)
    (let ((start (point))
          (end (if (re-search-forward "^\\* " nil t)
                   (line-beginning-position)
                 (point-max))))
      (delete-region start end)
      (goto-char start)
      (insert body "\n\n"))
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest tibetan-cascade-regenerate-preserves-everything ()
  "Regenerate rebuilds the deterministic sections but preserves: user
slots, populated sentence-level Claude/DM bodies, populated
subsegment Renderings, and UNKNOWN top-level sections (§5.38-H2).
Placeholders regenerate freshly."
  (tibetan-cascade-test--with-cascade-file
    ;; Populate user + Claude + DM + rendering content.
    (tibetan-cascade-test--set-l1-body cascade-file "My Notes"
                                       "USER NOTE stays.")
    (with-temp-buffer
      (insert-file-contents cascade-file)
      ;; Sentence-level Translation body (placeholder → real).
      (goto-char (point-min))
      (re-search-forward "^\\*\\* Translation$")
      (forward-line 1)
      (let ((start (point))
            (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                     (line-beginning-position)
                   (point-max))))
        (delete-region start end)
        (goto-char start)
        (insert "The lama went and asked for dharma.\n\n"))
      ;; An UNKNOWN top-level section the regenerator must not eat.
      (goto-char (point-max))
      (insert "* Sanskrit (DharmaMitra)\nUNKNOWN SECTION body.\n\n")
      (write-region (point-min) (point-max) cascade-file nil 'silent))
    (tibetan-cascade--write-rendering cascade-file 105
                                      "⟪He went⟫ and asked.")
    ;; Regenerate with the same segs.
    (tibetan-cascade--regenerate
     cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
     (expand-file-name "doc.org" dir))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))
      ;; Preserved.
      (should (string-match-p "USER NOTE stays\\." s))
      (should (string-match-p "The lama went and asked for dharma\\." s))
      (should (string-match-p (regexp-quote "⟪He went⟫ and asked.") s))
      (should (string-match-p "^\\* Sanskrit (DharmaMitra)$" s))
      (should (string-match-p "UNKNOWN SECTION body\\." s))
      ;; Still a well-formed cascade file (marker + both subsegments).
      (should (string-match-p "^#\\+TIBETAN_LAYOUT: cascade$" s))
      (should (string-match-p "^- ⟦105⟧ " s))
      (should (string-match-p "^- ⟦106⟧ " s))
      ;; The UNPOPULATED sibling rendering is a fresh placeholder.
      (should (tibetan-cascade--rendering-needs-request-p
               cascade-file 106))
      (should-not (tibetan-cascade--rendering-needs-request-p
                   cascade-file 105)))))

(ert-deftest tibetan-cascade-regenerate-restores-vocab-without-scaffold-slot ()
  "§5.26 class (2026-09-15): a preserved L2 body whose heading the
fresh scaffold does NOT emit (the renderer-error fallback emits
only Translation + Provided Translations; this fixture's canned
renderer likewise has no Claude Vocabulary slot) must still be
RESTORED — the restore loop creates the missing heading instead
of silently dropping the body."
  (tibetan-cascade-test--with-cascade-file
    ;; Land a populated Claude Vocabulary (as --insert-claude-sections
    ;; would leave it).
    (with-temp-buffer
      (insert-file-contents cascade-file)
      (goto-char (point-min))
      (re-search-forward "^\\*\\* Translation$")
      (beginning-of-line)
      (insert "** Claude Vocabulary\n"
              "khang pa, noun, \"Haus\", the context reading\n\n")
      (write-region (point-min) (point-max) cascade-file nil 'silent))
    (tibetan-cascade--regenerate
     cascade-file 4
     '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
     (expand-file-name "doc.org" dir))
    (let ((body (tibetan-sentence--read-l2-body cascade-file
                                                "Claude Vocabulary")))
      (should body)
      (should (string-match-p "khang pa, noun, \"Haus\"" body)))
    ;; The created heading must sit INSIDE * Tibetan Analysis (above
    ;; * Footnotes), not dangle at the file end.
    (with-temp-buffer
      (insert-file-contents cascade-file)
      (let ((vocab (progn (goto-char (point-min))
                          (re-search-forward
                           "^\\*\\* Claude Vocabulary$" nil t)))
            (foot  (progn (goto-char (point-min))
                          (re-search-forward "^\\* Footnotes" nil t))))
        (should (and vocab foot (< vocab foot)))))))

(ert-deftest tibetan-cascade-regenerate-binds-claude-vocab-for-render ()
  "Regenerate binds `tibetan-analysis--claude-vocabulary-for-render'
\(parsed from the file's preserved ** Claude Vocabulary body, via
the shared `tibetan-analysis--claude-render-vars' helper) around
the scaffold call — so the Reading lines and Gloss Table row 2
render with the Claude context glosses (2026-09-15 C-für-Cascade).
Spy on the scaffold: at call time the var must hold the parsed
alist keyed by the entry's Wylie."
  (tibetan-cascade-test--with-cascade-file
    ;; Land a populated sentence-level Claude Vocabulary body.
    (with-temp-buffer
      (insert-file-contents cascade-file)
      (goto-char (point-min))
      (re-search-forward "^\\*\\* Translation$")
      (beginning-of-line)
      (insert "** Claude Vocabulary\n"
              "khang pa, noun, \"Haus\", the Claude context reading\n\n")
      (write-region (point-min) (point-max) cascade-file nil 'silent))
    (let* ((orig (symbol-function 'tibetan-cascade--scaffold))
           (captured 'unset))
      (cl-letf (((symbol-function 'tibetan-cascade--scaffold)
                 (lambda (&rest args)
                   (setq captured
                         (and (boundp
                               'tibetan-analysis--claude-vocabulary-for-render)
                              tibetan-analysis--claude-vocabulary-for-render))
                   (apply orig args))))
        (tibetan-cascade--regenerate
         cascade-file 4
         '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
         (expand-file-name "doc.org" dir)))
      (should (consp captured))
      (should (assoc "khang pa" captured)))))

(ert-deftest tibetan-cascade-regenerate-is-idempotent ()
  "A second regenerate with identical inputs is byte-identical
modulo the LAST_ANALYZED stamp."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade--write-rendering cascade-file 105
                                      "⟪He went⟫ and asked.")
    (let ((src (expand-file-name "doc.org" dir))
          (segs '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།")))
          (strip (lambda ()
                   (replace-regexp-in-string
                    "^#\\+LAST_ANALYZED: .*$" ""
                    (with-temp-buffer
                      (insert-file-contents cascade-file)
                      (buffer-string))))))
      (tibetan-cascade--regenerate cascade-file 4 segs src)
      (let ((first (funcall strip)))
        (tibetan-cascade--regenerate cascade-file 4 segs src)
        (should (equal first (funcall strip)))))))

;; ============================================================================
;; C3.1 — span extraction + response landing
;; ============================================================================

(defconst tibetan-cascade-test--response
  "## Translation
⟦105⟧The lama went to rNgog's place⟦/105⟧ and ⟦106⟧requested the dharma⟦/106⟧.
### Segment 105
Having gone to rNgog's place,
### Segment 106
[he] requested the dharma.

## Vocabulary
### Segment 105
rngog, proper noun, \"rNgog\", a disciple
### Segment 106
chos, noun, \"dharma\", the teaching

## Grammar
A two-clause chain: ablative converb then main verb.
### Segment 105
- *Verb backbone:* phyin is the past of 'gro.
### Segment 106
- *Verb backbone:* zhus is the past of zhu.

## Particles
### Segment 105
nas, nas, 2.11, ablative converb
### Segment 106
la, la, 1.4, dative

## Concept Notes
- **rNgog** — one of Mar pa's four pillars.
"
  "Canned sentence-first response for cascade landing tests.")

(ert-deftest tibetan-cascade-extract-span ()
  "Pure span extraction: own pair → span text; residual markers
stripped defensively; absent / malformed pairs → nil."
  (let ((whole "⟦105⟧The lama went⟦/105⟧ and ⟦106⟧asked⟦/106⟧."))
    (should (equal "The lama went"
                   (tibetan-cascade--extract-span whole 105)))
    (should (equal "asked" (tibetan-cascade--extract-span whole 106)))
    (should-not (tibetan-cascade--extract-span whole 107)))
  ;; Malformed: close before open, or missing close → nil.
  (should-not (tibetan-cascade--extract-span "⟦/105⟧ x ⟦105⟧" 105))
  (should-not (tibetan-cascade--extract-span "⟦105⟧never closed" 105))
  (should-not (tibetan-cascade--extract-span nil 105))
  ;; Defensive: a stray sibling marker inside the span is stripped.
  (should (equal "went and asked"
                 (tibetan-cascade--extract-span
                  "⟦105⟧went ⟦106⟧and asked⟦/105⟧" 105))))

(ert-deftest tibetan-cascade-land-response-writes-all ()
  "Landing writes the sentence-level sections (Translation stripped of
markers, Vocabulary/Grammar/Particles with their segment subsections,
Concept Notes) AND each subsegment's Rendering = its extracted span.
The per-segment SUB-TRANSLATIONS are DISCARDED by design."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade--land-response
     tibetan-cascade-test--response
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file cascade-file :cascade t :force nil))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))
      ;; Sentence-level Translation: whole, markers stripped.
      (should (string-match-p
               "The lama went to rNgog's place and requested the dharma\\."
               s))
      (should-not (string-match-p
                   "⟦" (or (tibetan-sentence--read-l2-body
                            cascade-file "Translation")
                           "")))
      ;; Vocabulary + Grammar landed with per-segment content.
      (should (string-match-p "rngog, proper noun" s))
      (should (string-match-p "two-clause chain" s))
      (should (string-match-p "one of Mar pa's four pillars" s))
      ;; Renderings = extracted spans.
      (should (equal "The lama went to rNgog's place"
                     (tibetan-cascade--read-rendering cascade-file 105)))
      (should (equal "requested the dharma"
                     (tibetan-cascade--read-rendering cascade-file 106)))
      ;; The ### sub-translations are DISCARDED.
      (should-not (string-match-p "Having gone to rNgog's place" s)))))

(ert-deftest tibetan-cascade-land-response-missing-span-stub ()
  "A segment whose span pair is absent gets a VISIBLE stub that still
counts as needs-request; the sibling lands normally.  Non-FORCE never
clobbers an already-populated Rendering."
  (tibetan-cascade-test--with-cascade-file
    ;; Pre-populate 106's rendering; feed a response whose whole
    ;; translation lacks 105's markers and carries DIFFERENT 106 text.
    (tibetan-cascade--write-rendering cascade-file 106 "KEEP ME.")
    (tibetan-cascade--land-response
     "## Translation\nNo markers for one-oh-five ⟦106⟧new text⟦/106⟧.\n"
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file cascade-file :cascade t :force nil))
    ;; 105 → stub, still needs request.
    (should (string-match-p
             "\\`\\[Claude sentence response missing Segment 105"
             (tibetan-cascade--read-rendering cascade-file 105)))
    (should (tibetan-cascade--rendering-needs-request-p
             cascade-file 105))
    ;; 106 was populated → non-FORCE landing left it alone.
    (should (equal "KEEP ME."
                   (tibetan-cascade--read-rendering cascade-file 106)))))

;; ============================================================================
;; C3.2 — cascade fire (dispatcher branch, claim, request, DM)
;; ============================================================================

(require 'tibetan-sentence-claude)

(ert-deftest tibetan-cascade-prompt-grounding-from-subsegments ()
  "The cascade prompt grounding comes from the cascade file's OWN
subsegment Interlinear sections (there are no child seg files)."
  (tibetan-cascade-test--with-cascade-file
    (let ((g (tibetan-cascade--prompt-grounding
              (list :sent-num 4 :seg-nums '(105 106))
              (expand-file-name "doc.org" dir)
              (file-name-directory cascade-file))))
      (should g)
      (should (string-match-p "=== Segment 105 ===" g))
      (should (string-match-p "=== Segment 106 ===" g))
      ;; Each block carries that unit's (non-empty) Reading line.
      (should (string-match-p "=== Segment 105 ===\n[^=\n]" g))
      (should (string-match-p "do NOT invent meanings" g)))))

(ert-deftest tibetan-cascade-fire-end-to-end ()
  "Dispatcher on a cascade document: no child seg files — one claim,
one request, landing into the single cascade file (spans + sentence
sections), one DM schedule targeting the cascade file.  A second
non-FORCE fire finds nothing needing Claude and declines."
  (tibetan-cascade-test--with-cascade-file
    (let ((src (expand-file-name "doc.org" dir))
          (dm-calls '())
          (had-gptel (featurep 'gptel)))
      (unwind-protect
          (progn
            (unless had-gptel (provide 'gptel))
            (tibetan-sentence-claude-clear-inflight)
            (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
                       (lambda (thunk &rest _)
                         (funcall thunk (lambda (_s) nil))))
                      ((symbol-function 'gptel-request)
                       (lambda (_prompt &rest args)
                         (funcall (plist-get args :callback)
                                  tibetan-cascade-test--response
                                  '(:status 200))))
                      ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
                       (lambda (&rest _) t))
                      ((symbol-function 'run-at-time)
                       (lambda (_s _r fn &rest args) (apply fn args) nil))
                      ((symbol-function 'tibetan-sentence-claude--schedule-dm)
                       (lambda (_sentence child-files sent-file _force)
                         (push (cons child-files sent-file) dm-calls)))
                      ((symbol-function 'tibetan-sentence--sentence-for-segment)
                       (lambda (_seg-id _src)
                         (list :sent-num 4 :seg-nums '(105 106)
                               :tibetan-text "བདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན།"))))
              ;; Fire — analysis-file only anchors the folder.
              (should (eq 'fired
                          (tibetan-analysis--fire-sentence-level
                           "བདག" cascade-file src 105 nil)))
              ;; Landed: spans + sentence-level Translation.
              (should (equal "The lama went to rNgog's place"
                             (tibetan-cascade--read-rendering
                              cascade-file 105)))
              (should-not (tibetan-analysis--claude-needs-request-p
                           cascade-file))
              ;; DM scheduled ONCE, against the cascade file itself.
              (should (equal (list (cons (list cascade-file) nil))
                             dm-calls))
              ;; Second non-FORCE fire: nothing needs Claude → nil.
              (tibetan-sentence-claude-clear-inflight)
              (should-not (tibetan-analysis--fire-sentence-level
                           "བདག" cascade-file src 105 nil))))
        (tibetan-sentence-claude-clear-inflight)
        (unless had-gptel
          (setq features (delq 'gptel features)))))))

;; ============================================================================
;; C4.1 — create-all + C-c u B branch
;; ============================================================================

(defmacro tibetan-cascade-test--with-cascade-source (&rest body)
  "Visit a 2-sentence cascade source; bind SRC, DIR, and BUF (current)."
  (declare (indent 0))
  `(tibetan-cascade-test--with-stub-renderer
     (let* ((dir (make-temp-file "cascade-src-" t))
            (src (expand-file-name "doc.org" dir)))
       (unwind-protect
           (progn
             (with-temp-file src
               (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                       "* Tibetan Text\n"
                       "*** Sentence 4\n"
                       "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"
                       "**** Segment 106\nཆོས་ཟབ་མོ་ཡིན།\n\n"
                       "*** Sentence 5\n"
                       "**** Segment 107\nམཐའ་མ་འདི་ཡིན།\n\n"))
             (let ((buf (find-file-noselect src)))
               (unwind-protect
                   (with-current-buffer buf ,@body)
                 (when (buffer-live-p buf)
                   (with-current-buffer buf (set-buffer-modified-p nil))
                   (kill-buffer buf)))))
         (delete-directory dir t)))))

(ert-deftest tibetan-cascade-create-all-one-file-per-sentence ()
  "C-c u B on a cascade source creates ONE cascade file per sentence
and ZERO seg files; a second run skips existing files."
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create nil))
      (tibetan-auto-analyze-document)
      (let ((analysis (expand-file-name "analysis" dir)))
        (should (= 2 (length (directory-files analysis nil "\\`sent-"))))
        (should (= 0 (length (directory-files analysis nil "\\`seg-"))))
        (let ((sent4 (car (directory-files analysis t "\\`sent-004"))))
          (should (equal '(105 106)
                         (tibetan-cascade--rendering-numbers sent4)))
          (should (string-match-p
                   "^#\\+TIBETAN_LAYOUT: cascade$"
                   (with-temp-buffer (insert-file-contents sent4)
                                     (buffer-string)))))
        ;; Second run: nothing new, nothing clobbered.
        (let ((result (tibetan-cascade-create-all)))
          (should (= 0 (plist-get result :created)))
          (should (= 2 (plist-get result :skipped))))))))

(ert-deftest tibetan-cascade-fire-defers-under-defer-mt ()
  "The cascade fire is a LEAF fire entry point — the P1 defer-MT
guard applies: a deferring source returns 'deferred and never
submits to the queue."
  (tibetan-cascade-test--with-cascade-file
    (let ((src (expand-file-name "doc.org" dir))
          (submits 0))
      ;; Flip the source to defer-MT (it already has the cascade header).
      (with-temp-buffer
        (insert-file-contents src)
        (goto-char (point-min))
        (forward-line 1)
        (insert "#+TIBETAN_DEFER_MT: t\n")
        (write-region (point-min) (point-max) src nil 'silent))
      (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
                 (lambda (&rest _) (cl-incf submits))))
        (should (eq 'deferred
                    (tibetan-cascade--fire-sentence
                     (list :sent-num 4 :seg-nums '(105 106)
                           :tibetan-text "x")
                     src (file-name-directory cascade-file))))
        (should (= 0 submits))))))

;; ============================================================================
;; C4.2 — open dispatch (C-c u A at a segment of a cascade doc)
;; ============================================================================

(ert-deftest tibetan-cascade-open-for-segment-creates-and-positions ()
  "Opening at a segment creates the cascade file when missing and
puts point on that segment's subtree; C-c u A dispatches there and
never creates a seg file."
  (tibetan-cascade-test--with-cascade-source
    (cl-letf (((symbol-function 'display-buffer-in-side-window)
               (lambda (buf &rest _) (get-buffer-window buf t))))
      (let ((tibetan-auto-fire-claude-on-create nil)
            (buf nil))
        (unwind-protect
            (progn
              ;; Direct open — file does not exist yet.
              (setq buf (tibetan-cascade-open-for-segment 106 src))
              (should (buffer-live-p buf))
              (with-current-buffer buf
                (should (string-match-p "sent-004" (buffer-name)))
                (should (looking-at "- ⟦106⟧ ")))
              ;; C-c u A from the source buffer at Segment 107 —
              ;; must route to the cascade file, not seg-107.org.
              (goto-char (point-min))
              (re-search-forward "^\\*\\*\\*\\* Segment 107")
              (tibetan-open-segment-analysis)
              (let ((analysis (expand-file-name "analysis" dir)))
                (should (= 0 (length
                              (directory-files analysis nil "\\`seg-"))))
                (should (= 2 (length
                              (directory-files analysis nil "\\`sent-"))))))
          (dolist (b (buffer-list))
            (when (and (buffer-file-name b)
                       (string-match-p "sent-00[45]"
                                       (buffer-file-name b)))
              (with-current-buffer b (set-buffer-modified-p nil))
              (kill-buffer b))))))))

;; ============================================================================
;; C4.3 — reanalyze routing + folder-batch safety
;; ============================================================================

(ert-deftest tibetan-cascade-sentence-batch-must-not-reshape-cascade-file ()
  "The sentence folder batch (C-c u r on sent files) routes cascade
files to the cascade regenerate — a cascade file must NEVER be
reshaped into the two-file sentence layout (it would lose the whole
* Subsegments tree)."
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create nil))
      (tibetan-auto-analyze-document)
      (let* ((analysis (expand-file-name "analysis" dir))
             (sent4 (car (directory-files analysis t "\\`sent-004"))))
        (tibetan-cascade--write-rendering sent4 105
                                          "KEEP ACROSS BATCH.")
        (let ((results (tibetan-sentence-batch-reanalyze
                        :folder analysis :re-request-claude nil)))
          (should results))
        ;; Still a cascade file, subsegments intact, rendering kept.
        (should (equal '(105 106)
                       (tibetan-cascade--rendering-numbers sent4)))
        (should (equal "KEEP ACROSS BATCH."
                       (tibetan-cascade--read-rendering sent4 105)))))))

(ert-deftest tibetan-cascade-reanalyze-for-segment-routes ()
  "C-c u R at a segment of a cascade source regenerates the owning
cascade file (preserving content) instead of a seg file."
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create nil))
      (tibetan-auto-analyze-document)
      (let* ((analysis (expand-file-name "analysis" dir))
             (sent4 (car (directory-files analysis t "\\`sent-004"))))
        (tibetan-cascade--write-rendering sent4 105
                                          "KEEP ACROSS REANALYZE.")
        (let ((r (tibetan-cascade-reanalyze-for-segment
                  "Sentence 4, Segment 106" src)))
          (should (plist-get r :ok)))
        (should (equal "KEEP ACROSS REANALYZE."
                       (tibetan-cascade--read-rendering sent4 105)))
        (should (= 0 (length (directory-files analysis nil "\\`seg-"))))))))

(ert-deftest tibetan-cascade-reanalyze-fire-carries-segment-enumeration ()
  "A3 (2026-09-24): der Re-Fire aus `tibetan-cascade-reanalyze-file'
\(C-c u R auf der Kaskaden-Datei) muss die Sentence-Plist MIT
`:children' bauen — `tibetan-sentence-claude--build-prompts' leitet
die `### Segment N'-Enumeration daraus ab; ohne sie enthält der
User-Prompt keine Segmenttexte und Claude kann keine korrekten
⟦N⟧-Spans liefern.  (Der Dispatcher-Pfad über den Walker war
korrekt; nur der Reanalyze-Pfad baute die Plist von Hand.)"
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create nil)
          (captured nil))
      (tibetan-auto-analyze-document)
      (let* ((analysis (expand-file-name "analysis" dir))
             (sent4 (car (directory-files analysis t "\\`sent-004"))))
        (cl-letf (((symbol-function 'tibetan-sentence-claude--claim)
                   (lambda (&rest _) t))
                  ((symbol-function 'tibetan-sentence-claude--request)
                   (lambda (sentence &rest _) (setq captured sentence)))
                  ((symbol-function 'tibetan-sentence-claude--schedule-dm)
                   (lambda (&rest _) nil)))
          (tibetan-cascade-reanalyze-file sent4 :source-file src
                                          :re-request-claude t))
        (should captured)
        (let ((children (plist-get captured :children)))
          (should children)
          (should (equal (plist-get captured :seg-nums)
                         (mapcar (lambda (c) (plist-get c :seg-num))
                                 children)))
          (dolist (c children)
            (should (> (length (string-trim (or (plist-get c :text) "")))
                       0))))
        ;; End-to-End: die Enumeration erreicht den User-Prompt.
        (let ((prompts (tibetan-sentence-claude--build-prompts
                        captured src (file-name-directory sent4))))
          (should (string-match-p "### Segment 105" (cdr prompts)))
          (should (string-match-p "### Segment 106" (cdr prompts))))))))

;; ============================================================================
;; C5.2 — tibetan-shad-split-segments (one-time source transform)
;; ============================================================================

(ert-deftest tibetan-shad-split-segments-splits-and-renumbers ()
  "Each multi-shad Segment splits into per-shad Segments; global
numbering is sequential afterwards; Working Translation siblings and
:FOLIO: drawers (on the first unit) survive; the concatenated
Tibetan is unchanged."
  (let* ((dir (make-temp-file "shad-split-" t))
         (src (expand-file-name "doc.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                    "* Tibetan Text\n"
                    "*** Sentence 1\n"
                    "**** Segment 1\n"
                    ":PROPERTIES:\n:FOLIO: 13a6\n:END:\n"
                    "ཚིག་དང་པོ། ཚིག་གཉིས་པ། ཚིག་གསུམ་པ།\n\n"
                    "**** Working Translation\nUSER DRAFT.\n\n"
                    "*** Sentence 2\n"
                    "**** Segment 2\nམཐའ་མ་འདི་ཡིན།\n\n"))
          (with-current-buffer (find-file-noselect src)
            (unwind-protect
                (progn
                  (let ((r (tibetan-shad-split-segments)))
                    (should (= 2 (plist-get r :segments-before)))
                    (should (= 4 (plist-get r :segments-after))))
                  (let ((s (buffer-string)))
                    ;; Sequential global numbering.
                    (should (equal '(1 2 3 4)
                                   (let (ns) (goto-char (point-min))
                                        (while (re-search-forward
                                                "^\\*+ Segment \\([0-9]+\\)"
                                                nil t)
                                          (push (string-to-number
                                                 (match-string 1))
                                                ns))
                                        (nreverse ns))))
                    ;; FOLIO stays on the first unit only.
                    (should (= 1 (cl-count-if
                                  (lambda (l) (equal l ":FOLIO: 13a6"))
                                  (split-string s "\n"))))
                    ;; User draft intact; all Tibetan preserved.
                    (should (string-match-p "USER DRAFT\\." s))
                    (dolist (u '("ཚིག་དང་པོ།" "ཚིག་གཉིས་པ།"
                                 "ཚིག་གསུམ་པ།" "མཐའ་མ་འདི་ཡིན།"))
                      (should (string-match-p (regexp-quote u) s)))))
              (set-buffer-modified-p nil)
              (kill-buffer))))
      (delete-directory dir t))))

(ert-deftest tibetan-shad-split-segments-refuses-two-file-corpus ()
  "The transform REFUSES when analysis/ holds seg files for this
source — renumbering would orphan them (the §5.26/§5.33 class)."
  (let* ((dir (make-temp-file "shad-guard-" t))
         (src (expand-file-name "doc.org" dir))
         (analysis (expand-file-name "analysis" dir)))
    (unwind-protect
        (progn
          (make-directory analysis)
          (with-temp-file (expand-file-name "seg-001.org" analysis)
            (insert "#+SOURCE: [[file:../doc.org::*Segment 1][doc / Segment 1]]\n"))
          (with-temp-file src
            (insert "#+TITLE: D\n\n* Tibetan Text\n*** Sentence 1\n"
                    "**** Segment 1\nཚིག་དང་པོ། ཚིག་གཉིས་པ།\n"))
          (with-current-buffer (find-file-noselect src)
            (unwind-protect
                (should-error (tibetan-shad-split-segments)
                              :type 'user-error)
              (set-buffer-modified-p nil)
              (kill-buffer))))
      (delete-directory dir t))))

;; ============================================================================
;; C7.1 — comparative-document importer (Rgyan §-layer)
;; ============================================================================

(defconst tibetan-cascade-test--comparative
  (concat
   "#+TITLE: Komparatives Übersetzungsdokument\n\n"
   "# *** GENERIERT ***\n"
   "# Hand-Edits gehen beim Re-Run verloren.\n\n"
   "** §167   :seg_1565_to_1573:\n"
   ":PROPERTIES:\n:SECTION: 167\n:B2_SEG_START: 1565\n"
   ":B2_SEG_END: 1573\n:END:\n\n"
   "*** Tibetisch (B2)\n\n"
   "བདེན་པར་ཡོད་འཛིན་པ་གཉིས་ཁྱད་པར་ཕྱེ་དགོས།\n\n"
   "*** Wylie\n\n/bden par yod 'dzin pa/\n\n"
   "*** Lopez 2006\n:PROPERTIES:\n:READ_ONLY: t\n:END:\n\n"
   "*§167.* COPYRIGHTED LOPEZ TEXT.\n\n"
   "*** Wangjié & Mulligan\n:PROPERTIES:\n:READ_ONLY: t\n:END:\n\n"
   "*§167.* COPYRIGHTED WM TEXT.\n\n"
   "** §168   :seg_1574_to_1581:\n"
   ":PROPERTIES:\n:SECTION: 168\n:B2_SEG_START: 1574\n"
   ":B2_SEG_END: 1581\n:END:\n\n"
   "*** Tibetisch (B2)\n\n"
   "སྟོང་ཉིད་བདེན་འཛིན་དང་ཡོད་ཙམ་གཉིས།\n\n"
   "*** Lopez 2006\n\n*§168.* MORE LOPEZ.\n")
  "Two-§ miniature of the generator-owned comparative document.")

(ert-deftest tibetan-cascade-import-comparative-structure ()
  "The importer produces a cascade CAT source: one Section per § with
the Lopez anchors carried, ONE initial Segment per § with the B2
text — and NEVER copies the copyrighted reference translations."
  (let* ((dir (make-temp-file "rgyan-import-" t))
         (comp (expand-file-name "Rgyan-comparative.org" dir))
         (out (expand-file-name "Rgyan-cat.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file comp
            (insert tibetan-cascade-test--comparative))
          (let ((r (tibetan-cascade-import-comparative comp out)))
            (should (= 2 (plist-get r :sections))))
          (let ((s (with-temp-buffer (insert-file-contents out)
                                     (buffer-string))))
            ;; Cascade CAT headers + the §-refs pointer.
            (should (string-match-p "^#\\+TIBETAN_LAYOUT: cascade$" s))
            (should (string-match-p
                     "^#\\+TIBETAN_SECTION_REFS: Rgyan-comparative\\.org$"
                     s))
            ;; Sections carry the Lopez anchors.
            (should (string-match-p "^\\*\\* Section §167$" s))
            (should (string-match-p "^:LOPEZ_SECTION: 167$" s))
            (should (string-match-p "^:B2_SEG_START: 1565$" s))
            ;; One initial segment per §, globally numbered.
            (should (string-match-p "^\\*\\*\\* Segment 1$" s))
            (should (string-match-p "^\\*\\*\\* Segment 2$" s))
            (should (string-match-p "ཁྱད་པར་ཕྱེ་དགོས།" s))
            ;; COPYRIGHT: reference bodies and Wylie never imported.
            (should-not (string-match-p "COPYRIGHTED" s))
            (should-not (string-match-p "MORE LOPEZ" s))
            (should-not (string-match-p "bden par yod" s))))
      (delete-directory dir t))))

;; ============================================================================
;; C7.2 — §-refs ¶-context injection (USER prompt only)
;; ============================================================================

(defmacro tibetan-cascade-test--with-rgyan-source (&rest body)
  "Bind DIR, REFS (mini comparative), SRC (cascade source with a
Section §167 wrapping Sentence 4 → segments 105/106)."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "rgyan-refs-" t))
          (refs (expand-file-name "Rgyan-comparative.org" dir))
          (src (expand-file-name "Rgyan-cat.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file refs
             (insert tibetan-cascade-test--comparative))
           (with-temp-file src
             (insert "#+TITLE: Rgyan CAT\n"
                     "#+TIBETAN_LAYOUT: cascade\n"
                     "#+TIBETAN_SECTION_REFS: Rgyan-comparative.org\n\n"
                     "* Tibetan Text\n"
                     "** Section §167\n"
                     ":PROPERTIES:\n:LOPEZ_SECTION: 167\n:END:\n\n"
                     "*** Sentence 4\n"
                     "**** Segment 105\nབདེན་པར་ཡོད་འཛིན།\n\n"
                     "**** Segment 106\nཁྱད་པར་ཕྱེ་དགོས།\n\n"))
           ,@body)
       (delete-directory dir t))))

(ert-deftest tibetan-cascade-section-refs-metadata-and-block ()
  "`#+TIBETAN_SECTION_REFS:' parses into :section-refs; the block
carries the §'s reference translations (all L3 children except the
B2 Tibetan and Wylie) with the context-only instruction."
  (tibetan-cascade-test--with-rgyan-source
    (should (equal "Rgyan-comparative.org"
                   (plist-get (tibetan-analysis--read-source-metadata src)
                              :section-refs)))
    (let ((block (tibetan-cascade--section-refs-block
                  (list :sent-num 4 :seg-nums '(105 106)) src)))
      (should block)
      (should (string-match-p "Lopez §167" block))
      (should (string-match-p "COPYRIGHTED LOPEZ TEXT" block))
      (should (string-match-p "Wangjié & Mulligan" block))
      (should (string-match-p "COPYRIGHTED WM TEXT" block))
      ;; The B2 Tibetan and Wylie children are NOT reference
      ;; translations — excluded.
      (should-not (string-match-p "bden par yod" block))
      ;; Context-only instruction present.
      (should (string-match-p "context" block)))
    ;; Sentence in a section without refs resolution → nil, no error.
    (should-not (tibetan-cascade--section-refs-block
                 (list :sent-num 99) src))))

(ert-deftest tibetan-cascade-build-prompts-injects-section-refs ()
  "The sentence-first USER prompt carries the §-refs block for a
cascade document with #+TIBETAN_SECTION_REFS (system prompt stays
refs-free — cache-constant)."
  (tibetan-cascade-test--with-rgyan-source
    (let* ((prompts (tibetan-sentence-claude--build-prompts
                     (list :sent-num 4 :seg-nums '(105 106)
                           :tibetan-text "བདེན་པར་ཡོད་འཛིན། ཁྱད་པར་ཕྱེ་དགོས།")
                     src nil)))
      (should (string-match-p "COPYRIGHTED LOPEZ TEXT" (cdr prompts)))
      (should-not (string-match-p "COPYRIGHTED LOPEZ TEXT"
                                  (car prompts))))))

;; ============================================================================
;; CH2 — Claude chunk-fire: collector, prompts, landing
;; ============================================================================

(ert-deftest tibetan-cascade-collect-section-chunks ()
  "Sentences group into section chunks with label + Lopez number; a
document without Sections forms one implicit chunk; the segment cap
splits oversized chunks at sentence boundaries."
  (with-temp-buffer
    (org-mode)
    (insert "* Tibetan Text\n"
            "** Section §167\n"
            ":PROPERTIES:\n:LOPEZ_SECTION: 167\n:END:\n\n"
            "*** Sentence 1\n**** Segment 1\nཀ།\n\n**** Segment 2\nཁ།\n\n"
            "*** Sentence 2\n**** Segment 3\nག།\n\n"
            "** Section §168\n"
            ":PROPERTIES:\n:LOPEZ_SECTION: 168\n:END:\n\n"
            "*** Sentence 3\n**** Segment 4\nང།\n\n")
    (let ((chunks (tibetan-cascade--collect-section-chunks)))
      (should (= 2 (length chunks)))
      (should (= 167 (plist-get (car chunks) :lopez)))
      (should (equal '(1 2)
                     (mapcar (lambda (s) (plist-get s :sent-num))
                             (plist-get (car chunks) :sentences))))
      (should (= 168 (plist-get (cadr chunks) :lopez)))))
  ;; Cap: 3 one-segment sentences with max 2 segments per chunk → 2+1.
  (with-temp-buffer
    (org-mode)
    (insert "* Tibetan Text\n"
            "*** Sentence 1\n**** Segment 1\nཀ།\n\n"
            "*** Sentence 2\n**** Segment 2\nཁ།\n\n"
            "*** Sentence 3\n**** Segment 3\nག།\n\n")
    (let* ((tibetan-cascade-chunk-max-segments 2)
           (chunks (tibetan-cascade--collect-section-chunks)))
      (should (= 2 (length chunks)))
      (should (= 2 (length (plist-get (car chunks) :sentences))))
      (should (= 1 (length (plist-get (cadr chunks) :sentences)))))))

(ert-deftest tibetan-cascade-chunk-prompts-translation-only ()
  "Chunk prompts: the system carries the CHUNK addendum (constant per
document — its own cache prefix); the user enumerates every segment
and demands ONLY the marked Translation."
  (let* ((chunk (list :label "Section §167" :lopez 167
                      :sentences
                      (list (list :sent-num 1
                                  :segs '((1 . "ཀ།") (2 . "ཁ།")))
                            (list :sent-num 2 :segs '((3 . "ག།"))))))
         (p1 (tibetan-cascade--build-chunk-prompts chunk "/tmp/doc.org"))
         (p2 (tibetan-cascade--build-chunk-prompts chunk "/tmp/doc.org")))
    ;; System constant across calls; contains the chunk contract.
    (should (equal (car p1) (car p2)))
    (should (string-match-p "CHUNK MODE" (car p1)))
    (should (string-match-p "ONLY" (car p1)))
    ;; User: passage + full enumeration + the marker instruction.
    (should (string-match-p "### Segment 1" (cdr p1)))
    (should (string-match-p "### Segment 3" (cdr p1)))
    (should (string-match-p "⟦" (cdr p1)))))

(ert-deftest tibetan-cascade-land-chunk-response ()
  "Landing a chunk response: every subsegment Rendering = its span;
every sentence Translation = ITS spans joined in ENGLISH order under
a chunk label; missing spans → visible stubs; populated files
untouched non-FORCE."
  (tibetan-cascade-test--with-cascade-file
    ;; Our fixture file holds Sentence 4 = segments 105+106.  Feed a
    ;; chunk response where ENGLISH order inverts the segments.
    (tibetan-cascade--land-chunk-response
     "## Translation\n⟦106⟧The dharma is deep⟦/106⟧ — ⟦105⟧so he acted⟦/105⟧."
     (list :chunk t :force nil
           :label "Section §167"
           :sentences (list (list :sent-num 4 :seg-nums '(105 106)
                                  :file cascade-file))))
    (should (equal "so he acted"
                   (tibetan-cascade--read-rendering cascade-file 105)))
    (should (equal "The dharma is deep"
                   (tibetan-cascade--read-rendering cascade-file 106)))
    (let ((s (with-temp-buffer (insert-file-contents cascade-file)
                               (buffer-string))))
      ;; Sentence Translation: English order (106 before 105), labeled.
      (should (string-match-p
               "The dharma is deep — so he acted" s))
      (should (string-match-p "Section §167 chunk" s))
      ;; Markers stripped from the TRANSLATION body (the Reading
      ;; view's ⟦N⟧ keys legitimately remain).
      (should-not (string-match-p
                   "⟦" (or (tibetan-sentence--read-l2-body
                            cascade-file "Translation")
                           ""))))))

;; ============================================================================
;; CH2c — fire-section (claim + queue + landing through §5.40 machinery)
;; ============================================================================

(ert-deftest tibetan-cascade-fire-section-end-to-end ()
  "One chunk claim → one queue submit → landing into every member
file; ONE DM section schedule; a second non-FORCE fire declines."
  (tibetan-cascade-test--with-cascade-file
    (let ((src (expand-file-name "doc.org" dir))
          (dm-calls 0)
          (had-gptel (featurep 'gptel)))
      (unwind-protect
          (progn
            (unless had-gptel (provide 'gptel))
            (tibetan-sentence-claude-clear-inflight)
            (cl-letf (((symbol-function 'tibetan-claude-queue-submit)
                       (lambda (thunk &rest _)
                         (funcall thunk (lambda (_s) nil))))
                      ((symbol-function 'gptel-request)
                       (lambda (_prompt &rest args)
                         (funcall (plist-get args :callback)
                                  "## Translation\n⟦105⟧He acted⟦/105⟧ and ⟦106⟧the dharma is deep⟦/106⟧."
                                  '(:status 200))))
                      ((symbol-function 'tibetan-analysis--ensure-gptel-ready)
                       (lambda (&rest _) t))
                      ((symbol-function 'run-at-time)
                       (lambda (_s _r fn &rest args) (apply fn args) nil))
                      ((symbol-function 'tibetan-cascade--schedule-dm-section)
                       (lambda (&rest _) (cl-incf dm-calls))))
              (let ((chunk (list :label "Section §167" :lopez 167
                                 :sentences
                                 (list (list :sent-num 4
                                             :segs '((105 . "བདག")
                                                     (106 . "ཆོས")))))))
                (should (eq 'fired
                            (tibetan-cascade--fire-section
                             chunk src
                             (file-name-directory cascade-file))))
                (should (equal "He acted"
                               (tibetan-cascade--read-rendering
                                cascade-file 105)))
                (should (= 1 dm-calls))
                ;; Everything landed → second non-FORCE fire declines.
                (tibetan-sentence-claude-clear-inflight)
                (should-not (tibetan-cascade--fire-section
                             chunk src
                             (file-name-directory cascade-file))))))
        (tibetan-sentence-claude-clear-inflight)
        (unless had-gptel
          (setq features (delq 'gptel features)))))))

;; ============================================================================
;; CH3 — DharmaMitra chunk-level fire
;; ============================================================================

(ert-deftest tibetan-dm-fire-section-writes-all-members ()
  "ONE chat-translate per section; the whole-section translation
lands in EVERY member file's nested DM slot under the section
label; a populated member is skipped non-FORCE."
  (tibetan-cascade-test--with-cascade-file
    (let ((calls 0))
      (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
                 (lambda (_text &rest _)
                   (cl-incf calls)
                   "The whole section, coherently.")))
        (should (tibetan-dharmamitra-translation-fire-section
                 "བདག ཆོས" "Section §167" (list cascade-file)))
        (should (= 1 calls))
        (let ((s (with-temp-buffer (insert-file-contents cascade-file)
                                   (buffer-string))))
          (should (string-match-p "(Section §167)" s))
          (should (string-match-p "The whole section, coherently\\." s))))
      ;; Populated now → a second non-FORCE fire makes NO api call.
      (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
                 (lambda (&rest _) (cl-incf calls) "OVERWRITE?")))
        (tibetan-dharmamitra-translation-fire-section
         "བདག ཆོས" "Section §167" (list cascade-file))
        (should (= 1 calls))))))

;; ============================================================================
;; BUG (2026-07-29): DM's SSE stream is unreadable for url.el → curl
;; ============================================================================

(ert-deftest tibetan-dm-http-post-uses-curl ()
  "`--http-post' transports via curl when available: DM's backend
now streams SSE with no end url.el can detect (live symptom:
`200 OK' + EMPTY body from url-retrieve while curl streamed the
same request fine), which silently broke EVERY DharmaMitra call."
  (skip-unless (executable-find "curl"))
  ;; Transport self-test: past the suite's no-network gate
  ;; (call-process-region stubbed — offline).
  (defvar tibetan-test-allow-dm-transport)
  (let ((tibetan-test-allow-dm-transport t)
        captured-args)
    (cl-letf (((symbol-function 'call-process-region)
               (lambda (_start _end program &optional _delete buffer
                               _display &rest args)
                 (setq captured-args (cons program args))
                 (with-current-buffer (if (bufferp buffer) buffer
                                        (current-buffer))
                   (insert "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n"))
                 0)))
      (let ((response (tibetan-dharmamitra-api--http-post
                       "/chat-translate/v1/chat/completions"
                       "{\"stream\":true}")))
        (should (equal "curl" (car captured-args)))
        (should (member "--data-binary" captured-args))
        (should (cl-some (lambda (a)
                           (and (stringp a)
                                (string-match-p "chat-translate" a)))
                         captured-args))
        (should (string-match-p "delta" response))))))

(ert-deftest tibetan-cascade-create-all-fires-chunks ()
  "After the live evaluation (9/9 spans on Rgyan §167), cascade
auto-fire is CHUNKED: create-all fires one section call per chunk —
never per-sentence fires."
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create t)
          (chunk-fires 0) (sentence-fires 0))
      (cl-letf (((symbol-function 'tibetan-cascade--fire-section)
                 (lambda (&rest _) (cl-incf chunk-fires) 'fired))
                ((symbol-function 'tibetan-cascade--fire-sentence)
                 (lambda (&rest _) (cl-incf sentence-fires) 'fired)))
        (tibetan-cascade-create-all))
      ;; The 2-sentence fixture has no Sections → ONE implicit chunk.
      (should (= 1 chunk-fires))
      (should (= 0 sentence-fires)))))

;; ============================================================================
;; V1+V2 (2026-07-30) — defer-MT visibility
;; ============================================================================
;; Live Portfolio confusion: the generic placeholders read as a
;; FAILURE when #+TIBETAN_DEFER_MT was doing its job.  The scaffold
;; must SAY why nothing fired — and the explanatory placeholder must
;; still count as needs-request everywhere (it starts with
;; "[Awaiting", so every §5.8/§5.29 recognizer accepts it; these
;; tests lock that so future prefix drift cannot break it).

(ert-deftest tibetan-cascade-defer-mt-placeholders-explain ()
  "A defer-MT document's cascade files carry the explanatory
placeholder in Translation, DM, and Rendering slots — and all three
still register as needing a request."
  (tibetan-cascade-test--with-stub-renderer
    (let* ((dir (make-temp-file "defer-vis-" t))
           (src (expand-file-name "doc.org" dir)))
      (unwind-protect
          (progn
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n"
                      "#+TIBETAN_DEFER_MT: t\n\n"
                      "* Tibetan Text\n*** Sentence 4\n"
                      "**** Segment 105\nབདག\n\n"))
            (let ((f (tibetan-cascade--create-file
                      4 '((105 . "བདག")) src)))
              (let ((s (with-temp-buffer (insert-file-contents f)
                                         (buffer-string))))
                ;; The explanation is present, the generic texts gone.
                (should (string-match-p "MT deferred" s))
                (should (string-match-p "TIBETAN_DEFER_MT" s))
                (should-not (string-match-p
                             (regexp-quote "[Requesting translation...]")
                             s))
                (should-not (string-match-p
                             (regexp-quote "[Awaiting DharmaMitra…]") s)))
              ;; Recognizer lock: everything still needs a request.
              (should (tibetan-analysis--claude-needs-request-p f))
              (should (tibetan-dharmamitra-translation-needs-request-p
                       f "Tibetan"))
              (should (tibetan-cascade--rendering-needs-request-p
                       f 105))))
        (delete-directory dir t)))))

(ert-deftest tibetan-cascade-no-defer-keeps-generic-placeholders ()
  "Without the defer header the scaffold is unchanged."
  (tibetan-cascade-test--with-cascade-file
    (should (string-match-p
             (regexp-quote "[Awaiting DharmaMitra…]")
             (with-temp-buffer (insert-file-contents cascade-file)
                               (buffer-string))))))

(ert-deftest tibetan-cascade-scaffold-binds-source-directory ()
  "The scaffold's renderer calls run with `default-directory' at the
SOURCE's directory — the Resources/wordlist resolution
\(`tibetan-find-resources-folder') falls back to `default-directory'
in headless runs (2026-06-03 corpus-wipe lesson), so a batch caller's
alien cwd must not decide whether ★ glosses appear (V3 refresh
2026-08-10: all 8 Portfolio files lost their wordlist glosses this
way)."
  (let* ((dir (make-temp-file "cascade-cwd-" t))
         (alien (make-temp-file "alien-cwd-" t))
         (src (expand-file-name "doc.org" dir))
         (seen-dirs '()))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                    "* Tibetan Text\n*** Sentence 1\n"
                    "**** Segment 1\nབདག\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (_text &rest _)
                       (push (file-truename default-directory) seen-dirs)
                       "** Wylie Transliteration\nW\n\n")))
            (let ((default-directory (file-name-as-directory alien)))
              (tibetan-cascade--scaffold 1 '((1 . "བདག")) src)))
          (should seen-dirs)
          (should (cl-every
                   (lambda (d)
                     (equal d (file-truename (file-name-as-directory dir))))
                   seen-dirs)))
      (delete-directory dir t)
      (delete-directory alien t))))

(ert-deftest tibetan-cascade-scaffold-binds-target-lang ()
  "The scaffold's renderer calls see `tibetan-analysis--target-lang'
from the SOURCE's #+TIBETAN_TARGET_LANG header — the bilingual
`DE // EN' gloss selection (Pass 5c) reads that dynamic var, and the
cascade temp-buffer context never bound it, so the Portfolio's
curated German glosses rendered English-only (W2, 2026-08-11)."
  (let* ((dir (make-temp-file "cascade-lang-" t))
         (src (expand-file-name "doc.org" dir))
         (seen '()))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n"
                    "#+TIBETAN_TARGET_LANG: de\n\n"
                    "* Tibetan Text\n*** Sentence 1\n"
                    "**** Segment 1\nབདག\n\n"))
          (cl-letf (((symbol-function 'tibetan-analysis-generate-content)
                     (lambda (_text &rest _)
                       (push (and (boundp 'tibetan-analysis--target-lang)
                                  tibetan-analysis--target-lang)
                             seen)
                       "** Wylie Transliteration\nW\n\n")))
            (tibetan-cascade--scaffold 1 '((1 . "བདག")) src))
          (should seen)
          (should (cl-every (lambda (l) (equal l "de")) seen)))
      (delete-directory dir t))))

;; ============================================================================
;; R4 (2026-08-12) — Reading-section assembler
;; ============================================================================

(ert-deftest tibetan-cascade-renderings-list-body-shape ()
  "The Renderings list: one `- ⟦N⟧ placeholder' line per unit, keyed
by GLOBAL segment number."
  (let ((body (tibetan-cascade--renderings-list-body
               '((105 . "བདག།") (106 . "ཆོས།")))))
    (should (equal (concat "- ⟦105⟧ " tibetan-cascade-rendering-placeholder
                           "\n"
                           "- ⟦106⟧ " tibetan-cascade-rendering-placeholder)
                   body))))

(ert-deftest tibetan-cascade-reading-section-structure ()
  "The assembled * Reading section (COMBINED, 2nd iteration): one
`** Interlinear' layer of combined lines, then the Renderings list."
  (cl-letf (((symbol-function 'tibetan-reading-decorated-lines)
             (lambda (units)
               (mapcar (lambda (u) (format "LINE(%s)" u)) units))))
    (let ((s (tibetan-cascade--reading-section
              '((105 . "བདག།") (106 . "ཆོས།")))))
      (should (string-match-p "^\\* Reading$" s))
      (let ((il (string-match "^\\*\\* Interlinear$" s))
            (re (string-match "^\\*\\* Renderings$" s)))
        (should (and il re))
        (should (< il re)))
      ;; The retired separate Wylie layer is gone.
      (should-not (string-match-p "^\\*\\* Wylie$" s))
      (should (string-match-p "^LINE(བདག།)$" s))
      (should (string-match-p "^LINE(ཆོས།)$" s))
      (should (string-match-p "^- ⟦105⟧ \\[Awaiting" s))
      (should (string-match-p "^- ⟦106⟧ \\[Awaiting" s)))))

(ert-deftest tibetan-cascade-reading-section-emits-gloss-tables ()
  "2026-09-15 (Masterarbeit three-view plan, Carsten's placement
decision): `** Gloss Tables' is the FIRST Reading child — captioned
three-row tables per shad unit BEFORE the Interlinear — carrying a
:GENERATED_HASH: drawer (the edit-protection anchor: hash of the
emitted body, so a later regenerate can tell generated from
hand-edited)."
  (let (seen-level)
    (cl-letf (((symbol-function 'tibetan-reading-decorated-lines)
               (lambda (units)
                 (mapcar (lambda (u) (format "LINE(%s)" u)) units)))
              ((symbol-function 'tibetan-gloss-table-render-captioned)
               (lambda (_segs _vocab &optional level)
                 (setq seen-level level)
                 "*** Segment 105\n| CAPTBL |")))
      (let ((s (tibetan-cascade--reading-section
                '((105 . "བདག།") (106 . "ཆོས།")))))
        ;; Carsten's 2026-09-16 form: Segment number as HEADING.
        (should (eql 3 seen-level))
        (let ((gt (string-match "^\\*\\* Gloss Tables$" s))
              (il (string-match "^\\*\\* Interlinear$" s))
              (re (string-match "^\\*\\* Renderings$" s)))
          (should (and gt il re))
          (should (< gt il re)))
        (should (string-match-p "^| CAPTBL |$" s))
        (should (string-match-p "^\\*\\*\\* Segment 105$" s))
        ;; Edit-protection drawer with the body hash.
        (should (string-match-p
                 (concat ":GENERATED_HASH: "
                         (sha1 "*** Segment 105\n| CAPTBL |"))
                 s))))))

(ert-deftest tibetan-cascade-reading-section-omits-gloss-tables-when-empty ()
  "No renderable unit (or the gloss-table module absent) → no
`** Gloss Tables' heading at all — no empty-section litter, the
degraded scaffold stays valid."
  (cl-letf (((symbol-function 'tibetan-reading-decorated-lines)
             (lambda (units)
               (mapcar (lambda (u) (format "LINE(%s)" u)) units)))
            ((symbol-function 'tibetan-gloss-table-render-captioned)
             (lambda (_segs _vocab &optional _level) nil)))
    (let ((s (tibetan-cascade--reading-section '((105 . "བདག།")))))
      (should-not (string-match-p "^\\*\\* Gloss Tables$" s))
      (should (string-match-p "^\\*\\* Interlinear$" s)))))

(defun tibetan-cascade-test--edit-gloss-tables (file marker)
  "Append MARKER as an extra line to FILE's `** Gloss Tables' body,
WITHOUT touching the :GENERATED_HASH: drawer — simulating a hand
edit (the hash now mismatches the body)."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Gloss Tables$")
    (let ((end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                   (match-beginning 0)
                 (point-max))))
      (goto-char end)
      (skip-chars-backward "\n")
      (insert "\n" marker))
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest tibetan-cascade-regenerate-refreshes-unedited-gloss-tables ()
  "Invariant guard: an UNTOUCHED (hash-matching) `** Gloss Tables'
section is regenerated fresh — new content, new hash."
  (tibetan-cascade-test--with-cascade-file
    (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
               (lambda (_segs _vocab &optional _level) "Unit 1 — Segment 105\n| NEU |")))
      (tibetan-cascade--regenerate
       cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
       (expand-file-name "doc.org" dir)))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file) (buffer-string))))
      (should (string-match-p "^| NEU |$" s))
      (should (string-match-p
               (concat ":GENERATED_HASH: "
                       (sha1 "Unit 1 — Segment 105\n| NEU |"))
               s)))))

(ert-deftest tibetan-cascade-regenerate-preserves-edited-gloss-tables ()
  "Carsten's edit-protection decision (2026-09-15): once he has
EDITED the tables (body no longer matches the stored hash), a
regenerate preserves the section byte-for-byte — his decision
layer, like the handout's hand-tuned tables."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade-test--edit-gloss-tables cascade-file
                                             "EDITIERT-VON-CARSTEN")
    (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
               (lambda (_segs _vocab &optional _level) "Unit 1 — Segment 105\n| NEU |")))
      (tibetan-cascade--regenerate
       cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
       (expand-file-name "doc.org" dir)))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file) (buffer-string))))
      ;; The edit survives; the fresh render did NOT land.
      (should (string-match-p "^EDITIERT-VON-CARSTEN$" s))
      (should-not (string-match-p "^| NEU |$" s))
      ;; Still the first Reading child.
      (let ((gt (string-match "^\\*\\* Gloss Tables$" s))
            (il (string-match "^\\*\\* Interlinear$" s)))
        (should (and gt il (< gt il)))))
    ;; Second regenerate: still byte-stable (modulo LAST_ANALYZED).
    (let ((before (with-temp-buffer
                    (insert-file-contents cascade-file) (buffer-string))))
      (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
                 (lambda (_segs _vocab &optional _level) "Unit 1 — Segment 105\n| NEU |")))
        (tibetan-cascade--regenerate
         cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
         (expand-file-name "doc.org" dir)))
      (let ((after (with-temp-buffer
                     (insert-file-contents cascade-file) (buffer-string)))
            (strip (lambda (x) (replace-regexp-in-string
                                "^#\\+LAST_ANALYZED:.*$" "" x))))
        (should (equal (funcall strip before) (funcall strip after)))))))

(ert-deftest tibetan-cascade-regenerate-edited-survives-scaffold-skip ()
  "Edited tables survive even when the fresh scaffold would OMIT
the section (renderer yields nothing): the preserved block is
re-inserted as the first Reading child (eb9b573 pattern)."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade-test--edit-gloss-tables cascade-file
                                             "EDITIERT-VON-CARSTEN")
    (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
               (lambda (_segs _vocab &optional _level) nil)))
      (tibetan-cascade--regenerate
       cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
       (expand-file-name "doc.org" dir)))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file) (buffer-string))))
      (should (string-match-p "^EDITIERT-VON-CARSTEN$" s))
      (let ((gt (string-match "^\\*\\* Gloss Tables$" s))
            (il (string-match "^\\*\\* Interlinear$" s)))
        (should (and gt il (< gt il)))))))

(ert-deftest tibetan-cascade-regenerate-keeps-readers-with-gloss-tables ()
  "Adjacent lock: on a regenerated file WITH the new `** Gloss
Tables' section, the Reading readers still resolve — the
renderings region, a landed ⟦N⟧ body, and the needs-request gate."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade--write-rendering cascade-file 105 "⟪Er ging⟫ los.")
    (tibetan-cascade--regenerate
     cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
     (expand-file-name "doc.org" dir))
    (should (equal "⟪Er ging⟫ los."
                   (tibetan-cascade--read-rendering cascade-file 105)))
    (should-not (tibetan-cascade--rendering-needs-request-p
                 cascade-file 105))
    (should (tibetan-cascade--rendering-needs-request-p
             cascade-file 106))))

;; ============================================================================
;; R8 (2026-08-12) — the migration: preserve-mode regenerate of a
;; LEGACY file produces the Reading layout with everything carried.
;; ============================================================================

(ert-deftest tibetan-cascade-regenerate-migrates-legacy-file ()
  "Regenerating an OLD * Subsegments file yields the new layout:
landed renderings verbatim on their ⟦N⟧ lines, user notes and
unknown L1 sections preserved, the retired Subsegments tree DROPPED
\(owned-legacy — never re-appended as unknown)."
  (tibetan-cascade-test--with-legacy-cascade-file
    ;; A landed rendering + a user note + an unknown L1 section.
    (tibetan-cascade--write-subsegment-section
     legacy-file 105 "Rendering" "Der Lama ging zu rNgog.")
    (tibetan-cascade-test--set-l1-body legacy-file "My Notes"
                                       "MIGRATION NOTE stays.")
    (with-temp-buffer
      (insert-file-contents legacy-file)
      (goto-char (point-max))
      (insert "* Kolophon\nUNKNOWN survives.\n\n")
      (write-region (point-min) (point-max) legacy-file nil 'silent))
    (tibetan-cascade-test--with-stub-renderer
      (tibetan-cascade--regenerate
       legacy-file 4
       '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
       src))
    (let ((s (with-temp-buffer (insert-file-contents legacy-file)
                               (buffer-string))))
      ;; New layout in, old tree out.
      (should (string-match-p "^\\* Reading$" s))
      (should-not (string-match-p "^\\* Subsegments$" s))
      (should-not (string-match-p "^\\*\\* Segment 105$" s))
      (should-not (string-match-p "^\\*+ Phonetics$" s))
      ;; Carried: rendering verbatim on its line, user + unknown L1.
      (should (string-match-p "^- ⟦105⟧ Der Lama ging zu rNgog\\.$" s))
      (should (string-match-p "MIGRATION NOTE stays\\." s))
      (should (string-match-p "^\\* Kolophon$" s))
      (should (string-match-p "UNKNOWN survives\\." s)))
    ;; The unpopulated unit regenerated as a placeholder line.
    (should (tibetan-cascade--rendering-needs-request-p legacy-file 106))
    ;; Idempotent: a second pass changes nothing but the date stamp.
    (let ((strip (lambda ()
                   (replace-regexp-in-string
                    "^#\\+LAST_ANALYZED: .*$" ""
                    (with-temp-buffer
                      (insert-file-contents legacy-file)
                      (buffer-string))))))
      (let ((first (funcall strip)))
        (tibetan-cascade-test--with-stub-renderer
          (tibetan-cascade--regenerate
           legacy-file 4
           '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
           src))
        (should (equal first (funcall strip)))))))

;; ============================================================================
;; R10 (2026-08-12) — per-unit Sentence Structure
;; ============================================================================

(ert-deftest tibetan-cascade-sentence-structure-per-unit ()
  "The cascade Sentence Structure body parses EACH shad unit
separately (one verb-first tree per unit, in order) — never the
joined sentence (the fused-token / hallucinated-main-verb class the
live sent-001 showed)."
  (let (parsed-units)
    ;; 2026-09-16: delegates to the shared TABULAR renderer; the
    ;; legacy tree body stays as the fallback.  Delegation spy +
    ;; the per-unit no-cross-shad-glue property on the FALLBACK.
    (cl-letf (((symbol-function 'tibetan-analysis--render-structure-tables)
               (lambda (segs)
                 (setq parsed-units (mapcar #'car segs))
                 "TABULAR-BODY")))
      (should (equal "TABULAR-BODY"
                     (tibetan-cascade--sentence-structure-body
                      '((105 . "བདག་གིས་ལས་བྱས།") (106 . "ཆོས་ཟབ་མོ་ཡིན།")))))
      (should (equal '(105 106) parsed-units)))
    (setq parsed-units nil)
    (cl-letf (((symbol-function 'tibetan-extract-verbs-compound-aware)
               (lambda (_text words _mwus)
                 (list `((lemma . ,(car words)) (source . hill)))))
              ((symbol-function 'tibetan-analysis--render-sentence-tree)
               (lambda (words _verbs _mwus)
                 (push (car words) parsed-units)
                 (format "TREE(%s)" (car words)))))
      (let ((body (tibetan-cascade--sentence-structure-body-trees
                   '((105 . "བདག་གིས་ལས་བྱས།") (106 . "ཆོས་ཟབ་མོ་ཡིན།")))))
        (should body)
        ;; One tree per unit, labeled, in order.
        (should (string-match-p "^Unit 1 — Segment 105$" body))
        (should (string-match-p "^Unit 2 — Segment 106$" body))
        (should (string-match-p "TREE(བདག)" body))
        (should (string-match-p "TREE(ཆོས)" body))
        (should (< (string-match "Unit 1" body)
                   (string-match "Unit 2" body)))
        ;; Each parse saw ONLY its unit's tokens (no cross-shad glue).
        (should (equal '("བདག" "ཆོས") (nreverse parsed-units)))))))

(ert-deftest tibetan-cascade-scaffold-uses-per-unit-structure ()
  "The scaffold's ** Sentence Structure carries the per-unit body."
  (tibetan-cascade-test--with-stub-renderer
    (cl-letf (((symbol-function 'tibetan-cascade--sentence-structure-body)
               (lambda (_segs) "Unit 1 — Segment 105\nPERUNIT-TREE")))
      (let ((s (tibetan-cascade--scaffold
                4 '((105 . "བདག།")) "/tmp/doc.org")))
        (should (string-match-p "^\\*\\* Sentence Structure$" s))
        (should (string-match-p "PERUNIT-TREE" s))))))

;; ============================================================================
;; R5 (2026-08-12) — dual-format rendering I/O
;; The `- ⟦N⟧ body' line under * Reading/** Renderings is the new
;; format; every primitive falls back to the legacy `** Segment N /
;; *** Rendering' subtree, so old and new files are equally servable
;; while the scaffold still emits the old layout (the migration IS
;; the dual format).
;; ============================================================================

(defmacro tibetan-cascade-test--with-new-format-file (&rest body)
  "Write a NEW-layout cascade file; bind NEWFILE."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "cascade-new-" t))
          (newfile (expand-file-name "sent-004-doc.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file newfile
             (insert "#+TITLE: Sentence 4 Analysis\n"
                     "#+TIBETAN_LAYOUT: cascade\n"
                     "#+SEGMENTS: 105, 106\n\n"
                     "* My Notes\n\n\n"
                     "* Tibetan Text\nབདག།ཆོས།\n\n"
                     "* Reading\n"
                     "** Interlinear\nbdag [I] /\nchos [dharma] /\n\n"
                     "** Renderings\n"
                     "- ⟦105⟧ [Awaiting sentence translation…]\n"
                     "- ⟦106⟧ the profound dharma\n\n"
                     "* Tibetan Analysis\n** Translation\nX\n\n"
                     "* Footnotes\n\n"))
           ,@body)
       (delete-directory dir t))))

(ert-deftest tibetan-cascade-rendering-io-new-format ()
  "Read/write/numbers/needs-request against the ⟦N⟧ line format."
  (tibetan-cascade-test--with-new-format-file
    (should (equal '(105 106) (tibetan-cascade--rendering-numbers newfile)))
    (should (equal "the profound dharma"
                   (tibetan-cascade--read-rendering newfile 106)))
    (should (tibetan-cascade--rendering-needs-request-p newfile 105))
    (should-not (tibetan-cascade--rendering-needs-request-p newfile 106))
    ;; Write normalizes to a single line and replaces in place.
    (should (tibetan-cascade--write-rendering newfile 105 "he\nbowed"))
    (should (equal "he bowed"
                   (tibetan-cascade--read-rendering newfile 105)))
    (should-not (tibetan-cascade--rendering-needs-request-p newfile 105))
    ;; The file still has exactly two rendering lines.
    (should (= 2 (with-temp-buffer
                   (insert-file-contents newfile)
                   (count-matches "^- ⟦" (point-min) (point-max)))))))

(ert-deftest tibetan-cascade-rendering-io-legacy-fallback ()
  "The same primitives serve a LEGACY subtree file unchanged."
  (tibetan-cascade-test--with-legacy-cascade-file
    (should (equal '(105 106)
                   (tibetan-cascade--rendering-numbers legacy-file)))
    (should (tibetan-cascade--rendering-needs-request-p legacy-file 105))
    (should (tibetan-cascade--write-rendering legacy-file 105 "a span"))
    (should (equal "a span"
                   (tibetan-cascade--read-rendering legacy-file 105)))
    ;; The write landed in the legacy subtree, not on a ⟦N⟧ line.
    (should-not (string-match-p
                 "^- ⟦"
                 (with-temp-buffer (insert-file-contents legacy-file)
                                   (buffer-string))))))

(ert-deftest tibetan-cascade-rendering-write-ignores-translation-spans ()
  "⟦N⟧ markers inside other sections (an unstripped Translation) are
never mistaken for rendering lines — writes stay inside
* Reading/** Renderings."
  (tibetan-cascade-test--with-new-format-file
    (with-temp-buffer
      (insert-file-contents newfile)
      (goto-char (point-max))
      (insert "* Notes with markers\n- ⟦105⟧ decoy line\n")
      (write-region (point-min) (point-max) newfile nil 'silent))
    (tibetan-cascade--write-rendering newfile 105 "real span")
    (let ((s (with-temp-buffer (insert-file-contents newfile)
                               (buffer-string))))
      (should (string-match-p "^- ⟦105⟧ real span$" s))
      (should (string-match-p "^- ⟦105⟧ decoy line$" s)))))

;; ============================================================================
;; R6 (2026-08-12) — landing + grounding on the new format
;; ============================================================================

(ert-deftest tibetan-cascade-land-response-new-format-lines ()
  "Landing into a NEW-layout file updates the ⟦N⟧ rendering lines:
the placeholder line gets its span, a populated line survives
non-FORCE, and no legacy subtree is created."
  (tibetan-cascade-test--with-new-format-file
    (tibetan-cascade--land-response
     tibetan-cascade-test--response
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file newfile :cascade t :force nil))
    (should (equal "The lama went to rNgog's place"
                   (tibetan-cascade--read-rendering newfile 105)))
    ;; 106 was already populated — non-FORCE keeps it.
    (should (equal "the profound dharma"
                   (tibetan-cascade--read-rendering newfile 106)))
    (should-not (string-match-p
                 "^\\*\\* Segment "
                 (with-temp-buffer (insert-file-contents newfile)
                                   (buffer-string))))))

(ert-deftest tibetan-cascade-read-interlinear-for-unit-dual ()
  "The grounding's per-unit interlinear read serves the new format
positionally (Nth line ↔ Nth ⟦N⟧ key) and legacy files via the
subtree fallback."
  (tibetan-cascade-test--with-new-format-file
    (should (equal "bdag [I] /"
                   (tibetan-cascade--read-interlinear-for-unit
                    newfile 105)))
    (should (equal "chos [dharma] /"
                   (tibetan-cascade--read-interlinear-for-unit
                    newfile 106))))
  (tibetan-cascade-test--with-legacy-cascade-file
    (should (string-match-p
             "GLOSS"
             (or (tibetan-cascade--read-interlinear-for-unit
                  legacy-file 105)
                 "")))))

;; ============================================================================
;; R7 (2026-08-12) — regenerate preserves renderings ACROSS formats
;; ============================================================================

(ert-deftest tibetan-cascade-regenerate-preserves-new-format-renderings ()
  "Preserve-mode regenerate of a NEW-layout file keeps its landed
⟦N⟧ renderings — restored through the dual-format writer into
whatever layout the scaffold currently emits."
  (tibetan-cascade-test--with-new-format-file
    (let ((src (expand-file-name "doc.org"
                                 (file-name-directory newfile))))
      (with-temp-file src
        (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                "* Tibetan Text\n*** Sentence 4\n"
                "**** Segment 105\nབདག།\n\n"
                "**** Segment 106\nཆོས།\n\n"))
      (tibetan-cascade-test--with-stub-renderer
        (tibetan-cascade--regenerate newfile 4
                                     '((105 . "བདག།") (106 . "ཆོས།"))
                                     src))
      ;; The landed rendering survived the rebuild — restored onto
      ;; the scaffold's ⟦N⟧ line (post-R8 layout), with no legacy
      ;; subtree resurrected.
      (should (equal "the profound dharma"
                     (tibetan-cascade--read-rendering newfile 106)))
      (should-not (string-match-p
                   "^\\*\\* Segment "
                   (with-temp-buffer (insert-file-contents newfile)
                                     (buffer-string))))
      ;; The placeholder unit regenerated as needing a request.
      (should (tibetan-cascade--rendering-needs-request-p newfile 105)))))

(ert-deftest tibetan-cascade-open-mentions-defer ()
  "Opening a defer-MT document's segment says WHY nothing fires."
  (tibetan-cascade-test--with-stub-renderer
    (let* ((dir (make-temp-file "defer-msg-" t))
           (src (expand-file-name "doc.org" dir))
           (messages '()))
      (unwind-protect
          (progn
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n"
                      "#+TIBETAN_DEFER_MT: t\n\n"
                      "* Tibetan Text\n*** Sentence 4\n"
                      "**** Segment 105\nབདག\n\n"))
            (cl-letf (((symbol-function 'display-buffer-in-side-window)
                       (lambda (buf &rest _) (get-buffer-window buf t)))
                      ((symbol-function 'message)
                       (lambda (fmt &rest args)
                         (push (apply #'format fmt args) messages)
                         nil)))
              (let ((buf (tibetan-cascade-open-for-segment 105 src)))
                (when (buffer-live-p buf)
                  (with-current-buffer buf (set-buffer-modified-p nil))
                  (kill-buffer buf))))
            (should (cl-some (lambda (m)
                               (string-match-p "TIBETAN_DEFER_MT" m))
                             messages)))
        (delete-directory dir t)))))

(provide 'tibetan-cascade-test)
;;; tibetan-cascade-test.el ends here
