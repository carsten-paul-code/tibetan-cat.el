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
  "Header-Marker + Retirements (die L1-/Reading-Ordnung prüft
`tibetan-cascade-scaffold-v2-structure'): kein Subsegments-Baum,
keine Phonetics, kein ** Renderings, keine ** Interlinear, kein
* Tibetan Text (S2, §5.58); ⟦N⟧-Schlüssel + Platzhalter vorhanden."
  (tibetan-cascade-test--with-stub-renderer
    (let ((s (tibetan-cascade--scaffold
              4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
              "/tmp/doc.org")))
      ;; Header marker + segments line.
      (should (string-match-p "^#\\+TIBETAN_LAYOUT: cascade$" s))
      (should (string-match-p "^#\\+SEGMENTS: 105, 106$" s))
      (should (string-match-p "^- ⟦105⟧ " s))
      (should (string-match-p "^- ⟦106⟧ " s))
      (should (string-match-p "\\[Awaiting sentence translation…\\]" s))
      ;; Retired sections.
      (should-not (string-match-p "^\\* Subsegments$" s))
      (should-not (string-match-p "^\\*+ Phonetics$" s))
      (should-not (string-match-p "^\\*\\* Segment 105$" s))
      (should-not (string-match-p "^\\*\\* Renderings$" s))
      (should-not (string-match-p "^\\*\\* Interlinear$" s))
      (should-not (string-match-p "^\\*\\* Wylie$" s))
      (should-not (string-match-p "^\\* Tibetan Text$" s)))))

(ert-deftest tibetan-cascade-scaffold-v2-structure ()
  "S2 (§5.58, Reading-Class-Struktur): * Translation ganz oben,
* Reading nur mit Gloss Tables (kein Interlinear), * Tibetan
Analysis flach (Sentence Structure / Claude Vocabulary / Claude
Grammar / Claude Particles / Concept Notes als L2-Geschwister,
keine ** Grammar-Hülle, kein ** Provided Translations darin),
* Provided Translations auf L1 mit dem DM-Slot, Working
Translation + My Notes am Ende; * Tibetan Text entfällt."
  (tibetan-cascade-test--with-stub-renderer
    (let ((s (tibetan-cascade--scaffold
              4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
              "/tmp/doc.org")))
      ;; L1 order: Translation → Reading → Tibetan Analysis →
      ;; Provided Translations → Working Translation → My Notes →
      ;; Footnotes.
      (let ((tr   (string-match "^\\* Translation$" s))
            (rd   (string-match "^\\* Reading$" s))
            (ta   (string-match "^\\* Tibetan Analysis$" s))
            (pt   (string-match "^\\* Provided Translations$" s))
            (wt   (string-match "^\\* Working Translation$" s))
            (mn   (string-match "^\\* My Notes$" s))
            (foot (string-match "^\\* Footnotes$" s)))
        (should (and tr rd ta pt wt mn foot))
        (should (< tr rd ta pt wt mn foot)))
      ;; Retired sections.
      (should-not (string-match-p "^\\* Tibetan Text$" s))
      (should-not (string-match-p "^\\*\\* Interlinear$" s))
      (should-not (string-match-p "^\\*\\* Grammar$" s))
      ;; Flat L2 analysis children, in order.
      (let ((ss (string-match "^\\*\\* Sentence Structure$" s))
            (cv (string-match "^\\*\\* Claude Vocabulary$" s))
            (cg (string-match "^\\*\\* Claude Grammar$" s))
            (cp (string-match "^\\*\\* Claude Particles$" s))
            (cn (string-match "^\\*\\* Concept Notes$" s)))
        (should (and ss cv cg cp cn))
        (should (< ss cv cg cp cn)))
      ;; Provided Translations darf NICHT mehr in * Tibetan Analysis
      ;; liegen: es kommt genau einmal vor, als L1.
      (should-not (string-match-p "^\\*\\* Provided Translations$" s))
      ;; DM slot under the L1 Provided Translations.
      (let ((pt (string-match "^\\* Provided Translations$" s))
            (dm (string-match "^\\*\\* DharmaMitra Translation$" s))
            (wt (string-match "^\\* Working Translation$" s)))
        (should (and pt dm wt))
        (should (< pt dm wt)))
      ;; The L1 Translation slot carries the request placeholder.
      (should (string-match-p
               "^\\* Translation\n\\[Requesting translation\\.\\.\\.\\]"
               s))
      ;; Die Bialek-Partikelkarte überlebt als eigenes L2 (aus dem
      ;; Stub-Renderer-`*** Particles'-Body).
      (should (string-match-p "^\\*\\* Partikelkarte$" s)))))

