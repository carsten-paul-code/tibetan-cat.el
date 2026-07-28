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
    (tibetan-cascade--write-subsegment-section
     cascade-file 105 "Rendering" "⟪He went⟫ and asked.")
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
      (should (string-match-p "^\\*\\* Segment 105$" s))
      (should (string-match-p "^\\*\\* Segment 106$" s))
      ;; The UNPOPULATED sibling rendering is a fresh placeholder.
      (should (tibetan-cascade--subsegment-rendering-needs-request-p
               cascade-file 106))
      (should-not (tibetan-cascade--subsegment-rendering-needs-request-p
                   cascade-file 105)))))

(ert-deftest tibetan-cascade-regenerate-is-idempotent ()
  "A second regenerate with identical inputs is byte-identical
modulo the LAST_ANALYZED stamp."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade--write-subsegment-section
     cascade-file 105 "Rendering" "⟪He went⟫ and asked.")
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
      (should-not (string-match-p "⟦" s))
      ;; Vocabulary + Grammar landed with per-segment content.
      (should (string-match-p "rngog, proper noun" s))
      (should (string-match-p "two-clause chain" s))
      (should (string-match-p "one of Mar pa's four pillars" s))
      ;; Renderings = extracted spans.
      (should (equal "The lama went to rNgog's place"
                     (tibetan-cascade--read-subsegment-section
                      cascade-file 105 "Rendering")))
      (should (equal "requested the dharma"
                     (tibetan-cascade--read-subsegment-section
                      cascade-file 106 "Rendering")))
      ;; The ### sub-translations are DISCARDED.
      (should-not (string-match-p "Having gone to rNgog's place" s)))))

(ert-deftest tibetan-cascade-land-response-missing-span-stub ()
  "A segment whose span pair is absent gets a VISIBLE stub that still
counts as needs-request; the sibling lands normally.  Non-FORCE never
clobbers an already-populated Rendering."
  (tibetan-cascade-test--with-cascade-file
    ;; Pre-populate 106's rendering; feed a response whose whole
    ;; translation lacks 105's markers and carries DIFFERENT 106 text.
    (tibetan-cascade--write-subsegment-section
     cascade-file 106 "Rendering" "KEEP ME.")
    (tibetan-cascade--land-response
     "## Translation\nNo markers for one-oh-five ⟦106⟧new text⟦/106⟧.\n"
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file cascade-file :cascade t :force nil))
    ;; 105 → stub, still needs request.
    (should (string-match-p
             "\\`\\[Claude sentence response missing Segment 105"
             (tibetan-cascade--read-subsegment-section
              cascade-file 105 "Rendering")))
    (should (tibetan-cascade--subsegment-rendering-needs-request-p
             cascade-file 105))
    ;; 106 was populated → non-FORCE landing left it alone.
    (should (equal "KEEP ME."
                   (tibetan-cascade--read-subsegment-section
                    cascade-file 106 "Rendering")))))

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
      (should (string-match-p
               (regexp-quote "GLOSS(བདག་གིས་ལས་བྱས། )") g))
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
                             (tibetan-cascade--read-subsegment-section
                              cascade-file 105 "Rendering")))
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
                         (tibetan-cascade--subsegment-numbers sent4)))
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

(provide 'tibetan-cascade-test)
;;; tibetan-cascade-test.el ends here
