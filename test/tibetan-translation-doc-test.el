;;; tibetan-translation-doc-test.el --- Tests for the translation stitcher -*- lexical-binding: t -*-

;;; Commentary:
;; Masterarbeit three-view plan (2026-09-15), view 3: stitch
;; Carsten's per-sentence `* Working Translation' + `* Footnotes'
;; out of the cascade sent files into a generated §-grouped
;; translation document, and compile per-§ views.  All fixtures in
;; temp dirs — never the live corpus.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../persist" base-dir))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-translation-doc)
(require 'tibetan-sentence-persist)

;; ----------------------------------------------------------------------------
;; Fixtures
;; ----------------------------------------------------------------------------

(defconst tibetan-translation-doc-test--source
  (concat
   "#+TITLE: Quelle\n"
   "#+TIBETAN_LAYOUT: cascade\n\n"
   "* Tibetan Text\n"
   "*** Sentence 1\n"
   "**** Segment 1\nབདག\n"
   "** Section §167\n"
   ":PROPERTIES:\n"
   ":LOPEZ_SECTION: 167\n"
   ":B2_SEG_START: 1538\n"
   ":END:\n"
   "*** Sentence 2\n"
   "**** Segment 2\nཆོས\n"
   "*** Sentence 3\n"
   "**** Segment 3\nལས\n"
   "** Section §168\n"
   ":PROPERTIES:\n"
   ":LOPEZ_SECTION: 168\n"
   ":END:\n"
   "*** Sentence 4\n"
   "**** Segment 4\nམི\n")
  "Cascade source: one pre-Section sentence, §167 with two
sentences, §168 with one.")

(defmacro tibetan-translation-doc-test--with-source (&rest body)
  "Write the fixture source into a temp dir; bind SOURCE-FILE and DIR."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "ttdoc-" t))
          (source-file (expand-file-name "quelle.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file source-file
             (insert tibetan-translation-doc-test--source))
           ,@body)
       (delete-directory dir t))))

;; ----------------------------------------------------------------------------
;; Readers
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-translation-doc-source-outline-groups-by-section ()
  "The outline groups sentences under their §: a leading
(:lopez nil …) group for pre-Section sentences, then one plist per
Section with the drawer's LOPEZ_SECTION number."
  (tibetan-translation-doc-test--with-source
    (should (equal '((:lopez nil :sent-nums (1))
                     (:lopez 167 :sent-nums (2 3))
                     (:lopez 168 :sent-nums (4)))
                   (tibetan-translation-doc--source-outline source-file)))))

(ert-deftest tibetan-translation-doc-source-outline-empty-and-missing ()
  "A source without sentences → nil; a missing file → nil (no error)."
  (tibetan-translation-doc-test--with-source
    (let ((empty (expand-file-name "leer.org" dir)))
      (with-temp-file empty (insert "#+TITLE: X\n* Tibetan Text\n"))
      (should-not (tibetan-translation-doc--source-outline empty))
      (should-not (tibetan-translation-doc--source-outline
                   (expand-file-name "fehlt.org" dir))))))

(ert-deftest tibetan-translation-doc-working-translation-reader ()
  "Body of `* Working Translation', trimmed; nil when empty."
  (tibetan-translation-doc-test--with-source
    (let ((f (expand-file-name "sent-001-q.org" dir)))
      (with-temp-file f
        (insert "#+TITLE: S1\n\n* Working Translation\n"
                "Der Ehrwürdige sprach.[fn:rje]\n\n"
                "* Tibetan Text\nབདག\n* Footnotes\n"))
      (should (equal "Der Ehrwürdige sprach.[fn:rje]"
                     (tibetan-translation-doc--working-translation f))))
    (let ((g (expand-file-name "sent-002-q.org" dir)))
      (with-temp-file g
        (insert "#+TITLE: S2\n\n* Working Translation\n\n\n* Footnotes\n"))
      (should-not (tibetan-translation-doc--working-translation g)))))

