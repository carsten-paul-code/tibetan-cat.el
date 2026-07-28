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
              (lambda (text &rest _)
                (format (concat "** Wylie Transliteration\nWYLIE(%s)\n\n"
                                "** Phonetics\nPHON(%s)\n\n"
                                "** Interlinear Gloss\nGLOSS(%s)\n\n"
                                "** Translation\n[Requesting translation...]\n\n"
                                "** Grammar\n*** Particles\nPART(%s)\n\n"
                                "*** Claude Grammar\n\n"
                                "** Provided Translations\n\n")
                        text text text text))))
     ,@body))

(ert-deftest tibetan-cascade-scaffold-structure ()
  "C2.1: layout, header marker, global-number keys, ordinal props,
per-unit sections, and top/bottom user-slot ordering."
  (tibetan-cascade-test--with-stub-renderer
    (let ((s (tibetan-cascade--scaffold
              4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
              "/tmp/doc.org")))
      ;; Header marker + segments line.
      (should (string-match-p "^#\\+TIBETAN_LAYOUT: cascade$" s))
      (should (string-match-p "^#\\+SEGMENTS: 105, 106$" s))
      ;; Top-level ordering.
      (let ((notes (string-match "^\\* My Notes$" s))
            (wt    (string-match "^\\* Working Translation$" s))
            (tt    (string-match "^\\* Tibetan Text$" s))
            (ta    (string-match "^\\* Tibetan Analysis$" s))
            (subs  (string-match "^\\* Subsegments$" s))
            (foot  (string-match "^\\* Footnotes$" s)))
        (should (and notes wt tt ta subs foot))
        (should (< notes wt tt ta subs foot)))
      ;; Subsegments keyed by GLOBAL segment number, ordinal as prop.
      (should (string-match-p "^\\*\\* Segment 105$" s))
      (should (string-match-p "^\\*\\* Segment 106$" s))
      (should (string-match-p "^:SUBSEG: 1$" s))
      (should (string-match-p "^:SUBSEG: 2$" s))
      ;; Every unit: Rendering stub + the four deterministic sections
      ;; demoted to L3, with UNIT-scoped content.  Counted within the
      ;; * Subsegments region only — the sentence-level Grammar
      ;; legitimately carries its own *** Particles.
      (let ((region (substring s
                               (string-match "^\\* Subsegments$" s)
                               (string-match "^\\* Footnotes$" s))))
        (dolist (h '("Rendering" "Wylie" "Phonetics" "Interlinear Gloss"
                     "Particles"))
          (should (= 2 (cl-count-if
                        (lambda (line) (equal line (concat "*** " h)))
                        (split-string region "\n"))))))
      (should (string-match-p "\\[Awaiting sentence translation…\\]" s))
      (should (string-match-p (regexp-quote "GLOSS(བདག་གིས་ལས་བྱས། )") s))
      (should (string-match-p (regexp-quote "PART(ཆོས་ཟབ་མོ་ཡིན།)") s))
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
                  (should (string-match-p "^\\* Subsegments$" c))))))
        (delete-directory dir t)))))

;; ============================================================================
;; C2.2 — subsegment subtree I/O (keyed by GLOBAL segment number)
;; ============================================================================

(defmacro tibetan-cascade-test--with-cascade-file (&rest body)
  "Create a scaffolded 2-unit cascade file; bind CASCADE-FILE and DIR."
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

(ert-deftest tibetan-cascade-subsegment-numbers ()
  "The ordered global segment numbers under * Subsegments."
  (tibetan-cascade-test--with-cascade-file
    (should (equal '(105 106)
                   (tibetan-cascade--subsegment-numbers cascade-file)))
    ;; Degenerate inputs → nil, never signals.
    (should-not (tibetan-cascade--subsegment-numbers nil))
    (should-not (tibetan-cascade--subsegment-numbers
                 "/nonexistent/nowhere.org"))))

(ert-deftest tibetan-cascade-subsegment-section-read ()
  "Read a subsegment's L3 section body by global number + heading."
  (tibetan-cascade-test--with-cascade-file
    (should (equal tibetan-cascade-rendering-placeholder
                   (tibetan-cascade--read-subsegment-section
                    cascade-file 105 "Rendering")))
    (should (equal "WYLIE(བདག་གིས་ལས་བྱས། )"
                   (tibetan-cascade--read-subsegment-section
                    cascade-file 105 "Wylie")))
    (should (equal "GLOSS(ཆོས་ཟབ་མོ་ཡིན།)"
                   (tibetan-cascade--read-subsegment-section
                    cascade-file 106 "Interlinear Gloss")))
    ;; Absent subsegment / heading → nil.
    (should-not (tibetan-cascade--read-subsegment-section
                 cascade-file 107 "Rendering"))
    (should-not (tibetan-cascade--read-subsegment-section
                 cascade-file 105 "No Such Heading"))))

(ert-deftest tibetan-cascade-subsegment-section-write ()
  "Write replaces exactly ONE section body; everything else is
byte-identical.  Re-read returns the new body; the needs-request
predicate flips."
  (tibetan-cascade-test--with-cascade-file
    (should (tibetan-cascade--subsegment-rendering-needs-request-p
             cascade-file 105))
    (let ((before (with-temp-buffer
                    (insert-file-contents cascade-file)
                    (buffer-string))))
      (should (tibetan-cascade--write-subsegment-section
               cascade-file 105 "Rendering" "⟪He went⟫ and asked."))
      (let ((after (with-temp-buffer
                     (insert-file-contents cascade-file)
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
                      cascade-file 105 "Rendering")))
      (should-not (tibetan-cascade--subsegment-rendering-needs-request-p
                   cascade-file 105))
      ;; The sibling subsegment still needs its rendering.
      (should (tibetan-cascade--subsegment-rendering-needs-request-p
               cascade-file 106))
      ;; Writing to an absent subsegment fails soft (nil, no file touch).
      (should-not (tibetan-cascade--write-subsegment-section
                   cascade-file 107 "Rendering" "x")))))

(provide 'tibetan-cascade-test)
;;; tibetan-cascade-test.el ends here
