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
  (add-to-list 'load-path (expand-file-name "../persist" base-dir)))

(require 'tibetan-translation-doc)

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

(provide 'tibetan-translation-doc-test)

;;; tibetan-translation-doc-test.el ends here
