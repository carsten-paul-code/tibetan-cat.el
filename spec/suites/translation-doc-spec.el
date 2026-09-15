;;; translation-doc-spec.el --- BDD: stitch the translation document -*- lexical-binding: t -*-

;;; Commentary:
;; Masterarbeit view 3 (2026-09-15): Carsten's per-sentence
;; `* Working Translation' + `* Footnotes' slots stitch into ONE
;; generated, §-grouped translation document — footnotes namespaced
;; per sentence, gaps visible, reference translations locked out.

;;; Code:

(require 'tibetan-bdd)
(require 'cl-lib)
(require 'tibetan-translation-doc)
(require 'tibetan-sentence-persist)

(define-bdd-suite translation-doc
    "Translation document stitcher (Masterarbeit view 3)"

  (spec "Stitch a §-grouped translation document from cascade sent files"
    :given (let* ((tmpdir (make-temp-file "ttdoc-bdd" t))
                  (source (expand-file-name "quelle.org" tmpdir))
                  (analysis (expand-file-name "analysis" tmpdir)))
             (make-directory analysis)
             (with-temp-file source
               (insert "#+TITLE: Q\n#+TIBETAN_LAYOUT: cascade\n\n"
                       "* Tibetan Text\n"
                       "** Section §167\n:PROPERTIES:\n"
                       ":LOPEZ_SECTION: 167\n:END:\n"
                       "*** Sentence 1\n**** Segment 1\nབདག\n"
                       "*** Sentence 2\n**** Segment 2\nཆོས\n"))
             (let ((f1 (tibetan-sentence--filepath 1 analysis source))
                   (f2 (tibetan-sentence--filepath 2 analysis source)))
               (with-temp-file f1
                 (insert "#+TITLE: S1\n\n"
                         "* Working Translation\n"
                         "Der Meister[fn:x] lehrte.\n\n"
                         "* Tibetan Text\nབདག\n\n"
                         "* Tibetan Analysis\n"
                         "** Provided Translations\nPOISON-LOPEZ\n\n"
                         "* Footnotes\n[fn:x] Erste Definition.\n"))
               (with-temp-file f2
                 (insert "#+TITLE: S2\n\n"
                         "* Working Translation\n\n\n"
                         "* Tibetan Text\nཆོས\n\n* Footnotes\n")))
             (let ((out (expand-file-name "uebersetzung.org" analysis)))
               (tibetan-translation-doc-build source out)
               (setq result (with-temp-buffer
                              (insert-file-contents out)
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-contains result "* §167"
            "§-heading emitted")
           (tibetan-bdd-assert-contains result "Der Meister[fn:s001-x] lehrte."
            "prose with namespaced anchor")
           (tibetan-bdd-assert-contains result "[fn:s001-x] Erste Definition."
            "namespaced definition collected")
           (tibetan-bdd-assert-contains result
            "[Satz 2 — noch keine Übersetzung]"
            "gap visible as placeholder")
           (tibetan-bdd-assert-not-contains result "POISON-LOPEZ"
            "reference translations locked out")
           (should (string-prefix-p "# GENERATED" result)))
    :example "two sentences of §167 → one generated document"
    :tags (:translation-doc :stitcher :critical)))

(provide 'translation-doc-spec)

;;; translation-doc-spec.el ends here
