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
;; PARAGRAPH REFERENCE-TRANSLATIONS SUITE
;; ============================================================================
;;
;; A paragraph in the Rgyan-comparative.org layout carries reference
;; translations as sibling subsections of `** §N' — `*** Lopez 2006',
;; `*** Wangjié & Mulligan', etc.  The CAT tool extracts these as
;; alist of (heading . body) so they can flow into both the
;; par-NNN.org scaffold and the Claude prompt context.

(define-bdd-suite paragraph-references
    "Sibling-section reference-translation extraction (generic)"

  (spec "Extract Lopez and Wangjié subsections as references"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §131\n*** Tibetisch (B2)\nབདུད།\n\n*** Wylie\nbdud\n\n*** Lopez 2006\nThe demons of...\n\n*** Wangjié & Mulligan\nThe weapons of demons...\n\n*** Eigene Übersetzung (Entwurf)\n[draft]\n")
             (goto-char (point-min))
             (search-forward "** §131")
             (setq result (tibetan-org-get-paragraph-references)))
    :when result
    :then ((should result)
           (should (= 2 (length result)))
           (should (assoc "Lopez 2006" result))
           (should (assoc "Wangjié & Mulligan" result))
           (should-not (assoc "Tibetisch (B2)" result))
           (should-not (assoc "Wylie" result))
           (should-not (assoc "Eigene Übersetzung (Entwurf)" result))
           (should (string-match-p "demons" (cdr (assoc "Lopez 2006" result))))
           (should (string-match-p "weapons" (cdr (assoc "Wangjié & Mulligan" result)))))
    :example "Rgyan-comparative paragraph layout"
    :tags (:paragraph :references :extraction :critical))

  (spec "Skip empty reference subsections"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §1\n*** Tibetisch\nFoo\n\n*** Lopez 2006\n\n\n*** Wangjié & Mulligan\nReal content here\n")
             (goto-char (point-min))
             (search-forward "** §1")
             (setq result (tibetan-org-get-paragraph-references)))
    :when result
    :then ((should (= 1 (length result)))
           (should (assoc "Wangjié & Mulligan" result))
           (should-not (assoc "Lopez 2006" result)))
    :example "Empty Lopez body filtered out"
    :tags (:paragraph :references :extraction))

  (spec "Skip Apparat / Notes / Footnotes"
    :given (with-temp-buffer
             (org-mode)
             (insert "* Text\n** §1\n*** Tibetisch\nFoo\n\n*** Lopez 2006\nA translation\n\n*** Apparat und Notizen\nB2: foo | H: bar\n\n*** Footnotes\n[fn:1] note\n")
             (goto-char (point-min))
             (search-forward "** §1")
             (setq result (tibetan-org-get-paragraph-references)))
    :when result
    :then ((should (= 1 (length result)))
           (should (assoc "Lopez 2006" result))
           (should-not (assoc "Apparat und Notizen" result))
           (should-not (assoc "Footnotes" result)))
    :example "Philological-note sections excluded"
    :tags (:paragraph :references :extraction))

  (spec "Claude prompt helper formats Reference Translations as labeled blocks"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-prompt" t))
                  (analysis-file (expand-file-name "par-007.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Paragraph 7\n\n* Tibetan Text\nFoo།\n\n* My Notes\n\n\n* Working Translation\n\n\n* Reference Translations\n** Lopez 2006\nLopez body line 1.\nLopez body line 2.\n\n** Wangjié & Mulligan\nWangjié body.\n\n* Auto-Analysis\n** Wylie\nfoo /\n\n* Footnotes\n"))
             (setq result
                   (tibetan-analysis--format-reference-translations
                    analysis-file)))
    :when result
    :then ((should result)
           (tibetan-bdd-assert-contains result "reference translations of THIS passage"
            "Instruction header present")
           (tibetan-bdd-assert-contains result "## Grammar"
            "Instruction references the Grammar section for divergence notes")
           (tibetan-bdd-assert-contains result "— Lopez 2006:"
            "Lopez label emitted")
           (tibetan-bdd-assert-contains result "Lopez body line 1"
            "Lopez body included")
           (tibetan-bdd-assert-contains result "— Wangjié & Mulligan:"
            "Wangjié label emitted")
           (tibetan-bdd-assert-contains result "Wangjié body"
            "Wangjié body included"))
    :example "Claude user-prompt block from par-NNN.org Reference Translations"
    :tags (:paragraph :references :claude :prompt :critical))

  (spec "Claude prompt helper returns nil when section absent (segment files)"
    :given (let* ((tmpdir (make-temp-file "tibetan-seg-prompt" t))
                  (analysis-file (expand-file-name "seg-001.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Segment 1\n\n* Tibetan Text\nFoo།\n\n* My Notes\n\n\n* Working Translation\n\n\n* Auto-Analysis\n** Wylie\nfoo /\n\n* Footnotes\n"))
             (setq result
                   (tibetan-analysis--format-reference-translations
                    analysis-file)))
    :when result
    :then ((should-not result))
    :example "seg-NNN.org has no top-level Reference Translations"
    :tags (:paragraph :references :claude :prompt))

  (spec "Reference Translations preserved across reanalyze"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-preserve" t))
                  (source (expand-file-name "comp.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir))
                  (analysis-file (expand-file-name "par-007.org" analysis-dir)))
             (make-directory analysis-dir)
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir)))
               (tibetan-analysis-create-paragraph-file
                7 "བདུད།" source "** Wylie\nbdud\n"
                '(("Lopez 2006" . "Original Lopez body — DO NOT WIPE")
                  ("Wangjié & Mulligan" . "Wangjié body — DO NOT WIPE")))
               ;; Simulate user editing the references manually
               ;; (e.g. correcting an OCR typo in Wangjié):
               (with-temp-buffer
                 (insert-file-contents analysis-file)
                 (goto-char (point-min))
                 (search-forward "Wangjié body — DO NOT WIPE")
                 (replace-match "Wangjié body USER-EDITED")
                 (write-file analysis-file))
               ;; Now reanalyze with fresh auto-content
               (tibetan-analysis-regenerate-auto
                analysis-file "བདུད།" "** Wylie\nbdud REGENERATED\n")
               (setq result (with-temp-buffer
                              (insert-file-contents analysis-file)
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-contains result "Wangjié body USER-EDITED"
            "User edits to references survive reanalyze")
           (tibetan-bdd-assert-contains result "Original Lopez body — DO NOT WIPE"
            "Untouched references survive reanalyze")
           (tibetan-bdd-assert-contains result "bdud REGENERATED"
            "Auto-Analysis IS regenerated"))
    :example "Reference Translations preservation invariant"
    :tags (:paragraph :references :preservation :critical))

  (spec "Paragraph auto-content suppresses the inner Reference Translations placeholder"
    :given (when (fboundp 'tibetan-analysis-generate-content)
             (setq result (tibetan-analysis-generate-content
                           "བདུད།" "§42" "")))
    :when result
    :then ((should result)
           ;; Top-level *** Reference Translations is the segment-pipeline
           ;; legacy slot; for paragraph files it duplicates the par-NNN.org
           ;; top-level `* Reference Translations' section that's populated
           ;; from comparative siblings.  Suppressed when seg-id is `§N'.
           (should-not (string-match-p "^\\*\\*\\* Reference Translations$"
                                       result))
           (should-not (string-match-p "Add reference translations here"
                                       result)))
    :example "auto-content for `§42' has no inner Reference Translations slot"
    :tags (:paragraph :dedup :auto-content :critical))

  (spec "Segment auto-content no longer emits the inner Reference Translations placeholder"
    :given (when (fboundp 'tibetan-analysis-generate-content)
             (setq result (tibetan-analysis-generate-content
                           "བདུད།" "Segment 7" "")))
    :when result
    :then ((should result)
           ;; §5.21 Commit 6/7 (2026-05-20):  `** Provided Translations'
           ;; became a USER-CONTENT slot (preserved across reanalyze
           ;; like `* My Notes' / `* Working Translation').  The nested
           ;; `*** Reference Translations' auto-fill that used to live
           ;; inside PT was retired in the same commit — Carsten now
           ;; pastes reference translations manually, and the new
           ;; nested-body preservation machinery keeps them verbatim
           ;; across regenerate.  Paragraph-mode files still get
           ;; top-level `* Reference Translations' from
           ;; `tibetan-analysis-create-paragraph-file' (unchanged).
           (should-not (string-match-p "\\*\\*\\* Reference Translations"
                                       result))
           ;; PT itself IS present — as an empty user-content
           ;; placeholder.
           (should (string-match-p "^\\*\\* Provided Translations$"
                                   result)))
    :example "auto-content for `Segment 7' has no inner RT slot post-§5.21"
    :tags (:segment :auto-content :layout-revision))

  (spec "Scaffold creates an Apparatus section between Auto-Analysis and Footnotes"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-app" t))
                  (source (expand-file-name "comp.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir)))
               (tibetan-analysis-create-paragraph-file
                42 "བདུད།" source "** Wylie\nbdud\n" nil)
               (setq result (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "par-042.org" analysis-dir))
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-contains result "* Apparatus"
            "Apparatus section emitted")
           ;; Position invariant: Apparatus must appear after Auto-Analysis
           ;; and before Footnotes in the new scaffold.
           (should (let ((auto (string-match "^\\* Auto-Analysis" result))
                         (app (string-match "^\\* Apparatus" result))
                         (foot (string-match "^\\* Footnotes" result)))
                     (and auto app foot
                          (< auto app)
                          (< app foot)))))
    :example "par-042.org scaffold ordering with Apparatus"
    :tags (:paragraph :apparatus :scaffold :critical))

  (spec "Apparatus preserved across reanalyze"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-app-pres" t))
                  (source (expand-file-name "comp.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir))
                  (analysis-file (expand-file-name "par-042.org" analysis-dir)))
             (make-directory analysis-dir)
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir)))
               (tibetan-analysis-create-paragraph-file
                42 "བདུད།" source "** Wylie\nbdud\n" nil)
               ;; Simulate user editing the apparatus
               (with-temp-buffer
                 (insert-file-contents analysis-file)
                 (goto-char (point-min))
                 (search-forward "* Apparatus")
                 (forward-line 2)
                 (insert "B2: rang lugs | H: gzhan lugs (fn. 55) — B2/G stützen rang.\n")
                 (write-file analysis-file))
               (tibetan-analysis-regenerate-auto
                analysis-file "བདུད།" "** Wylie\nbdud REGEN\n")
               (setq result (with-temp-buffer
                              (insert-file-contents analysis-file)
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-contains result "B2: rang lugs | H: gzhan lugs"
            "User edits to apparatus survive reanalyze")
           (tibetan-bdd-assert-contains result "bdud REGEN"
            "Auto-Analysis IS regenerated"))
    :example "Apparatus preservation invariant"
    :tags (:paragraph :apparatus :preservation :critical))

  (spec "Segment files (seg-NNN.org) get NO empty Apparatus on reanalyze"
    :given (let* ((tmpdir (make-temp-file "tibetan-seg-noapp" t))
                  (analysis-file (expand-file-name "seg-001.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Segment 1\n#+TIBETAN_HASH: x\n\n* Tibetan Text\nFoo།\n\n* My Notes\n\n\n* Working Translation\n\n\n* Auto-Analysis\n** Wylie\nfoo /\n\n* Footnotes\n"))
             (tibetan-analysis-regenerate-auto
              analysis-file "Foo།" "** Wylie\nfoo REGEN\n")
             (setq result (with-temp-buffer
                            (insert-file-contents analysis-file)
                            (buffer-string))))
    :when result
    :then ((should-not (string-match-p "^\\* Apparatus" result))
           (tibetan-bdd-assert-contains result "foo REGEN"
            "Segment Auto-Analysis still regenerates"))
    :example "Seg files unaffected by Apparatus addition"
    :tags (:segment :apparatus :backwards-compat :critical))

  (spec "References written into par-NNN.org scaffold"
    :given (let* ((tmpdir (make-temp-file "tibetan-par-refs" t))
                  (source (expand-file-name "Rgyan-comparative.org" tmpdir))
                  (analysis-dir (expand-file-name "analysis" tmpdir)))
             (make-directory analysis-dir)
             (cl-letf (((symbol-function 'tibetan-analysis-get-folder)
                        (lambda () analysis-dir)))
               (tibetan-analysis-create-paragraph-file
                131 "བདུད།" source "** Wylie\nbdud\n"
                '(("Lopez 2006" . "The demons of...")
                  ("Wangjié & Mulligan" . "The weapons of demons...")))
               (setq result (with-temp-buffer
                              (insert-file-contents
                               (expand-file-name "par-131.org" analysis-dir))
                              (buffer-string)))))
    :when result
    :then ((tibetan-bdd-assert-contains result "* Reference Translations"
            "Reference Translations top-level section")
           (tibetan-bdd-assert-contains result "** Lopez 2006"
            "Lopez subsection present")
           (tibetan-bdd-assert-contains result "The demons of..."
            "Lopez body inserted")
           (tibetan-bdd-assert-contains result "** Wangjié & Mulligan"
            "Wangjié subsection present")
           (tibetan-bdd-assert-contains result "The weapons of demons..."
            "Wangjié body inserted"))
    :example "par-131.org scaffold with references"
    :tags (:paragraph :references :scaffold :critical)))

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