(ert-deftest tibetan-cascade-regenerate-migrates-old-layout ()
  "S2 (§5.58): das Regenerate einer ALT-Layout-Datei hebt die
gelandeten Slots verlustfrei in die neue Struktur: ** Translation
(L2) → * Translation (L1), *** Claude Grammar → ** Claude Grammar,
*** Claude Particles (unter ** Provided Translations) → ** Claude
Particles, DM-Body → unter * Provided Translations (L1)."
  (tibetan-cascade-test--with-stub-renderer
    (let* ((dir (make-temp-file "cascade-mig-" t))
           (src (expand-file-name "doc.org" dir))
           (file (expand-file-name "analysis/sent-004-doc.org" dir)))
      (unwind-protect
          (progn
            (make-directory (expand-file-name "analysis" dir) t)
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                      "* Tibetan Text\n*** Sentence 4\n"
                      "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"
                      "**** Segment 106\nཆོས་ཟབ་མོ་ཡིན།\n\n"))
            ;; Hand-built OLD layout file with landed content.
            (with-temp-file file
              (insert "#+TITLE: Sentence 4 Analysis\n"
                      "#+TIBETAN_LAYOUT: cascade\n"
                      "#+SOURCE: [[file:../doc.org::*Sentence 4]"
                      "[doc.org / Sentence 4]]\n"
                      "#+SEGMENTS: 105, 106\n\n"
                      "* My Notes\nNOTIZ bleibt.\n\n"
                      "* Working Translation\nMeine Übersetzung.\n\n"
                      "* Tibetan Text\nབདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན།\n\n"
                      "* Reading\n** Gloss Tables\n"
                      ":PROPERTIES:\n:GENERATED_HASH: deadbeef\n:END:\n"
                      "*** Segment 105\n| bdag |\n\n"
                      "*** Segment 106\n| chos |\n\n"
                      "** Interlinear\nbdag /\nchos /\n\n"
                      "** Renderings\n"
                      "- ⟦105⟧ Ich handelte.\n"
                      "- ⟦106⟧ Der Dharma ist tief.\n\n"
                      "* Tibetan Analysis\n"
                      ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
                      "** Claude Vocabulary\n*** Segment 105\n"
                      "bdag, pronoun, \"ich\", Agens\n\n"
                      "** Translation\nIch handelte; der Dharma ist tief.\n\n"
                      "** Grammar\n*** Particles\nKARTE.\n\n"
                      "*** Claude Grammar\nErgativ-Kette.\n\n"
                      "** Provided Translations\n"
                      "*** Claude Particles\n**** Segment 105\n"
                      "gis, gis, 1.2, ergative\n\n"
                      "** Concept Notes\nBegriffsnotiz.\n\n"
                      "** DharmaMitra Translation\n"
                      ":PROPERTIES:\n:LAST_TRANSLATED: 2026-10-07\n:END:\n"
                      "DM-Übersetzung.\n\n"
                      "* Footnotes\n\n"))
            (tibetan-cascade--regenerate
             file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
             src)
            (let ((s (with-temp-buffer
                       (insert-file-contents file)
                       (buffer-string))))
              ;; Translation → L1, body preserved.
              (should (string-match-p
                       "^\\* Translation\nIch handelte; der Dharma ist tief\\."
                       s))
              (should-not (string-match-p "^\\*\\* Translation$" s))
              ;; Claude Grammar → L2 inside * Tibetan Analysis.
              (should (string-match-p
                       "^\\*\\* Claude Grammar\nErgativ-Kette\\." s))
              ;; Claude Particles → L2, raus aus Provided Translations.
              (should (string-match-p "^\\*\\* Claude Particles$" s))
              (should (string-match-p "gis, gis, 1\\.2, ergative" s))
              (let ((pt (string-match "^\\* Provided Translations$" s))
                    (cp (string-match "^\\*\\* Claude Particles$" s)))
                (should (and pt cp))
                (should (< cp pt)))
              ;; DM under the L1 Provided Translations, body intact.
              (let ((pt (string-match "^\\* Provided Translations$" s))
                    (dm (string-match "^\\*\\* DharmaMitra Translation$" s))
                    (wt (string-match "^\\* Working Translation$" s)))
                (should (and pt dm wt))
                (should (< pt dm wt)))
              (should (string-match-p "DM-Übersetzung\\." s))
              (should (string-match-p ":LAST_TRANSLATED: 2026-10-07" s))
              ;; User slots + renderings survive; Tibetan Text is gone.
              (should (string-match-p "NOTIZ bleibt\\." s))
              (should (string-match-p "Meine Übersetzung\\." s))
              (should (string-match-p "^- ⟦105⟧ Ich handelte\\.$" s))
              (should (string-match-p
                       "^- ⟦106⟧ Der Dharma ist tief\\.$" s))
              (should-not (string-match-p "^\\* Tibetan Text$" s))
              ;; Vocabulary + Concept Notes an ihren L2-Slots.
              (should (string-match-p
                       "bdag, pronoun, \"ich\", Agens" s))
              (should (string-match-p
                       "^\\*\\* Concept Notes\nBegriffsnotiz\\." s))))
        (delete-directory dir t)))))

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
    ;; Sentence-level Translation body (placeholder → real).
    (tibetan-cascade-test--set-translation-body
     cascade-file "The lama went and asked for dharma.")
    (with-temp-buffer
      (insert-file-contents cascade-file)
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

(defun tibetan-cascade-test--set-l2-body (file heading body)
  "Test helper: replace the `** HEADING' body in FILE with BODY."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward (format "^\\*\\* %s$" (regexp-quote heading)))
    (forward-line 1)
    (let ((start (point))
          (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                   (line-beginning-position)
                 (point-max))))
      (delete-region start end)
      (goto-char start)
      (insert body "\n\n"))
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest tibetan-cascade-regenerate-restores-vocab-without-scaffold-slot ()
  "§5.26 class (2026-09-15, S2-Fassung): a preserved L2 body whose
heading the fresh scaffold does NOT emit (hier simuliert über einen
leeren Analysis-Body) must still be RESTORED — am ENDE von
* Tibetan Analysis angelegt, NICHT vor * Footnotes (zwischen beiden
liegen seit S2 Provided Translations / Working Translation /
My Notes — der alte Anker hätte den Slot ins falsche Elternteil
gelegt)."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade-test--set-l2-body
     cascade-file "Claude Vocabulary"
     "khang pa, noun, \"Haus\", the context reading")
    (cl-letf (((symbol-function 'tibetan-cascade--analysis-body)
               (lambda (&rest _) "")))
      (tibetan-cascade--regenerate
       cascade-file 4
       '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
       (expand-file-name "doc.org" dir)))
    (let ((body (tibetan-sentence--read-l2-body cascade-file
                                                "Claude Vocabulary")))
      (should body)
      (should (string-match-p "khang pa, noun, \"Haus\"" body)))
    ;; The created heading must sit INSIDE * Tibetan Analysis —
    ;; before * Provided Translations, not dangling further down.
    (with-temp-buffer
      (insert-file-contents cascade-file)
      (let ((vocab (progn (goto-char (point-min))
                          (re-search-forward
                           "^\\*\\* Claude Vocabulary$" nil t)))
            (pt    (progn (goto-char (point-min))
                          (re-search-forward
                           "^\\* Provided Translations$" nil t))))
        (should (and vocab pt (< vocab pt)))))))

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
    (tibetan-cascade-test--set-l2-body
     cascade-file "Claude Vocabulary"
     "khang pa, noun, \"Haus\", the Claude context reading")
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

