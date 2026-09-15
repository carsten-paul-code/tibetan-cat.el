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

(provide 'tibetan-translation-doc-test)

;;; tibetan-translation-doc-test.el ends here