(ert-deftest tibetan-translation-doc-footnote-definitions-reader ()
  "The `* Footnotes' body comes back with its internal formatting
intact (multi-line definitions); nil when empty."
  (tibetan-translation-doc-test--with-source
    (let ((f (expand-file-name "sent-001-q.org" dir)))
      (with-temp-file f
        (insert "#+TITLE: S1\n\n* Working Translation\nText.\n\n"
                "* Footnotes\n\n"
                "[fn:rje] Titel des Mi-la ras-pa.\n"
                "Zweite Zeile der Definition.\n\n"
                "[fn:zwei] Kurz.\n"))
      (should (equal (concat "[fn:rje] Titel des Mi-la ras-pa.\n"
                             "Zweite Zeile der Definition.\n\n"
                             "[fn:zwei] Kurz.")
                     (tibetan-translation-doc--footnote-definitions f))))))

;; ----------------------------------------------------------------------------
;; Footnote namespacing
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-translation-doc-namespace-anchor-and-definition ()
  "Anchors in the prose AND definition labels in the footnote
block get the same prefix — org keeps resolving them as pairs."
  (should (equal "Er sprach.[fn:s012-tha-snyad] Und ging.[fn:s012-rje]"
                 (tibetan-translation-doc--namespace-footnotes
                  "Er sprach.[fn:tha-snyad] Und ging.[fn:rje]"
                  "s012-")))
  (should (equal "[fn:s012-tha-snyad] Die Definition.\n[fn:s012-rje] Kurz."
                 (tibetan-translation-doc--namespace-footnotes
                  "[fn:tha-snyad] Die Definition.\n[fn:rje] Kurz."
                  "s012-"))))

(ert-deftest tibetan-translation-doc-namespace-inline-and-numeric ()
  "Inline `[fn:label:def]' and numeric `[fn:1]' labels are
prefixed too."
  (should (equal "Text[fn:s003-kurz:eine Inline-Definition] Ende."
                 (tibetan-translation-doc--namespace-footnotes
                  "Text[fn:kurz:eine Inline-Definition] Ende."
                  "s003-")))
  (should (equal "Text[fn:s003-1] Ende."
                 (tibetan-translation-doc--namespace-footnotes
                  "Text[fn:1] Ende." "s003-"))))

(ert-deftest tibetan-translation-doc-namespace-leaves-rest-alone ()
  "Anonymous inline footnotes `[fn::…]' stay untouched; text
without footnotes comes back byte-identical."
  (should (equal "Text[fn::anonym bleibt] Ende."
                 (tibetan-translation-doc--namespace-footnotes
                  "Text[fn::anonym bleibt] Ende." "s003-")))
  (let ((plain "Ein Text ohne Fußnoten, mit [Klammern] und fn: frei."))
    (should (equal plain
                   (tibetan-translation-doc--namespace-footnotes
                    plain "s003-")))))

;; ----------------------------------------------------------------------------
;; Builder — fixture corpus
;; ----------------------------------------------------------------------------

(defun tibetan-translation-doc-test--sent-file (n dir source-file
                                                 wt footnotes)
  "Write a minimal cascade sent file for sentence N (at the path the
suffix-aware resolver returns) with WT / FOOTNOTES bodies and
DISTINCTIVE poison strings in the sections the stitcher must never
copy (Renderings / DharmaMitra / Provided Translations)."
  (let ((f (tibetan-sentence--filepath n dir source-file)))
    (with-temp-file f
      (insert (format "#+TITLE: Sentence %d Analysis\n" n)
              "#+TIBETAN_LAYOUT: cascade\n"
              (format "#+SOURCE: [[file:../%s::*Sentence %d][q]]\n\n"
                      (file-name-nondirectory source-file) n)
              "* My Notes\n\n"
              "* Working Translation\n" (or wt "") "\n\n"
              "* Tibetan Text\nབདག\n\n"
              "* Reading\n** Interlinear\nbdag [ich]\n\n"
              (format "** Renderings\n- ⟦%d⟧ POISON-RENDERING-%d\n\n" n n)
              "* Tibetan Analysis\n"
              (format "** Translation\nPOISON-CLAUDE-%d\n\n" n)
              (format "** DharmaMitra Translation\nPOISON-DM-%d\n\n" n)
              (format "** Provided Translations\nPOISON-LOPEZ-%d\n\n" n)
              "* Footnotes\n" (or footnotes "") "\n"))
    f))