(ert-deftest tibetan-cascade-regenerate-binds-claude-particles-for-tables ()
  "T3 (§5.58): das Regenerate bindet
`tibetan-gloss-table--claude-particles' textkeyed aus dem
preservierten ** Claude Particles-Body — die Converb-Funktionen
erreichen Zeile 3 der Tabellen (§5.57-Word-Analysis-Muster)."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade-test--set-l2-body
     cascade-file "Claude Particles"
     (concat "*** Segment 105\n"
             "gis, gis, 1.2, ergative\n"
             "byas nas, nas, 2.11, sequential converb"))
    (let* ((orig (symbol-function 'tibetan-cascade--scaffold))
           (captured 'unset))
      (cl-letf (((symbol-function 'tibetan-cascade--scaffold)
                 (lambda (&rest args)
                   (setq captured
                         (and (boundp 'tibetan-gloss-table--claude-particles)
                              tibetan-gloss-table--claude-particles))
                   (apply orig args))))
        (tibetan-cascade--regenerate
         cascade-file 4
         '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
         (expand-file-name "doc.org" dir)))
      (should (consp captured))
      (let ((unit (cdr (assoc "བདག་གིས་ལས་བྱས།" captured))))
        (should unit)
        (should (equal "nas" (plist-get (cadr unit) :particle)))
        (should (equal "sequential converb"
                       (plist-get (cadr unit) :label)))))))

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

(ert-deftest tibetan-cascade-regenerate-never-silently-drops-l2-when-reader-unbound ()
  "B1 (§5.58, B0-Klasse): keep-l2 hing an `(fboundp
'tibetan-sentence--read-l2-body)' — in einem Batch ohne
tibetan-sentence-persist wurde die Liste still leer und der
Regenerate warf JEDEN gelandeten L2-Body (Translation, DM,
Vocabulary, Concept Notes, Word Analysis, Provided Translations)
kommentarlos weg.  Ein fehlendes Lesemodul darf den Regenerate
höchstens LAUT abbrechen (Datei unberührt), nie still zerstören."
  (tibetan-cascade-test--with-cascade-file
    ;; Populate the sentence-level Translation (placeholder → real).
    (tibetan-cascade-test--set-translation-body
     cascade-file "The lama went and asked for dharma.")
    ;; Simulate the unloaded module: the reader is UNBOUND.
    (let ((orig (symbol-function 'tibetan-sentence--read-l2-body)))
      (unwind-protect
          (progn
            (fmakunbound 'tibetan-sentence--read-l2-body)
            ;; A loud abort is acceptable; silent completion that
            ;; loses the body is the bug.
            (ignore-errors
              (tibetan-cascade--regenerate
               cascade-file 4
               '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
               (expand-file-name "doc.org" dir))))
        (fset 'tibetan-sentence--read-l2-body orig)))
    (should (string-match-p
             "The lama went and asked for dharma\\."
             (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))))

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
;; T4 (§5.58) — Sequenzübersetzung unter der jeweiligen Segment-Tabelle
;; ============================================================================

(ert-deftest tibetan-cascade-rendering-line-lives-under-its-table ()
  "T4 (§5.58, Reading-Class-Layout): jede ⟦N⟧-Sequenzübersetzung
steht DIREKT unter der Glossentabelle ihres Segments (nach dem
`*** Segment N'-Block, vor dem nächsten), nicht mehr in einer
eigenen `** Renderings'-Sektion."
  (tibetan-cascade-test--with-cascade-file
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))
      (should-not (string-match-p "^\\*\\* Renderings$" s))
      (let ((seg105 (string-match "^\\*\\*\\* Segment 105$" s))
            (r105   (string-match "^- ⟦105⟧ " s))
            (seg106 (string-match "^\\*\\*\\* Segment 106$" s))
            (r106   (string-match "^- ⟦106⟧ " s)))
        (should (and seg105 r105 seg106 r106))
        (should (< seg105 r105 seg106 r106)))
      ;; Readers/writers follow the lines to their new home.
      (should (equal '(105 106)
                     (tibetan-cascade--rendering-numbers cascade-file)))
      (should (tibetan-cascade--write-rendering cascade-file 105
                                                "Neuer Span."))
      (should (equal "Neuer Span."
                     (tibetan-cascade--read-rendering cascade-file 105))))))

(ert-deftest tibetan-cascade-landing-keeps-gloss-tables-unedited ()
  "T4 (§5.58, Hash-Kanonik): die ⟦N⟧-Zeilen leben IM
Gloss-Tables-Body — ohne Kanonisierung würde jede Landung den
:GENERATED_HASH:-Vergleich kippen und die Tabellen dauerhaft als
»handeditiert« einfrieren.  Der Hash muss die Maschinenzeilen
beidseitig ausklammern: nach einer Landung gilt die Sektion weiter
als GENERIERT."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade--land-response
     tibetan-cascade-test--response
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file cascade-file :cascade t :force nil))
    ;; The landed span sits inside the Gloss Tables section…
    (let* ((state (tibetan-cascade--read-gloss-tables cascade-file)))
      (should state)
      (should (string-match-p "⟦105⟧ The lama went to rNgog's place"
                              (car state)))
      ;; …and the section still counts as generated (hash canonical).
      (should-not (tibetan-cascade--gloss-tables-edited-p state)))
    ;; A real CELL edit still flips the protection.
    (with-temp-buffer
      (insert-file-contents cascade-file)
      (goto-char (point-min))
      (re-search-forward "^\\*\\*\\* Segment 105$")
      (forward-line 1)
      (insert "| HANDEDIT |\n")
      (write-region (point-min) (point-max) cascade-file nil 'silent))
    (should (tibetan-cascade--gloss-tables-edited-p
             (tibetan-cascade--read-gloss-tables cascade-file)))))

(ert-deftest tibetan-cascade-write-rendering-inserts-missing-line ()
  "T4 (§5.58): eine hand-preservierte Gloss-Tables-Sektion aus dem
ALTEN Layout trägt keine ⟦N⟧-Zeilen — der Writer muss die Zeile
dann hinter dem `*** Segment N'-Block NEU einsetzen statt still
nil zu liefern (sonst verlöre der Regenerate einer editierten
Alt-Datei jede Sequenzübersetzung)."
  (tibetan-cascade-test--with-cascade-file
    ;; Simulate the post-restore state: strip every ⟦N⟧ line.
    (with-temp-buffer
      (insert-file-contents cascade-file)
      (goto-char (point-min))
      (while (re-search-forward "^- ⟦[0-9]+⟧ .*\n" nil t)
        (replace-match ""))
      (write-region (point-min) (point-max) cascade-file nil 'silent))
    (should (tibetan-cascade--write-rendering cascade-file 106
                                              "Wieder da."))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))
      (let ((seg106 (string-match "^\\*\\*\\* Segment 106$" s))
            (r106   (string-match "^- ⟦106⟧ Wieder da\\.$" s)))
        (should (and seg106 r106))
        (should (< seg106 r106))))))

(defun tibetan-cascade-test--set-translation-body (file body)
  "Test helper: replace the Translation body in FILE with BODY —
v2-L1 (`* Translation') zuerst, Alt-L2 als Fallback."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward "^\\*\\{1,2\\} Translation$")
    (forward-line 1)
    (let ((start (point))
          (end (if (re-search-forward "^\\*\\{1,2\\} " nil t)
                   (line-beginning-position)
                 (point-max))))
      (delete-region start end)
      (goto-char start)
      (insert body "\n\n"))
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest tibetan-cascade-land-response-fills-missing-slots-after-chunk ()
  "B3 (§5.58, Gate-Falle, Landungsseite): nach einer Chunk-Landung
ist ** Translation gefüllt und das ALTE Gesamt-Gate (needs-request-p
= Translation UND Vocabulary beide leer) dauerhaft zu — Vocabulary /
Grammar / Particles / Concept Notes einer späteren Satz-Antwort
kamen ohne FORCE nie mehr an.  Die Landung muss per Slot gaten:
fehlende Slots landen, die vorhandene Translation bleibt unberührt."
  (tibetan-cascade-test--with-cascade-file
    ;; Simulate the post-chunk state: Translation populated (chunk
    ;; slice with its label), everything else still placeholder.
    (tibetan-cascade-test--set-translation-body
     cascade-file
     "(Sentence 4 — §220 chunk)\nCHUNK TRANSLATION stays.")
    (tibetan-cascade--land-response
     tibetan-cascade-test--response
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file cascade-file :cascade t :force nil))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))
      ;; The missing slots arrived.
      (should (string-match-p "rngog, proper noun" s))
      (should (string-match-p "two-clause chain" s))
      (should (string-match-p "one of Mar pa's four pillars" s))
      ;; The populated Translation was NOT overwritten (non-FORCE).
      (should (string-match-p "CHUNK TRANSLATION stays\\." s))
      (should-not
       (string-match-p
        "The lama went to rNgog's place and requested the dharma\\."
        (or (tibetan-sentence--read-l2-body cascade-file "Translation")
            ""))))))

(ert-deftest tibetan-cascade-land-truncated-response-stubs-concept-notes ()
  "B4 (§5.58): eine ABGESCHNITTENE Satz-Antwort (sent-654-Klasse:
der Text riss mitten im Particles-Eintrag `…approx-quotative (' ab,
`## Concept Notes' kam nie) wurde kommentarlos gelandet — Concept
Notes blieb stummer Platzhalter, nichts signalisierte den Abriss.
Die Landung muss den fehlenden Pflicht-Schluss erkennen und einen
SICHTBAREN Stub schreiben, der weiter als needs-request zählt."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade--land-response
     (concat "## Translation\n"
             "⟦105⟧Er ging⟦/105⟧ und ⟦106⟧fragte⟦/106⟧.\n\n"
             "## Vocabulary\n### Segment 105\n"
             "rngog, proper noun, \"rNgog\", ein Schüler\n\n"
             "## Grammar\nZwei Klausen.\n\n"
             "## Particles\n### Segment 105\n"
             "kun rdzob bden zhes, zhes, 2.4, approx-quotative (")
     (list :sent-num 4 :seg-nums '(105 106)
           :sent-file cascade-file :cascade t :force nil))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file)
               (buffer-string))))
      ;; Visible truncation stub under ** Concept Notes — it must
      ;; SURVIVE the regenerate-after-land (hence no `[Awaiting'
      ;; prefix: keep-l2 filtert die heraus; §5.40-Stub-Familie).
      (should (string-match-p "^\\*\\* Concept Notes" s))
      (should (string-match-p "\\[Antwort abgeschnitten" s))
      ;; The stub still counts as needing a request → B3 gate open.
      (should (tibetan-cascade--claude-sections-incomplete-p
               cascade-file)))))

(ert-deftest tibetan-cascade-fire-gate-opens-on-missing-vocabulary ()
  "B3 (§5.58, Gate-Falle, Feuerseite): im Nach-Chunk-Zustand
\(Translation + Renderings gefüllt, Vocabulary/Concept Notes leer)
muss der Satz-Fire öffnen — das alte Gate lieferte nil, womit die
fehlenden Sektionen für immer unerreichbar waren."
  (tibetan-cascade-test--with-cascade-file
    (tibetan-cascade-test--set-translation-body
     cascade-file
     "(Sentence 4 — §220 chunk)\nCHUNK TRANSLATION stays.")
    (tibetan-cascade--write-rendering cascade-file 105 "Span eins.")
    (tibetan-cascade--write-rendering cascade-file 106 "Span zwei.")
    (let ((requests '()))
      (cl-letf (((symbol-function 'tibetan-sentence-claude--claim)
                 (lambda (&rest _) t))
                ((symbol-function 'tibetan-sentence-claude--request)
                 (lambda (&rest args) (push args requests)))
                ((symbol-function 'tibetan-sentence-claude--schedule-dm)
                 (lambda (&rest _) nil)))
        (should (eq 'fired
                    (tibetan-cascade--fire-sentence-1
                     (list :sent-num 4 :seg-nums '(105 106)
                           :tibetan-text "བདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན།")
                     (expand-file-name "doc.org" dir)
                     (file-name-directory cascade-file)
                     nil)))
        (should (= 1 (length requests)))))))

;; ============================================================================
;; A0 (§5.59): Fire-Plist + Fire-Gate als geteilte Helfer
;; ============================================================================

(ert-deftest tibetan-cascade-fire-plist-carries-children ()
  "A0 (§5.59): der Satz-Plist für `--fire-sentence' wird an EINER
Stelle gebaut — :seg-nums, :children (der A3-Vertrag: ohne sie bekommt
Claude keine Segment-Enumeration) und :tibetan-text."
  (let ((p (tibetan-cascade--fire-plist
            4 '((105 . "བདག་གིས་") (106 . "ཆོས།")))))
    (should (= 4 (plist-get p :sent-num)))
    (should (equal '(105 106) (plist-get p :seg-nums)))
    (should (equal '((:seg-num 105 :text "བདག་གིས་")
                     (:seg-num 106 :text "ཆོས།"))
                   (plist-get p :children)))
    (should (equal "བདག་གིས་ཆོས།" (plist-get p :tibetan-text)))))

(ert-deftest tibetan-cascade-sentence-needs-fire-p-gate ()
  "A0 (§5.59): EIN Gate für Fire und Vorab-Zählung — offen bei
unvollständigen Claude-Slots ODER Rendering-Platzhalter, zu wenn
alles gelandet ist."
  (tibetan-cascade-test--with-cascade-file
    ;; Frisches Scaffold: alles Platzhalter → offen.
    (should (tibetan-cascade--sentence-needs-fire-p cascade-file '(105 106)))
    (tibetan-cascade-test--set-translation-body cascade-file "Ganzer Satz.")
    (tibetan-cascade-test--set-l2-body cascade-file "Claude Vocabulary"
                                       "bdag, pronoun, \"ich\", note")
    (tibetan-cascade-test--set-l2-body cascade-file "Concept Notes"
                                       "[No notable concepts in this passage]")
    (tibetan-cascade--write-rendering cascade-file 105 "Span eins.")
    ;; 106 noch Platzhalter → offen.
    (should (tibetan-cascade--sentence-needs-fire-p cascade-file '(105 106)))
    (tibetan-cascade--write-rendering cascade-file 106 "Span zwei.")
    ;; Alles gelandet → zu.
    (should-not (tibetan-cascade--sentence-needs-fire-p
                 cascade-file '(105 106)))))

;; ============================================================================
;; M1 (§5.58): Ordner-Migration auf die v2-Struktur
;; ============================================================================

(ert-deftest tibetan-cascade-migrate-structure-v2-folder ()
  "M1 (§5.58): der Ordner-Wrapper migriert jede Kaskaden-Satzdatei
per purem Preserve-Regenerate (NIE ein Fire — trotz der per B3
geöffneten Gates), überspringt Two-File-Dateien, sammelt Fehler
statt abzubrechen (resume-fähig)."
  (tibetan-cascade-test--with-stub-renderer
    (let* ((dir (make-temp-file "cascade-migrate-" t))
           (src (expand-file-name "doc.org" dir))
           (analysis (file-name-as-directory
                      (expand-file-name "analysis" dir))))
      (unwind-protect
          (progn
            (make-directory analysis t)
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                      "* Tibetan Text\n*** Sentence 4\n"
                      "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"))
            ;; (a) Alt-Layout-Kaskadendatei mit gelandetem Inhalt.
            (with-temp-file (expand-file-name "sent-004-doc.org"
                                              analysis)
              (insert "#+TITLE: Sentence 4 Analysis\n"
                      "#+TIBETAN_LAYOUT: cascade\n"
                      "#+SOURCE: [[file:../doc.org::*Sentence 4]"
                      "[doc.org / Sentence 4]]\n"
                      "#+SEGMENTS: 105\n\n"
                      "* My Notes\n\n\n* Working Translation\n\n\n"
                      "* Tibetan Text\nབདག་གིས་ལས་བྱས།\n\n"
                      "* Reading\n** Renderings\n"
                      "- ⟦105⟧ Ich handelte.\n\n"
                      "* Tibetan Analysis\n"
                      "** Translation\nIch handelte.\n\n"
                      "* Footnotes\n\n"))
            ;; (b) Two-File-Satzdatei (kein Kaskaden-Marker).
            (with-temp-file (expand-file-name "sent-007-doc.org"
                                              analysis)
              (insert "#+TITLE: Sentence 7 Analysis\n\n"
                      "* Tibetan Analysis\n** Translation\nZwei-File.\n"))
            ;; (c) Kaputte Kaskadendatei (keine Quelle auflösbar).
            (with-temp-file (expand-file-name "sent-099-doc.org"
                                              analysis)
              (insert "#+TITLE: Sentence 99 Analysis\n"
                      "#+TIBETAN_LAYOUT: cascade\n\n* Footnotes\n"))
            (let ((two-file-before
                   (with-temp-buffer
                     (insert-file-contents
                      (expand-file-name "sent-007-doc.org" analysis))
                     (buffer-string)))
                  (fires 0))
              (cl-letf (((symbol-function 'tibetan-cascade--fire-sentence)
                         (lambda (&rest _) (cl-incf fires) 'fired))
                        ((symbol-function 'tibetan-cascade--fire-section)
                         (lambda (&rest _) (cl-incf fires) 'fired)))
                (let ((r (tibetan-cascade-migrate-structure-v2 analysis)))
                  (should (= 3 (plist-get r :total)))
                  (should (= 1 (plist-get r :ok)))
                  (should (= 1 (plist-get r :skipped)))
                  (should (= 1 (plist-get r :failed)))
                  (should (= 1 (length (plist-get r :failures))))))
              ;; NIE gefeuert — Migration ist render-only.
              (should (= 0 fires))
              ;; (a) migriert: L1-Translation, Rendering erhalten.
              (let ((s (with-temp-buffer
                         (insert-file-contents
                          (expand-file-name "sent-004-doc.org" analysis))
                         (buffer-string))))
                (should (string-match-p
                         "^\\* Translation\nIch handelte\\." s))
                (should (string-match-p "^- ⟦105⟧ Ich handelte\\.$" s))
                (should-not (string-match-p "^\\* Tibetan Text$" s)))
              ;; (b) byte-identisch unberührt.
              (should (equal two-file-before
                             (with-temp-buffer
                               (insert-file-contents
                                (expand-file-name "sent-007-doc.org"
                                                  analysis))
                               (buffer-string))))))
        (delete-directory dir t)))))

;; ============================================================================
;; P2 (§5.58): Lopez/W&M-Materialisierung nach * Provided Translations
;; ============================================================================

(ert-deftest tibetan-cascade-materialize-provided-translations-once ()
  "P2 (§5.58, Entscheidung »einmalig«): das Kommando kopiert die
§-Referenzübersetzungen (Lopez 2006, Wangjié & Mulligan — NIE
Tibetisch/Wylie) aus der Comparative in * Provided Translations
der Satzdatei; danach sind sie editierbar und keep-geschützt.
Zweiter Lauf: idempotent, Hand-Edits bleiben unangetastet."
  (tibetan-cascade-test--with-stub-renderer
    (let* ((dir (make-temp-file "cascade-pt-" t))
           (src (expand-file-name "doc.org" dir))
           (refs (expand-file-name "comparative.org" dir)))
      (unwind-protect
          (progn
            (with-temp-file refs
              (insert "* Text\n"
                      "** §7\n"
                      "*** Tibetisch (B2)\nབོད་ཡིག\n\n"
                      "*** Wylie\nbod yig\n\n"
                      "*** Lopez 2006\n:PROPERTIES:\n:READ_ONLY: t\n:END:\n"
                      "*§7.* The mind itself is distilled here.\n\n"
                      "*** Wangjié & Mulligan\n:PROPERTIES:\n:READ_ONLY: t\n:END:\n"
                      "*§7.* [W&M ¶7, PDF-S. 12] The very mind.\n\n"
                      "*** Übersetzung CP\n:PROPERTIES:\n:STATUS: in Arbeit\n:END:\n"
                      "**** Stufe 1 — wörtlich\nCARSTENS EIGENE RUBRIK.\n\n"
                      "** §8\n*** Lopez 2006\nanderer §.\n"))
            (with-temp-file src
              (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n"
                      "#+TIBETAN_SECTION_REFS: comparative.org\n\n"
                      "* Tibetan Text\n"
                      "** Section §7\n"
                      ":PROPERTIES:\n:LOPEZ_SECTION: 7\n:END:\n"
                      "*** Sentence 4\n"
                      "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"))
            (let ((file (tibetan-cascade--create-file
                         4 '((105 . "བདག་གིས་ལས་བྱས།")) src)))
              (let ((r (tibetan-cascade-materialize-provided-translations
                        file)))
                (should (= 1 (plist-get r :written))))
              (let ((s (with-temp-buffer
                         (insert-file-contents file)
                         (buffer-string))))
                ;; Beide Referenzen unter * Provided Translations,
                ;; NACH dem DM-Slot; Tibetisch/Wylie nie.
                (let ((pt (string-match "^\\* Provided Translations$" s))
                      (dm (string-match
                           "^\\*\\* DharmaMitra Translation$" s))
                      (lo (string-match "^\\*\\* Lopez 2006$" s))
                      (wm (string-match
                           "^\\*\\* Wangjié & Mulligan$" s))
                      (wt (string-match "^\\* Working Translation$" s)))
                  (should (and pt dm lo wm wt))
                  (should (< pt dm lo wm wt)))
                (should (string-match-p
                         "The mind itself is distilled here\\." s))
                (should (string-match-p "\\[W&M ¶7, PDF-S\\. 12\\]" s))
                (should-not (string-match-p "བོད་ཡིག" s))
                (should-not (string-match-p "^bod yig$" s))
                ;; Nicht der andere §.
                (should-not (string-match-p "anderer §" s))
                ;; Carstens EIGENE Rubrik wird NIE dupliziert — seine
                ;; autorschaftliche Ebene lebt in der Comparative
                ;; bzw. * Working Translation (Zwei-Quellen-Drift).
                (should-not (string-match-p "Übersetzung CP" s))
                (should-not (string-match-p
                             "CARSTENS EIGENE RUBRIK" s)))
              ;; Hand-Edit + zweiter Lauf: idempotent, Edit bleibt.
              (with-temp-buffer
                (insert-file-contents file)
                (goto-char (point-min))
                (re-search-forward "^\\*\\* Lopez 2006$")
                (forward-line 1)
                (insert "HAND-GEKÜRZT.\n")
                (write-region (point-min) (point-max) file nil 'silent))
              (let ((r2 (tibetan-cascade-materialize-provided-translations
                         file)))
                (should (= 0 (plist-get r2 :written))))
              (let ((s2 (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
                (should (string-match-p "HAND-GEKÜRZT\\." s2))
                ;; Keine Duplikate.
                (should (= 1 (cl-count "** Lopez 2006"
                                       (split-string s2 "\n")
                                       :test #'equal))))))
        (delete-directory dir t)))))

;; ============================================================================
;; C3.2 — cascade fire (dispatcher branch, claim, request, DM)
;; ============================================================================

(require 'tibetan-sentence-claude)

(ert-deftest tibetan-cascade-prompt-grounding-from-subsegments ()
  "S2 (§5.58): die Satzdatei trägt keine ** Interlinear mehr — das
Grounding wird aus den Token-Strömen der shad-gesplitteten Units
erzeugt (Splitter-Kontrakt: Position K ↔ K-tes Segment); Alt-Dateien
mit Interlinear-Sektion werden weiter gelesen (Dual-Pfad)."
  (tibetan-cascade-test--with-cascade-file
    (let ((g (tibetan-cascade--prompt-grounding
              (list :sent-num 4 :seg-nums '(105 106)
                    :tibetan-text "བདག་གིས་ལས་བྱས། ཆོས་ཟབ་མོ་ཡིན།")
              (expand-file-name "doc.org" dir)
              (file-name-directory cascade-file))))
      (should g)
      (should (string-match-p "=== Segment 105 ===" g))
      (should (string-match-p "=== Segment 106 ===" g))
      ;; Each block carries that unit's (non-empty) generated line.
      (should (string-match-p "=== Segment 105 ===\n[^=\n]" g))
      (should (string-match-p "do NOT invent meanings" g)))))

(ert-deftest tibetan-cascade-prompt-grounding-parity-with-legacy-interlinear ()
  "Paritäts-Lock (§5.53-Klasse): auf einer ALT-Layout-Datei MIT
** Interlinear liest das Grounding die Dateizeile; die interne
Erzeugung über dieselben Units liefert dieselbe Zeile — Batch- und
Alt/Neu-Läufe füttern den Prompt identisch."
  (tibetan-cascade-test--with-cascade-file
    ;; Append a legacy ** Interlinear layer with the generated lines.
    (let* ((units '("བདག་གིས་ལས་བྱས། " "ཆོས་ཟབ་མོ་ཡིན།"))
           (src (expand-file-name "doc.org" dir))
           (gen (tibetan-cascade--generated-reading-lines
                 cascade-file src units)))
      (should (= 2 (length gen)))
      (with-temp-buffer
        (insert-file-contents cascade-file)
        (goto-char (point-min))
        (re-search-forward "^\\* Tibetan Analysis$")
        (goto-char (line-beginning-position))
        (insert "** Interlinear\n" (string-join gen "\n") "\n\n")
        (write-region (point-min) (point-max) cascade-file nil 'silent))
      ;; Read path (legacy file line) == generated path.
      (dolist (pair (list (cons 105 (nth 0 gen))
                          (cons 106 (nth 1 gen))))
        (should (equal (cdr pair)
                       (tibetan-cascade--read-interlinear-for-unit
                        cascade-file (car pair))))))))

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
;; A1 (§5.59): C-c u A auf JEDER Hierarchieebene (Kaskaden-Quelle)
;; ============================================================================

(defmacro tibetan-cascade-test--with-sectioned-source (sec1 &rest body)
  "Visit a cascade source with two Sections — SEC1 (heading text
after `** ') wraps Sentences 4+5, `Section §168' wraps Sentence 6.
Bind SRC, DIR, ANALYSIS; BUF is current.  The renderer is stubbed;
FIRED collects the sent-nums `--fire-sentence' saw, OPENED the
segment `--open-for-segment' was called with, PARAGRAPH is set when
the two-file paragraph path runs."
  (declare (indent 1))
  `(tibetan-cascade-test--with-stub-renderer
     (let* ((dir (make-temp-file "cascade-subtree-" t))
            (src (expand-file-name "doc.org" dir))
            (analysis (expand-file-name "analysis" dir))
            (fired '()) (opened nil) (paragraph nil)
            (tibetan-auto-fire-claude-on-create t))
       (unwind-protect
           (progn
             (with-temp-file src
               (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                       "* Tibetan Text\n"
                       "** " ,sec1 "\n"
                       ":PROPERTIES:\n:LOPEZ_SECTION: 167\n:END:\n\n"
                       "*** Sentence 4\n"
                       "**** Segment 105\nབདག་གིས་ལས་བྱས།\n\n"
                       "**** Segment 106\nཆོས་ཟབ་མོ་ཡིན།\n\n"
                       "*** Sentence 5\n"
                       "**** Segment 107\nམཐའ་མ་འདི་ཡིན།\n\n"
                       "** Section §168\n"
                       ":PROPERTIES:\n:LOPEZ_SECTION: 168\n:END:\n\n"
                       "*** Sentence 6\n"
                       "**** Segment 108\nལམ་འདི་ཡིན།\n\n"))
             (let ((buf (find-file-noselect src)))
               (unwind-protect
                   (cl-letf (((symbol-function 'tibetan-cascade--fire-sentence)
                              (lambda (sentence &rest _)
                                (push (plist-get sentence :sent-num) fired)
                                'fired))
                             ((symbol-function 'tibetan-cascade-open-for-segment)
                              (lambda (seg &rest _) (setq opened seg) nil))
                             ((symbol-function 'tibetan-open-paragraph-analysis)
                              (lambda (&rest _) (setq paragraph t))))
                     (with-current-buffer buf ,@body))
                 (when (buffer-live-p buf)
                   (with-current-buffer buf (set-buffer-modified-p nil))
                   (kill-buffer buf)))))
         (delete-directory dir t)))))

(defun tibetan-cascade-test--sent-files (analysis)
  "Sorted sent-file basenames in ANALYSIS (nil when absent)."
  (and (file-directory-p analysis)
       (sort (directory-files analysis nil "\\`sent-") #'string<)))

(ert-deftest tibetan-cascade-cu-a-on-section-analyzes-subtree ()
  "A1 (§5.59, Carstens Befund an §220): C-c u A auf `** Section §167'
einer KASKADEN-Quelle lief in den Two-File-Absatzpfad („Paragraph
§220 has no `*** Tibetisch' child\").  Jetzt: alle Sätze NUR dieses
Subtrees angelegt + (gated) gefeuert, der erste Satz geöffnet."
  (tibetan-cascade-test--with-sectioned-source "Section §167"
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Section §167")
    (tibetan-open-segment-analysis)
    (should-not paragraph)
    (should (equal '("sent-004-doc.org" "sent-005-doc.org")
                   (tibetan-cascade-test--sent-files analysis)))
    (should (equal '(4 5) (sort fired #'<)))
    (should (equal 105 opened))))

(ert-deftest tibetan-cascade-cu-a-on-top-heading-analyzes-document ()
  "A1 (§5.59): `* Tibetan Text' (Ebene 1) umfasst alle Sätze — die
org-Hierarchie bestimmt den Umfang, nicht ein fester Level."
  (tibetan-cascade-test--with-sectioned-source "Section §167"
    (goto-char (point-min))
    (re-search-forward "^\\* Tibetan Text")
    (tibetan-open-segment-analysis)
    (should (equal '("sent-004-doc.org" "sent-005-doc.org"
                     "sent-006-doc.org")
                   (tibetan-cascade-test--sent-files analysis)))
    (should (equal '(4 5 6) (sort fired #'<)))))

(ert-deftest tibetan-cascade-cu-a-on-section-without-paragraph-sign ()
  "A1 (§5.59): Sanskrit-Quellen tragen Sections ohne „§\"
\(`** Section MAv VI.28') — bisher fiel C-c u A dort in den
Segment-Impl („Not in a segment or paragraph\")."
  (tibetan-cascade-test--with-sectioned-source "Section MAv VI.28"
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Section MAv")
    (tibetan-open-segment-analysis)
    (should (equal '(4 5) (sort fired #'<)))))

(ert-deftest tibetan-cascade-cu-a-subtree-asks-above-threshold ()
  "A1 (§5.59): über `tibetan-cascade-subtree-confirm-threshold'
fragt C-c u A mit der Anzahl nach (API-Kosten!); „n\" → kein
Fire.  Das strukturelle Anlegen ist gratis und bleibt."
  (tibetan-cascade-test--with-sectioned-source "Section §167"
    (let ((tibetan-cascade-subtree-confirm-threshold 1)
          (prompt nil))
      (cl-letf (((symbol-function 'y-or-n-p)
                 (lambda (p) (setq prompt p) nil)))
        (goto-char (point-min))
        (re-search-forward "^\\* Tibetan Text")
        (tibetan-open-segment-analysis))
      (should (and prompt (string-match-p "\\b3\\b" prompt)))
      (should-not fired)
      (should (= 3 (length (tibetan-cascade-test--sent-files analysis)))))))

(ert-deftest tibetan-cascade-cu-a-subtree-skips-complete-sentences ()
  "A1 (§5.59): vollständige Sätze feuern nicht (das A0-Gate
entscheidet — Zählung und Fire benutzen dasselbe Prädikat)."
  (tibetan-cascade-test--with-sectioned-source "Section §167"
    (cl-letf (((symbol-function 'tibetan-cascade--sentence-needs-fire-p)
               (lambda (file _segs) (string-match-p "sent-005" file))))
      (goto-char (point-min))
      (re-search-forward "^\\*\\* Section §167")
      (tibetan-open-segment-analysis))
    (should (equal '(5) fired))))

(defmacro tibetan-cascade-test--with-cu-r-stubs (&rest body)
  "Inside `--with-sectioned-source': create the files of Sentences 4
and 6 (5 stays missing), stub the per-file regenerate and the
two-file paragraph reanalyze.  REANALYZED collects (BASENAME .
RE-REQUEST) pairs; PARAGRAPH-R is set by the paragraph path."
  (declare (indent 0))
  `(let ((reanalyzed '()) (paragraph-r nil))
     (dolist (n '(4 6))
       (tibetan-cascade--create-file
        n (tibetan-cascade--segs-for-sentence src n) src))
     (cl-letf (((symbol-function 'tibetan-cascade-reanalyze-file)
                (lambda (file &rest args)
                  (push (cons (file-name-nondirectory file)
                              (plist-get args :re-request-claude))
                        reanalyzed)
                  (list :file file :ok t)))
               ((symbol-function 'tibetan-reanalyze-paragraph)
                (lambda (&rest _) (setq paragraph-r t))))
       ,@body)))

(ert-deftest tibetan-cascade-cu-r-on-section-rerenders-subtree ()
  "A2 (§5.59, gleiche Klasse wie A1): C-c u R auf `** Section §167'
lief in `tibetan-reanalyze-paragraph'.  Jetzt: jede EXISTIERENDE
Satzdatei des Subtrees wird neu gerendert (Inhalte bleiben) — ohne
Fire, wie C-c u R auf dem Satz."
  (tibetan-cascade-test--with-sectioned-source "Section §167"
    (tibetan-cascade-test--with-cu-r-stubs
      (goto-char (point-min))
      (re-search-forward "^\\*\\* Section §167")
      (let ((current-prefix-arg nil))
        (tibetan-reanalyze-segment))
      (should-not paragraph-r)
      ;; Satz 5 hat keine Datei (C-c u A legt sie an), Satz 6 liegt
      ;; außerhalb des Subtrees.
      (should (equal '(("sent-004-doc.org" . nil)) reanalyzed)))))

(ert-deftest tibetan-cascade-cu-r-prefix-forces-refire-after-confirm ()
  "A2 (§5.59): C-u C-c u R auf einer höheren Ebene erzwingt das
Neu-Feuern (überschreibt Gelandetes!) — darum IMMER y-or-n-p mit
der Anzahl; „n\" → gar nichts."
  (tibetan-cascade-test--with-sectioned-source "Section §167"
    (tibetan-cascade-test--with-cu-r-stubs
      (let ((prompts '()) (answer t))
        (cl-letf (((symbol-function 'y-or-n-p)
                   (lambda (p) (push p prompts) answer)))
          (goto-char (point-min))
          (re-search-forward "^\\* Tibetan Text")
          (let ((current-prefix-arg '(4)))
            (tibetan-reanalyze-segment))
          (should (= 1 (length prompts)))
          (should (string-match-p "\\b2\\b" (car prompts)))
          (should (equal '(("sent-004-doc.org" . t) ("sent-006-doc.org" . t))
                         (sort reanalyzed
                               (lambda (a b) (string< (car a) (car b))))))
          (setq reanalyzed nil answer nil)
          (let ((current-prefix-arg '(4)))
            (tibetan-reanalyze-segment))
          (should-not reanalyzed))))))

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

(ert-deftest tibetan-cascade-scaffold-emits-current-translation-heading ()
  "Tshig-gsal-Befund 2 (2026-09-24): der Segment-Renderer emittierte
im Scaffold noch den LEGACY-Namen `** Claude Translation' (SS5.18
verlangt: Writer emittieren nur den neuen Namen).  Folge: sobald
die Satz-Übersetzung landet, entsteht ein DUPLIKAT —
Legacy-Platzhalter oben, gefüllte `** Translation' unten.  Der
frische Kaskaden-Scaffold muss `** Translation' tragen und den
Legacy-Namen nirgends emittieren."
  ;; Bewusst OHNE den Stub-Renderer der übrigen Kaskaden-Fixtures:
  ;; der Legacy-Name kommt aus dem ECHTEN generate-content-Pfad
  ;; (SECTION 1b), den der Stub umgeht.
  (let* ((dir (make-temp-file "cascade-heading-" t))
         (src (expand-file-name "doc.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file src
            (insert "#+TITLE: D\n#+TIBETAN_LAYOUT: cascade\n\n"
                    "* Tibetan Text\n"
                    "*** Sentence 1\n"
                    "**** Segment 1\nབདག་གིས་ལས་བྱས།\n"))
          (let* ((file (tibetan-cascade--create-file
                        1 '((1 . "བདག་གིས་ལས་བྱས།")) src))
                 (s (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string))))
            ;; S2 (§5.58): der Slot heißt jetzt * Translation (L1);
            ;; weder der Legacy-Name noch das alte L2 dürfen
            ;; emittiert werden.
            (should (string-match-p "^\\* Translation$" s))
            (should-not (string-match-p "^\\*\\* Translation$" s))
            (should-not (string-match-p
                         "^\\*\\* Claude Translation$" s))))
      (delete-directory dir t))))

(ert-deftest tibetan-cascade-open-for-segment-fires-on-create ()
  "Tshig-gsal-Befund (2026-09-24): `tibetan-cascade-open-for-segment'
\(der C-c u A-Zweig) erzeugte die Kaskaden-Datei, feuerte aber NIE
Claude/DM — Paritätslücke zu den Two-File-Öffnern (SS5.8.1/SS5.29):
Claude Vocabulary/Translation/DM blieben Platzhalter, bis der User
von Hand C-c u R gab.  Erwartet: der Sentence-Level-Dispatcher wird
nach dem Öffnen gerufen (seine Gates/Claims verhindern Doppel-Fires
auf befüllten Dateien)."
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create t)
          (fires nil))
      (cl-letf (((symbol-function 'display-buffer-in-side-window)
                 (lambda (&rest _) nil))
                ((symbol-function 'tibetan-analysis--fire-sentence-level)
                 (lambda (&rest args) (push args fires) 'fired)))
        (tibetan-cascade-open-for-segment 105 src))
      (should (= 1 (length fires)))
      ;; Datei wurde erzeugt.
      (should (car (directory-files
                    (expand-file-name "analysis" dir) t "\\`sent-004"))))))

(ert-deftest tibetan-cascade-open-for-segment-no-fire-when-opted-out ()
  "Der Auto-Fire-Optout (`tibetan-auto-fire-claude-on-create' nil)
gilt auch für den Öffnungs-Fire."
  (tibetan-cascade-test--with-cascade-source
    (let ((tibetan-auto-fire-claude-on-create nil)
          (fires nil))
      (cl-letf (((symbol-function 'display-buffer-in-side-window)
                 (lambda (&rest _) nil))
                ((symbol-function 'tibetan-analysis--fire-sentence-level)
                 (lambda (&rest args) (push args fires) 'fired)))
        (tibetan-cascade-open-for-segment 105 src))
      (should (= 0 (length fires))))))

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
  "The assembled * Reading section (S2, §5.58): NUR `** Gloss
Tables' — die ⟦N⟧-Zeilen unter ihren Segment-Headings; die eigene
Renderings-Sektion UND die kombinierte Interlinear-Schicht sind
pensioniert."
  (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
             (lambda (_segs _vocab &optional _level) nil)))
    (let ((s (tibetan-cascade--reading-section
              '((105 . "བདག།") (106 . "ཆོས།")))))
      (should (string-match-p "^\\* Reading$" s))
      (should (string-match-p "^\\*\\* Gloss Tables$" s))
      (should-not (string-match-p "^\\*\\* Renderings$" s))
      (should-not (string-match-p "^\\*\\* Interlinear$" s))
      ;; The retired separate Wylie layer is gone.
      (should-not (string-match-p "^\\*\\* Wylie$" s))
      ;; ⟦N⟧ line under its own segment heading, in order.
      (let ((h105 (string-match "^\\*\\*\\* Segment 105$" s))
            (r105 (string-match "^- ⟦105⟧ \\[Awaiting" s))
            (h106 (string-match "^\\*\\*\\* Segment 106$" s))
            (r106 (string-match "^- ⟦106⟧ \\[Awaiting" s)))
        (should (and h105 r105 h106 r106))
        (should (< h105 r105 h106 r106))))))

(ert-deftest tibetan-cascade-reading-section-emits-gloss-tables ()
  "2026-09-15 (Masterarbeit three-view plan, Carsten's placement
decision): `** Gloss Tables' is the FIRST Reading child — captioned
three-row tables per shad unit BEFORE the Interlinear — carrying a
:GENERATED_HASH: drawer (the edit-protection anchor: hash of the
emitted body, so a later regenerate can tell generated from
hand-edited)."
  (let (seen-level)
    (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
               (lambda (_segs _vocab &optional level)
                 (setq seen-level level)
                 "*** Segment 105\n| CAPTBL |")))
      (let ((s (tibetan-cascade--reading-section
                '((105 . "བདག།") (106 . "ཆོས།")))))
        ;; Carsten's 2026-09-16 form: Segment number as HEADING.
        (should (eql 3 seen-level))
        (should (string-match-p "^\\*\\* Gloss Tables$" s))
        (should (string-match-p "^| CAPTBL |$" s))
        (should (string-match-p "^\\*\\*\\* Segment 105$" s))
        ;; T4: ein Segment OHNE Renderer-Block bekommt trotzdem sein
        ;; Heading + die ⟦N⟧-Zeile (Maschinenschlüssel).
        (should (string-match-p "^\\*\\*\\* Segment 106$" s))
        (should (string-match-p "^- ⟦106⟧ " s))
        ;; Edit-protection drawer hashes the CANONICAL body (the
        ;; ⟦N⟧ machine lines stripped — T4 Hash-Kanonik).
        (should (string-match-p
                 (concat ":GENERATED_HASH: "
                         (sha1 (concat "*** Segment 105\n| CAPTBL |"
                                       "\n\n*** Segment 106")))
                 s))))))

(ert-deftest tibetan-cascade-reading-section-always-emits-gloss-tables ()
  "T4 (§5.58) INVERTIERT den alten Omit-Kontrakt: auch ohne
renderbare Tabellen wird `** Gloss Tables' emittiert — die Sektion
ist jetzt das Zuhause der ⟦N⟧-Sequenzübersetzungen, jede Einheit
bekommt ihr Heading + die Maschinenzeile (nur eben ohne Tabelle)."
  (cl-letf (((symbol-function 'tibetan-gloss-table-render-captioned)
             (lambda (_segs _vocab &optional _level) nil)))
    (let ((s (tibetan-cascade--reading-section '((105 . "བདག།")))))
      (should (string-match-p "^\\*\\* Gloss Tables$" s))
      (should (string-match-p "^\\*\\*\\* Segment 105$" s))
      (should (string-match-p "^- ⟦105⟧ \\[Awaiting" s))
      (should-not (string-match-p "^|" s)))))

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
               (lambda (_segs _vocab &optional _level)
                 "*** Segment 105\n| NEU |")))
      (tibetan-cascade--regenerate
       cascade-file 4 '((105 . "བདག་གིས་ལས་བྱས། ") (106 . "ཆོས་ཟབ་མོ་ཡིན།"))
       (expand-file-name "doc.org" dir)))
    (let ((s (with-temp-buffer
               (insert-file-contents cascade-file) (buffer-string))))
      (should (string-match-p "^| NEU |$" s))
      ;; T4: der Hash deckt die KANONISCHE Form (Maschinenzeilen
      ;; gestrippt, Segment 106 trägt nur sein Heading).
      (should (string-match-p
               (concat ":GENERATED_HASH: "
                       (sha1 (concat "*** Segment 105\n| NEU |"
                                     "\n\n*** Segment 106")))
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
      (should (string-match-p "^\\*\\* Gloss Tables$" s)))
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
      (should (string-match-p "^\\*\\* Gloss Tables$" s)))))

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