;; ============================================================================
;; TRANSLATION COMPARISON SUITE
;; ============================================================================
;;
;; The `* Translation Comparison' section in par-NNN.org carries
;; Claude's pairwise similarity matrix between Lopez / Wangjié /
;; (future Mitra) / User translations of the paragraph, plus a
;; diagnostic block explaining substantive divergences.  Refreshed
;; via a separate command (C-c u T) — NOT auto-regenerated by
;; `tibetan-reanalyze-paragraph'.  This way the matrix represents
;; an explicit comparison snapshot the user requests; reanalysis
;; doesn't quietly overwrite it.

(define-bdd-suite translation-comparison
    "Pairwise translation-similarity matrix in par-NNN.org"

  (spec "Collect translations from par-NNN.org (refs + working)"
    :given (let* ((tmpdir (make-temp-file "tibetan-tcomp-collect" t))
                  (analysis-file (expand-file-name "par-007.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Paragraph 7\n\n* Tibetan Text\nFoo།\n\n* My Notes\n\n\n* Working Translation\nMy German rendering here.\n\n* Reference Translations\n** Lopez 2006\nLopez body.\n\n** Wangjié & Mulligan\nWangjié body.\n\n* Auto-Analysis\n** Wylie\nfoo /\n\n* Footnotes\n"))
             (setq result
                   (tibetan-analysis--collect-paragraph-translations
                    analysis-file)))
    :when result
    :then ((should result)
           (should (= 3 (length result)))
           (should (assoc "Lopez 2006" result))
           (should (assoc "Wangjié & Mulligan" result))
           (should (assoc "Working Translation" result))
           (should (string-match-p "Lopez body"
                                   (cdr (assoc "Lopez 2006" result))))
           (should (string-match-p "My German"
                                   (cdr (assoc "Working Translation" result)))))
    :example "Collects all 3 translations including user's own"
    :tags (:translation-comparison :collection :critical))

  (spec "Skip empty Working Translation in collection"
    :given (let* ((tmpdir (make-temp-file "tibetan-tcomp-empty" t))
                  (analysis-file (expand-file-name "par-007.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Paragraph 7\n\n* Working Translation\n\n\n* Reference Translations\n** Lopez 2006\nLopez body.\n\n* Auto-Analysis\n"))
             (setq result
                   (tibetan-analysis--collect-paragraph-translations
                    analysis-file)))
    :when result
    :then ((should result)
           (should (= 1 (length result)))
           (should (assoc "Lopez 2006" result))
           (should-not (assoc "Working Translation" result)))
    :example "Empty user translation is filtered"
    :tags (:translation-comparison :collection))

  (spec "Parse Claude's matrix-response into org-table rows"
    :given (setq response
                 "## Comparison Matrix\n\n| | Lopez | Wangjié | User |\n|---|---|---|---|\n| Lopez | 1.00 | 0.74 | 0.65 |\n| Wangjié | 0.74 | 1.00 | 0.71 |\n| User | 0.65 | 0.71 | 1.00 |\n\n## Diagnostic\n\nLopez and Wangjié agree on the main verb but diverge on the modifier scope.  The user's reading aligns with Lopez here.")
    :when (tibetan-analysis--parse-comparison-response response)
    :then ((should result)
           (should (plist-get result :matrix))
           (should (plist-get result :diagnostic))
           (should (string-match-p "0\\.74" (plist-get result :matrix)))
           (should (string-match-p "diverge on the modifier"
                                   (plist-get result :diagnostic))))
    :example "Markdown matrix → org table; diagnostic prose preserved"
    :tags (:translation-comparison :parsing :critical))

  (spec "Write Translation Comparison section into par-NNN.org"
    :given (let* ((tmpdir (make-temp-file "tibetan-tcomp-write" t))
                  (analysis-file (expand-file-name "par-007.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Paragraph 7\n\n* Tibetan Text\nFoo།\n\n* Working Translation\nMy text\n\n* Auto-Analysis\n** Wylie\nfoo /\n\n* Footnotes\n"))
             (tibetan-analysis--write-comparison-section
              analysis-file
              "| Foo | Bar |\n|---|---|\n| 1 | 2 |"
              "Sample diagnostic body.")
             (setq result (with-temp-buffer
                            (insert-file-contents analysis-file)
                            (buffer-string))))
    :when result
    :then ((tibetan-bdd-assert-contains result "* Translation Comparison"
            "Top-level section emitted")
           (tibetan-bdd-assert-contains result "Sample diagnostic body"
            "Diagnostic body present")
           (tibetan-bdd-assert-contains result "| Foo | Bar |"
            "Matrix table present")
           ;; Section position: between Working Translation and Auto-Analysis
           (should (let ((wt (string-match "^\\* Working Translation" result))
                         (tc (string-match "^\\* Translation Comparison" result))
                         (auto (string-match "^\\* Auto-Analysis" result)))
                     (and wt tc auto (< wt tc) (< tc auto)))))
    :example "Comparison section written + correctly positioned"
    :tags (:translation-comparison :write :critical))

  (spec "Translation Comparison section preserved across reanalyze"
    :given (let* ((tmpdir (make-temp-file "tibetan-tcomp-pres" t))
                  (analysis-file (expand-file-name "par-007.org" tmpdir)))
             (with-temp-file analysis-file
               (insert "#+TITLE: Paragraph 7\n#+TIBETAN_HASH: x\n\n* Tibetan Text\nFoo།\n\n* My Notes\n\n\n* Working Translation\n\n\n* Translation Comparison\nUSER-EDITED-MATRIX-CONTENT\n\n* Auto-Analysis\n** Wylie\nfoo /\n\n* Footnotes\n"))
             (tibetan-analysis-regenerate-auto
              analysis-file "Foo།" "** Wylie\nfoo REGEN\n")
             (setq result (with-temp-buffer
                            (insert-file-contents analysis-file)
                            (buffer-string))))
    :when result
    :then ((tibetan-bdd-assert-contains result "USER-EDITED-MATRIX-CONTENT"
            "Comparison section survives regenerate-auto")
           (tibetan-bdd-assert-contains result "foo REGEN"
            "Auto-Analysis IS regenerated"))
    :example "Translation Comparison preservation invariant"
    :tags (:translation-comparison :preservation :critical))

  (spec "C-c u T entry point exists and is interactive"
    :given (setq fn 'tibetan-translation-comparison-refresh)
    :when (and (fboundp fn) (commandp fn))
    :then ((should result))
    :example "tibetan-translation-comparison-refresh defined"
    :tags (:translation-comparison :entry-point)))

(provide 'paragraph-analysis-spec)
;;; paragraph-analysis-spec.el ends here
