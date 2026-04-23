;;; paragraph-analysis-spec.el --- BDD specs for paragraph analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Specifications for the C-c p A paragraph analysis feature.
;;
;; A paragraph is a `** §N'-headed org subtree whose Tibetan content
;; lives in a `*** Tibetisch' (or `*** Tibetisch (B2)') child.  This
;; layout is the one used by `Rgyan-comparative.org' for Gendün
;; Chöpel's Klu sgrub dgongs rgyan, but the detection / extraction
;; code is deliberately generic — any document that groups related
;; segments under `** §N' headings can drive this feature.
;;
;; Analysis files are named `par-NNN.org' (analogue of `seg-NNN.org'),
;; live in the document's `analysis/' sibling folder, and carry the
;; same scaffold sections: `* Tibetan Text', `* My Notes',
;; `* Working Translation', `* Auto-Analysis', `* Footnotes'.

;;; Code:

(require 'tibetan-bdd)

;; ============================================================================
;; PARAGRAPH DETECTION SUITE
;; ============================================================================

(define-bdd-suite paragraph-detection
    "Paragraph detection for §-headed org subtrees"

  (spec "Detect paragraph at heading"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §131\n*** Tibetisch (B2)\nབདུད་རྩི།\n")
             (goto-char (point-min))
             (search-forward "** §131")
             (beginning-of-line)
             (setq result (tibetan-org-at-paragraph-p)))
    :when result
    :then ((should result))
    :example "Cursor on `** §131' heading"
    :tags (:paragraph :detection :heading))

  (spec "Detect paragraph in content"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §131\n*** Tibetisch (B2)\nབདུད་རྩི།\n")
             (goto-char (point-min))
             (search-forward "བདུད་རྩི")
             (setq result (tibetan-org-at-paragraph-p)))
    :when result
    :then ((should result))
    :example "Cursor inside paragraph subtree"
    :tags (:paragraph :detection :content))

  (spec "Not detect on segment-style heading"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** Section\n*** Segment 1\nText།\n")
             (goto-char (point-min))
             (search-forward "*** Segment 1")
             (beginning-of-line)
             (setq result (tibetan-org-at-paragraph-p)))
    :when result
    :then ((should-not result))
    :example "`*** Segment N' (not `§N') should not match"
    :tags (:paragraph :detection :negative))

  (spec "Get paragraph ID as integer"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §131   :seg_1269_to_1275:\n*** Tibetisch (B2)\nText།\n")
             (goto-char (point-min))
             (search-forward "** §131")
             (setq result (tibetan-org-get-paragraph-id)))
    :when result
    :then ((should (= 131 result)))
    :example "Extract 131 from `** §131'"
    :tags (:paragraph :extraction :id))

  (spec "Get Tibetan text from `*** Tibetisch (B2)' child"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §131\n*** Tibetisch (B2)\nབདུད་ཀྱི་མཚོན་ཆ།\n\n*** Wylie\nbdud kyi mtshon cha\n")
             (goto-char (point-min))
             (search-forward "** §131")
             (setq result (tibetan-org-get-paragraph-text)))
    :when result
    :then ((should result)
           (should (string-match-p "བདུད་ཀྱི་མཚོན་ཆ" result))
           (should-not (string-match-p "bdud kyi" result)))
    :example "Rgyan-comparative layout"
    :tags (:paragraph :extraction :text :rgyan))

  (spec "Get Tibetan text from generic `*** Tibetisch' child"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §7\n*** Tibetisch\nདཔེར་ན།\n\n*** Übersetzung\n[placeholder]\n")
             (goto-char (point-min))
             (search-forward "** §7")
             (setq result (tibetan-org-get-paragraph-text)))
    :when result
    :then ((should result)
           (should (string-match-p "དཔེར་ན" result)))
    :example "Generic layout without (B2) suffix"
    :tags (:paragraph :extraction :text :generic)))

;; ============================================================================
;; PARAGRAPH FILEPATH SUITE
;; ============================================================================