(defmacro tibetan-translation-doc-test--with-corpus (&rest body)
  "Fixture corpus: the §-grouped source + analysis/ with sentences
1 (pre-§, filled), 2 (§167, filled + footnote), 3 (§167, EMPTY WT),
4 (§168, filled + colliding footnote label).  Binds SOURCE-FILE,
DIR, ANALYSIS-DIR."
  (declare (indent 0))
  `(tibetan-translation-doc-test--with-source
     (let ((analysis-dir (expand-file-name "analysis" dir)))
       (make-directory analysis-dir)
       (tibetan-translation-doc-test--sent-file
        1 analysis-dir source-file "Der Vorspann-Satz." nil)
       (tibetan-translation-doc-test--sent-file
        2 analysis-dir source-file
        "Der Ehrwürdige[fn:x] sprach lange."
        "[fn:x] Definition aus Satz zwei.")
       (tibetan-translation-doc-test--sent-file
        3 analysis-dir source-file nil nil)
       (tibetan-translation-doc-test--sent-file
        4 analysis-dir source-file
        "Und dann ging er.[fn:x]"
        "[fn:x] Definition aus Satz vier.")
       ,@body)))

;; ----------------------------------------------------------------------------
;; Builder
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-translation-doc-build-groups-and-orders ()
  "The stitched document carries `* §167' before `* §168', bodies
in source order, a GENERATED marker header, and the pre-§ group."
  (tibetan-translation-doc-test--with-corpus
    (let* ((out (expand-file-name "uebersetzung.org" analysis-dir))
           (ret (tibetan-translation-doc-build source-file out))
           (s (with-temp-buffer (insert-file-contents out)
                                (buffer-string))))
      (should (equal out ret))
      (should (string-match-p "^# GENERATED" s))
      (let ((pre (string-match "Der Vorspann-Satz\\." s))
            (g167 (string-match "^\\* §167$" s))
            (rje (string-match "Der Ehrwürdige" s))
            (g168 (string-match "^\\* §168$" s))
            (ging (string-match "Und dann ging er\\." s)))
        (should (and pre g167 rje g168 ging))
        (should (< pre g167 rje g168 ging))))))

(ert-deftest tibetan-translation-doc-build-placeholders ()
  "An empty Working Translation renders a visible German
placeholder; a missing sent file its own."
  (tibetan-translation-doc-test--with-corpus
    ;; Sentence 4's file removed → missing-file placeholder.
    (delete-file (tibetan-sentence--filepath 4 analysis-dir source-file))
    (let* ((out (expand-file-name "uebersetzung.org" analysis-dir))
           (s (progn (tibetan-translation-doc-build source-file out)
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string)))))
      (should (string-match-p "\\[Satz 3 — noch keine Übersetzung\\]" s))
      (should (string-match-p "\\[Satz 4 — Analysedatei fehlt\\]" s)))))

(ert-deftest tibetan-translation-doc-build-copyright-lock ()
  "NOTHING but Working Translation + Footnotes reaches the output:
the poison strings planted in Renderings / Claude Translation /
DharmaMitra / Provided Translations never appear."
  (tibetan-translation-doc-test--with-corpus
    (let* ((out (expand-file-name "uebersetzung.org" analysis-dir))
           (s (progn (tibetan-translation-doc-build source-file out)
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string)))))
      (should-not (string-match-p "POISON-" s)))))

(ert-deftest tibetan-translation-doc-build-namespaces-end-to-end ()
  "The colliding [fn:x] of sentences 2 and 4 comes out as s002-x /
s004-x — anchors in the prose, definitions under ONE trailing
* Footnotes."
  (tibetan-translation-doc-test--with-corpus
    (let* ((out (expand-file-name "uebersetzung.org" analysis-dir))
           (s (progn (tibetan-translation-doc-build source-file out)
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string)))))
      (should (string-match-p "Ehrwürdige\\[fn:s002-x\\]" s))
      (should (string-match-p "ging er\\.\\[fn:s004-x\\]" s))
      (should (string-match-p "^\\[fn:s002-x\\] Definition aus Satz zwei\\." s))
      (should (string-match-p "^\\[fn:s004-x\\] Definition aus Satz vier\\." s))
      ;; Exactly one Footnotes heading, at the end.
      (should (= 1 (cl-count-if
                    (lambda (l) (equal l "* Footnotes"))
                    (split-string s "\n"))))
      (should-not (string-match-p "\\[fn:x\\]" s)))))