(define-bdd-suite paragraph-filepath
    "Filename and filepath conventions for paragraph analysis"

  (spec "Paragraph filename uses par-NNN.org pattern"
    :given (setq input 131)
    :when (tibetan-analysis-paragraph-filename input)
    :then ((tibetan-bdd-assert-equal "par-131.org" result
            "Integer 131 -> par-131.org"))
    :example "§131 filename"
    :tags (:paragraph :filepath))

  (spec "Paragraph filename zero-pads below 100"
    :given (setq input 7)
    :when (tibetan-analysis-paragraph-filename input)
    :then ((tibetan-bdd-assert-equal "par-007.org" result
            "Integer 7 -> par-007.org (three-digit pad)"))
    :example "§7 filename"
    :tags (:paragraph :filepath :zero-pad))

  (spec "Paragraph filename accepts §-prefixed string"
    :given (setq input "§131")
    :when (tibetan-analysis-paragraph-filename input)
    :then ((tibetan-bdd-assert-equal "par-131.org" result
            "§131 string -> par-131.org"))
    :example "§131 as string"
    :tags (:paragraph :filepath :string-input)))

;; ============================================================================
;; PARAGRAPH FILE CREATION SUITE
;; ============================================================================

(define-bdd-suite paragraph-file-creation
    "Paragraph analysis file scaffold"

  (spec "Create paragraph file with standard scaffold"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-spec" t))
                  (source (expand-file-name "Rgyan-comparative.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (with-temp-file source
               (insert "* Text\n** §131\n*** Tibetisch (B2)\nབདུད་རྩི།\n"))
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir)))
               (tibetan-analysis-create-paragraph-file
                131 "བདུད་རྩི།" source "** Wylie\nbdud rtsi\n")
               (setq result (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "par-131.org" analysis-dir))
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-contains result "#+TITLE: Paragraph 131 Analysis"
            "Title header with paragraph number")
           (tibetan-bdd-assert-contains result "#+STARTUP: showall"
            "Startup convention matches segment scaffold")
           (tibetan-bdd-assert-contains result "#+SOURCE:"
            "Backlink header present")
           (tibetan-bdd-assert-contains result "* Tibetan Text"
            "Tibetan Text section present")
           (tibetan-bdd-assert-contains result "བདུད་རྩི"
            "Tibetan content inserted")
           (tibetan-bdd-assert-contains result "* My Notes"
            "My Notes user section")
           (tibetan-bdd-assert-contains result "* Working Translation"
            "Working Translation user section")
           (tibetan-bdd-assert-contains result "* Auto-Analysis"
            "Auto-Analysis section with generated content")
           (tibetan-bdd-assert-contains result "** Wylie"
            "Auto-content passed through verbatim")
           (tibetan-bdd-assert-contains result "* Footnotes"
            "Footnotes section last"))
    :example "Create par-131.org"
    :tags (:paragraph :file-creation :scaffold :critical))

  (spec "Source link points to §N heading"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-spec" t))
                  (source (expand-file-name "Rgyan-comparative.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir)))
               (tibetan-analysis-create-paragraph-file
                42 "Text" source "** Wylie\nbodyplain\n")
               (setq result (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "par-042.org" analysis-dir))
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-matches "#\\+SOURCE:.*::\\*§42" result
            "Source header encodes `::*§42' org-link search")
           (tibetan-bdd-assert-contains result "Rgyan-comparative.org"
            "Source filename present in backlink"))
    :example "par-042.org source header"
    :tags (:paragraph :file-creation :backlink)))

;; ============================================================================
;; PARAGRAPH ENTRY-POINT SUITE
;; ============================================================================