(ert-deftest tibetan-translation-doc-build-range-filter ()
  "FROM-SEC/TO-SEC restrict to the §-range (the Anhang-A.1 use
case); the pre-§ group is excluded when a range is given."
  (tibetan-translation-doc-test--with-corpus
    (let* ((out (expand-file-name "uebersetzung.org" analysis-dir))
           (s (progn (tibetan-translation-doc-build source-file out 168 168)
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string)))))
      (should (string-match-p "^\\* §168$" s))
      (should-not (string-match-p "^\\* §167$" s))
      (should-not (string-match-p "Vorspann-Satz" s))
      (should (string-match-p "Und dann ging er\\." s)))))

(ert-deftest tibetan-translation-doc-build-overwrite-guard ()
  "An existing file WITHOUT the GENERATED marker is never
overwritten (user-error, bytes untouched); the builder's own
previous output is."
  (tibetan-translation-doc-test--with-corpus
    (let ((out (expand-file-name "uebersetzung.org" analysis-dir)))
      (with-temp-file out (insert "Handgeschriebenes Dokument.\n"))
      (should-error (tibetan-translation-doc-build source-file out)
                    :type 'user-error)
      (should (equal "Handgeschriebenes Dokument.\n"
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string))))
      (delete-file out)
      ;; Twice over its own output: fine.
      (tibetan-translation-doc-build source-file out)
      (tibetan-translation-doc-build source-file out)
      (should (file-exists-p out)))))

;; ----------------------------------------------------------------------------
;; §-Ansicht generator
;; ----------------------------------------------------------------------------

(defun tibetan-translation-doc-test--add-gloss-tables (file body)
  "Insert a `** Gloss Tables' section with BODY into FILE's Reading."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Interlinear$")
    (beginning-of-line)
    (insert "** Gloss Tables\n" body "\n\n")
    (write-region (point-min) (point-max) file nil 'silent)))

(ert-deftest tibetan-translation-doc-section-view-demotes-table-headings ()
  "The cascade `** Gloss Tables' body now carries `*** Segment N'
headings; copied verbatim under the view's L3 `*** Glossentabellen'
they would become SIBLINGS and break the outline — the view
demotes them one level to `**** Segment N'."
  (tibetan-translation-doc-test--with-corpus
    (tibetan-translation-doc-test--add-gloss-tables
     (tibetan-sentence--filepath 2 analysis-dir source-file)
     "*** Segment 2\n| EDITIERTE-TABELLE |")
    (let* ((out (tibetan-translation-doc-section-view source-file 167))
           (s (with-temp-buffer (insert-file-contents out)
                                (buffer-string))))
      (should (string-match-p "^\\*\\*\\*\\* Segment 2$" s))
      (should-not (string-match-p "^\\*\\*\\* Segment 2$" s)))))

(ert-deftest tibetan-translation-doc-section-view-structure ()
  "The §167 view: `* §167', then `** Satz 2' with Tibetisch /
Glossentabellen (VERBATIM, incl. Carsten's edits) / Claude and DM
suggestions / his translation; `** Satz 3' shows the placeholder.
GENERATED marker present."
  (tibetan-translation-doc-test--with-corpus
    (tibetan-translation-doc-test--add-gloss-tables
     (tibetan-sentence--filepath 2 analysis-dir source-file)
     "Unit 1 — Segment 2\n| EDITIERTE-TABELLE |")
    (let* ((out (tibetan-translation-doc-section-view
                 source-file 167))
           (s (with-temp-buffer (insert-file-contents out)
                                (buffer-string))))
      (should (string-match-p "par-167-ansicht\\.org\\'" out))
      (should (string-prefix-p "# GENERATED" s))
      (let ((g (string-match "^\\* §167$" s))
            (s2 (string-match "^\\*\\* Satz 2$" s))
            (tib (string-match "^\\*\\*\\* Tibetisch$" s))
            (tbl (string-match "^| EDITIERTE-TABELLE |$" s))
            (cl (string-match "^\\*\\*\\* Vorschlag Claude$" s))
            (dm (string-match "^\\*\\*\\* Vorschlag DharmaMitra$" s))
            (cp (string-match "^\\*\\*\\* Übersetzung CP$" s))
            (s3 (string-match "^\\*\\* Satz 3$" s)))
        (should (and g s2 tib tbl cl dm cp s3))
        (should (< g s2 tib tbl cl dm cp s3)))
      ;; Suggestion bodies present (the fixture's poison markers are
      ;; the Claude/DM section bodies — HERE they are wanted).
      (should (string-match-p "POISON-CLAUDE-2" s))
      (should (string-match-p "POISON-DM-2" s))
      (should (string-match-p "\\[Satz 3 — noch keine Übersetzung\\]" s)))))

(ert-deftest tibetan-translation-doc-section-view-dual-name-and-drawer ()
  "The Rgyan cascade files carry the legacy `** Claude Translation'
heading (dual-name class, §5.18) — the view must find it; and a
suggestion body's leading :PROPERTIES: drawer (DM's
LAST_TRANSLATED) must not leak into the sheet."
  (tibetan-translation-doc-test--with-corpus
    (let ((f (tibetan-sentence--filepath 2 analysis-dir source-file)))
      (with-temp-file f
        (insert "#+TITLE: Sentence 2 Analysis\n#+TIBETAN_LAYOUT: cascade\n\n"
                "* Working Translation\nMein Satz.\n\n"
                "* Tibetan Text\nཆོས\n\n"
                "* Tibetan Analysis\n"
                "** Claude Translation\nLEGACY-CLAUDE-BODY\n\n"
                "** DharmaMitra Translation\n"
                ":PROPERTIES:\n:LAST_TRANSLATED: 2026-08-10\n:END:\n\n"
                "DM-BODY-OHNE-DRAWER\n\n"
                "* Footnotes\n")))
    (let* ((out (tibetan-translation-doc-section-view source-file 167))
           (s (with-temp-buffer (insert-file-contents out)
                                (buffer-string))))
      (should (string-match-p "^\\*\\*\\* Vorschlag Claude$" s))
      (should (string-match-p "LEGACY-CLAUDE-BODY" s))
      (should (string-match-p "DM-BODY-OHNE-DRAWER" s))
      (should-not (string-match-p ":LAST_TRANSLATED:" s))
      (should-not (string-match-p "^:PROPERTIES:$" s)))))

(ert-deftest tibetan-translation-doc-section-view-locks-references ()
  "Provided Translations (the Lopez/W&M slot) never reaches the
view; the ⟦N⟧ RENDERINGS — Claude's per-segment German — DO (in
the Rgyan corpus they carry the actual suggestion; the
sentence-level body is often just the placeholder).  Footnotes
namespaced and collected."
  (tibetan-translation-doc-test--with-corpus
    (let* ((out (tibetan-translation-doc-section-view source-file 167))
           (s (with-temp-buffer (insert-file-contents out)
                                (buffer-string))))
      (should-not (string-match-p "POISON-LOPEZ" s))
      ;; The rendering content of §167's sentences is IN the sheet…
      (should (string-match-p "⟦2⟧ POISON-RENDERING-2" s))
      ;; …but no foreign sentence leaks over.
      (should-not (string-match-p "POISON-RENDERING-4" s))
      (should (string-match-p "Ehrwürdige\\[fn:s002-x\\]" s))
      (should (string-match-p "^\\[fn:s002-x\\] Definition aus Satz zwei\\." s)))))

(ert-deftest tibetan-translation-doc-section-view-skips-placeholder-renderings ()
  "A still-awaiting rendering line is machine noise — skipped."
  (tibetan-translation-doc-test--with-corpus
    (let ((f (tibetan-sentence--filepath 3 analysis-dir source-file)))
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        (re-search-forward "^- ⟦3⟧ .*$")
        (replace-match "- ⟦3⟧ [Awaiting sentence translation…]")
        (write-region (point-min) (point-max) f nil 'silent)))
    (let* ((out (tibetan-translation-doc-section-view source-file 167))
           (s (with-temp-buffer (insert-file-contents out)
                                (buffer-string))))
      (should-not (string-match-p "⟦3⟧ \\[Awaiting" s)))))

(ert-deftest tibetan-translation-doc-section-view-guard-and-unknown-par ()
  "A hand-owned file at the target path is never overwritten; an
unknown § signals user-error."
  (tibetan-translation-doc-test--with-corpus
    (let ((out (expand-file-name "par-167-ansicht.org" analysis-dir)))
      (with-temp-file out (insert "Handgeschrieben.\n"))
      (should-error (tibetan-translation-doc-section-view
                     source-file 167)
                    :type 'user-error)
      (should (equal "Handgeschrieben.\n"
                     (with-temp-buffer (insert-file-contents out)
                                       (buffer-string)))))
    (should-error (tibetan-translation-doc-section-view source-file 999)
                  :type 'user-error)))

(provide 'tibetan-translation-doc-test)

;;; tibetan-translation-doc-test.el ends here