(define-bdd-suite paragraph-entry-points
    "Interactive commands: C-c p A / C-c p R"

  (spec "`tibetan-open-paragraph-analysis' exists and is interactive"
    :given (setq fn 'tibetan-open-paragraph-analysis)
    :when (and (fboundp fn) (commandp fn))
    :then ((should result))
    :example "C-c p A entry point"
    :tags (:paragraph :entry-point))

  (spec "`tibetan-reanalyze-paragraph' exists and is interactive"
    :given (setq fn 'tibetan-reanalyze-paragraph)
    :when (and (fboundp fn) (commandp fn))
    :then ((should result))
    :example "C-c p R entry point"
    :tags (:paragraph :entry-point))

  (spec "Open paragraph analysis creates par-NNN.org from Tibetisch child"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-open" t))
                  (source (expand-file-name "Rgyan-comparative.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (with-temp-file source
               (insert "#+TITLE: Test\n\n* Text\n\n** §7\n\n*** Tibetisch (B2)\nདཔེར་ན་ཆོས།\n\n*** Wylie\nbody\n"))
             ;; Stub display + Claude + analysis generation so the entry
             ;; point runs to completion in batch without side effects.
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir))
                       ((symbol-function 'display-buffer-in-side-window)
                        (lambda (buf _alist) buf))
                       ((symbol-function 'tibetan-analysis-setup-faces)
                        (lambda () nil))
                       ((symbol-function 'tibetan-analysis-generate-content)
                        (lambda (text &rest _) (format "** Wylie\nstub-wylie for %d chars\n" (length text))))
                       ((symbol-function 'tibetan-analysis--request-claude-translation)
                        (lambda (&rest _) nil)))
               (let ((buf (find-file-noselect source)))
                 (with-current-buffer buf
                   (org-mode)
                   (goto-char (point-min))
                   (search-forward "** §7")
                   (tibetan-open-paragraph-analysis))
                 (kill-buffer buf)))
             (setq result
                   (let ((f (expand-file-name "par-007.org" analysis-dir)))
                     (when (file-exists-p f)
                       (with-temp-buffer
                         (insert-file-contents f)
                         (buffer-string))))))
    :when result
    :then ((should result)
           (tibetan-bdd-assert-contains result "#+TITLE: Paragraph 7 Analysis"
            "Scaffold header")
           (tibetan-bdd-assert-contains result "དཔེར་ན་ཆོས"
            "Tibetan Text pulled from `*** Tibetisch (B2)' child")
           (tibetan-bdd-assert-contains result "stub-wylie"
            "Auto-content from generate-content included"))
    :example "End-to-end: C-c p A on `** §7'"
    :tags (:paragraph :entry-point :integration :critical)))

;; ============================================================================
;; CONTEXT-DISPATCH SUITE
;; ============================================================================
;;
;; Because `C-c p' collides with Projectile's prefix map, paragraph
;; analysis is dispatched via the existing `C-c u A' / `C-c u R'
;; bindings based on cursor context: paragraph (`** §N') takes
;; precedence, falling through to segment (`*** Segment N' / legacy
;; 〔seg:…〕) when not in a paragraph.  Users type one command and
;; it does the right thing.

(define-bdd-suite paragraph-dispatch
    "C-c u A dispatches paragraph vs segment by cursor context"

  (spec "On `** §N' heading, C-c u A creates par-NNN.org"
    :given (let* ((tmpdir (make-temp-file "tibetan-dispatch-par" t))
                  (source (expand-file-name "Rgyan-comparative.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (with-temp-file source
               (insert "#+TITLE: Test\n\n* Text\n\n** §131\n\n*** Tibetisch (B2)\nབདུད་རྩི།\n"))
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir))
                       ((symbol-function 'display-buffer-in-side-window)
                        (lambda (buf _) buf))
                       ((symbol-function 'tibetan-analysis-setup-faces)
                        (lambda () nil))
                       ((symbol-function 'tibetan-analysis-generate-content)
                        (lambda (&rest _) "** Wylie\nstub\n"))
                       ((symbol-function 'tibetan-analysis--request-claude-translation)
                        (lambda (&rest _) nil)))
               (let ((buf (find-file-noselect source)))
                 (with-current-buffer buf
                   (org-mode)
                   (goto-char (point-min))
                   (search-forward "** §131")
                   (tibetan-open-segment-analysis))
                 (kill-buffer buf)))
             (setq result
                   (list
                    :par (file-exists-p (expand-file-name "par-131.org" analysis-dir))
                    :seg (file-exists-p (expand-file-name "seg-131.org" analysis-dir)))))
    :when result
    :then ((should (plist-get result :par))
           (should-not (plist-get result :seg)))
    :example "C-c u A on `** §131' → par-131.org, not seg-131.org"
    :tags (:paragraph :dispatch :critical))

  (spec "On `*** Sentence N', C-c u A creates sent-NNN.org"
    :given (let* ((tmpdir (make-temp-file "tibetan-dispatch-sent" t))
                  (source (expand-file-name "classroom.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (with-temp-file source
               (insert "#+TITLE: Test\n\n* Tibetan Text\n\n** Section 1\n\n*** Sentence 1\n\n**** Segment 1\nབདུད་རྩི།\n"))
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir))
                       ((symbol-function 'display-buffer-in-side-window)
                        (lambda (buf _) buf))
                       ((symbol-function 'tibetan-analysis-setup-faces)
                        (lambda () nil))
                       ((symbol-function 'tibetan-sentence-persist--generate-content)
                        (lambda (&rest _) "** Wylie\nstub\n"))
                       ((symbol-function 'tibetan-analysis-generate-content)
                        (lambda (&rest _) "** Wylie\nstub\n"))
                       ((symbol-function 'tibetan-analysis--request-claude-translation)
                        (lambda (&rest _) nil))
                       ((symbol-function 'tibetan-sentence-persist--request-claude-translation)
                        (lambda (&rest _) nil)))
               (let ((buf (find-file-noselect source)))
                 (with-current-buffer buf
                   (org-mode)
                   (goto-char (point-min))
                   (search-forward "*** Sentence 1")
                   (tibetan-open-segment-analysis))
                 (kill-buffer buf)))
             (setq result
                   (list
                    :sent (not (null
                                (directory-files analysis-dir nil "^sent-.*\\.org$")))
                    :seg (not (null
                               (directory-files analysis-dir nil "^seg-.*\\.org$")))
                    :par (not (null
                               (directory-files analysis-dir nil "^par-.*\\.org$"))))))
    :when result
    :then ((should (plist-get result :sent))
           (should-not (plist-get result :seg))
           (should-not (plist-get result :par)))
    :example "C-c u A on `*** Sentence 1' → sent-*.org"
    :tags (:sentence :dispatch :critical))

  (spec "Segment wins over sentence (nested `**** Segment' under `*** Sentence')"
    :given (let* ((tmpdir (make-temp-file "tibetan-dispatch-nested" t))
                  (source (expand-file-name "classroom.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (with-temp-file source
               (insert "#+TITLE: Test\n\n* Tibetan Text\n\n** Section 1\n\n*** Sentence 1\n\n**** Segment 1\nབདུད་རྩི།\n"))
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir))
                       ((symbol-function 'display-buffer-in-side-window)
                        (lambda (buf _) buf))
                       ((symbol-function 'tibetan-analysis-setup-faces)
                        (lambda () nil))
                       ((symbol-function 'tibetan-analysis-generate-content)
                        (lambda (&rest _) "** Wylie\nstub\n"))
                       ((symbol-function 'tibetan-analysis--request-claude-translation)
                        (lambda (&rest _) nil)))
               (let ((buf (find-file-noselect source)))
                 (with-current-buffer buf
                   (org-mode)
                   (goto-char (point-min))
                   (search-forward "**** Segment 1")
                   (tibetan-open-segment-analysis))
                 (kill-buffer buf)))
             (setq result
                   (list
                    :seg (file-exists-p (expand-file-name "seg-001.org" analysis-dir))
                    :sent (not (null
                                (directory-files analysis-dir nil "^sent-.*\\.org$"))))))
    :when result
    :then ((should (plist-get result :seg))
           (should-not (plist-get result :sent)))
    :example "Most-specific-wins in nested Sentence→Segment layout"
    :tags (:segment :dispatch :priority :critical))

  (spec "On `*** Segment N' heading, C-c u A still creates seg-NNN.org"
    :given (let* ((tmpdir (make-temp-file "tibetan-dispatch-seg" t))
                  (source (expand-file-name "classroom.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (with-temp-file source
               (insert "#+TITLE: Test\n\n* Tibetan Text\n\n** Sentence 1\n\n*** Segment 1\nབདུད་རྩི།\n"))
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir))
                       ((symbol-function 'display-buffer-in-side-window)
                        (lambda (buf _) buf))
                       ((symbol-function 'tibetan-analysis-setup-faces)
                        (lambda () nil))
                       ((symbol-function 'tibetan-analysis-generate-content)
                        (lambda (&rest _) "** Wylie\nstub\n"))
                       ((symbol-function 'tibetan-analysis--request-claude-translation)
                        (lambda (&rest _) nil)))
               (let ((buf (find-file-noselect source)))
                 (with-current-buffer buf
                   (org-mode)
                   (goto-char (point-min))
                   (search-forward "*** Segment 1")
                   (tibetan-open-segment-analysis))
                 (kill-buffer buf)))
             (setq result
                   (list
                    :seg (file-exists-p (expand-file-name "seg-001.org" analysis-dir))
                    :par (file-exists-p (expand-file-name "par-001.org" analysis-dir)))))
    :when result
    :then ((should (plist-get result :seg))
           (should-not (plist-get result :par)))
    :example "Existing segment flow preserved"
    :tags (:paragraph :dispatch :regression :critical)))

(provide 'paragraph-analysis-spec)
;;; paragraph-analysis-spec.el ends here
