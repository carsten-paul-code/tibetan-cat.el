;;; tibetan-analysis-combine-test.el --- Tests for combine-document -*- lexical-binding: t -*-

;;; Commentary:
;; Exercises `tibetan-analysis-combine-document' and its helpers in
;; `persist/tibetan-analysis-combine.el'.  Uses temporary analysis
;; folders so no real seg-NNN.org files are touched.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tibetan-analysis-combine)

(defmacro tibetan-combine-test--with-temp-folder (dirvar &rest body)
  "Bind DIRVAR to a fresh temp dir; cleanup after BODY."
  (declare (indent 1))
  `(let ((,dirvar (make-temp-file "tibetan-combine-" t)))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p ,dirvar)
         (delete-directory ,dirvar t)))))

(defun tibetan-combine-test--write-seg (folder seg-id tibetan-body auto-sections)
  "Create FOLDER/seg-SEG-ID.org with TIBETAN-BODY under `* Tibetan
Text' and AUTO-SECTIONS (a list of (HEADING BODY) pairs) under
`* Auto-Analysis'."
  (let ((path (expand-file-name (format "seg-%03d.org" seg-id) folder)))
    (with-temp-file path
      (insert (format "#+TITLE: Segment %d Analysis\n" seg-id))
      (insert "* Tibetan Text\n")
      (insert tibetan-body)
      (insert "\n\n")
      (insert "* Auto-Analysis\n")
      (dolist (pair auto-sections)
        (insert (car pair) "\n")
        (insert (cadr pair) "\n\n"))
      (insert "* My Notes\n\n")
      (insert "* Working Translation\n\n")
      (insert "* Footnotes\n"))
    path))

;; ----------------------------------------------------------------------------
;; Snippet truncation
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-combine-snippet-short-text-kept-verbatim ()
  (should (equal (tibetan-analysis-combine--snippet "གཞོན་ནུར་")
                 "གཞོན་ནུར་")))

(ert-deftest tibetan-combine-snippet-drops-non-tibetan-lines ()
  "Non-Tibetan lines (English descriptions, comments) disappear from
the heading snippet."
  (let ((result (tibetan-analysis-combine--snippet
                 "(Homage)
# comment
གཞོན་ནུར་")))
    (should-not (string-match-p "Homage" result))
    (should-not (string-match-p "comment" result))
    (should (string-match-p "གཞོན" result))))

(ert-deftest tibetan-combine-snippet-truncates-with-ellipsis ()
  "Long Tibetan input is truncated to the configured max length."
  (let* ((long (make-string (+ tibetan-analysis-combine--snippet-max 20)
                            ?ག))
         (out (tibetan-analysis-combine--snippet long)))
    (should (> (length long) (length out)))
    (should (string-suffix-p "…" out))))

;; ----------------------------------------------------------------------------
;; Entry splitters and dedup
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-combine-split-detailed-entries-diamond-delimited ()
  (let* ((body "◆ ngo mtshar [ngo mtshar]
  [01-Hopkins2015]
    amazing

◆ bskal pa [bskal pa]
  [01-Hopkins2015]
    aeon
")
         (entries (tibetan-analysis-combine--split-detailed-entries body)))
    (should (= 2 (length entries)))
    (should (string-prefix-p "◆ ngo mtshar" (nth 0 entries)))
    (should (string-prefix-p "◆ bskal pa" (nth 1 entries)))))

(ert-deftest tibetan-combine-split-grammatical-entries-bulleted ()
  "Each `- ' bullet becomes its own entry; continuation lines (indented
or unlabelled) attach to the bullet they follow."
  (let* ((body "- དེ [de] in «དེ» → CONVERBIAL: COORDINATIVE CONVERB
  continuation line
- ལ [la] in «ལ» → DATIVE (DAT)
- དང [dang] in «དང» → COMITATIVE (COM)")
         (entries (tibetan-analysis-combine--split-grammatical-entries body)))
    (should (= 3 (length entries)))
    (should (string-prefix-p "- དེ" (nth 0 entries)))
    (should (string-match-p "continuation line" (nth 0 entries)))
    (should (string-prefix-p "- ལ" (nth 1 entries)))
    (should (string-prefix-p "- དང" (nth 2 entries)))))

(ert-deftest tibetan-combine-dedup-merges-identical-entries ()
  "An identical dictionary entry appearing in two segments becomes a
single output entry whose :segments list names both."
  (let* ((body "◆ bskal pa [bskal pa]
  [01-Hopkins2015]
    aeon")
         (per-seg (list (cons 3 body) (cons 7 body)))
         (result (tibetan-analysis-combine--dedup-entries
                  per-seg
                  #'tibetan-analysis-combine--split-detailed-entries)))
    (should (= 1 (length result)))
    (should (equal (plist-get (car result) :segments) '(3 7)))))

(ert-deftest tibetan-combine-dedup-keeps-distinct-entries ()
  (let* ((per-seg (list
                   (cons 3 "◆ ngo mtshar [ngo mtshar]\n  amazing")
                   (cons 5 "◆ bskal pa [bskal pa]\n  aeon")))
         (result (tibetan-analysis-combine--dedup-entries
                  per-seg
                  #'tibetan-analysis-combine--split-detailed-entries)))
    (should (= 2 (length result)))))

;; ----------------------------------------------------------------------------
;; End-to-end: build a combined.org from a synthetic folder
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-combine-end-to-end-happy-path ()
  "Given two synthetic seg files, the combine command writes a
`combined.org' containing both segment blocks and the appendix."
  (tibetan-combine-test--with-temp-folder folder
    (tibetan-combine-test--write-seg
     folder 1 "གཞོན་ནུར་གྱུར་པ་"
     '(("** Wylie Transliteration" "gzhon nur gyur pa")
       ("** Particle Map" "[map 1]")
       ("** Interlinear Gloss" "gzhon nur gyur pa [is young]")
       ("** Verb Classification (Hill 2010)" "[verbs 1]")
       ("** Claude Translation" "Having become a youth")
       ("** Claude Grammar" "Narrative converb")
       ("** Grammatical Markers" "- ལ [la] in «ལ» → DATIVE (DAT)")
       ("** Detailed Dictionary"
        "◆ gzhon nur gyur pa [gzhon nur gyur pa]\n  [01-Hopkins2015]\n    became a youth")))
    (tibetan-combine-test--write-seg
     folder 2 "རྒྱལ་དང་དེ་སྲས་"
     '(("** Wylie Transliteration" "rgyal dang de sras")
       ("** Particle Map" "[map 2]")
       ("** Interlinear Gloss" "rgyal [king] dang [and] de sras [his son]")
       ("** Verb Classification (Hill 2010)" "[no verbs]")
       ("** Claude Translation" "The victor and his son")
       ("** Claude Grammar" "Coordinated NP")
       ("** Grammatical Markers" "- ལ [la] in «ལ» → DATIVE (DAT)")
       ("** Detailed Dictionary"
        "◆ rgyal [rgyal]\n  [01-Hopkins2015]\n    king")))
    (let ((buf (tibetan-analysis-combine-document folder)))
      (unwind-protect
          (with-current-buffer buf
            (let ((text (buffer-string)))
              ;; Per-segment blocks in order.
              (should (string-match-p "^\\* Segment 1" text))
              (should (string-match-p "^\\* Segment 2" text))
              (should (< (string-match "Segment 1" text)
                         (string-match "Segment 2" text)))
              ;; The 7 priority headings present in each segment block.
              (dolist (h '("\\*\\* Tibetan Text"
                           "\\*\\* Wylie Transliteration"
                           "\\*\\* Particle Map"
                           "\\*\\* Interlinear Gloss"
                           "\\*\\* Verb Classification"
                           "\\*\\* Claude Translation"
                           "\\*\\* Claude Grammar"))
                (should (string-match-p h text)))
              ;; Both appendices present.
              (should (string-match-p "Appendix A — Grammatical Markers" text))
              (should (string-match-p "Appendix B — Detailed Dictionary" text))
              ;; Deduped entry with back-references.
              (should (string-match-p "(segments: 1, 2)" text))
              ;; Distinct dictionary entries both listed.
              (should (string-match-p "gzhon nur gyur pa" text))
              (should (string-match-p "◆ rgyal" text))))
        (kill-buffer buf)))))

(ert-deftest tibetan-combine-empty-folder-errors ()
  "Calling the command on a folder with no seg files signals
a user-error rather than silently writing an empty file."
  (tibetan-combine-test--with-temp-folder folder
    (should-error (tibetan-analysis-combine-document folder)
                  :type 'user-error)))

(ert-deftest tibetan-combine-skips-segments-with-no-tibetan ()
  "A segment whose `* Tibetan Text' contains only non-Tibetan lines
\(e.g. a `〔seg:1〕' that captured the source-file preamble) must be
dropped from the combined output — no empty `* Segment N' heading,
no run of `[Not available]' placeholders."
  (tibetan-combine-test--with-temp-folder folder
    ;; seg-001: preamble only — no Tibetan characters.
    (tibetan-combine-test--write-seg
     folder 1
     "#+TITLE: A source file\n#+TIBETAN_CLAUDE_CONTEXT: some context\n"
     '(("** Wylie Transliteration" "")
       ("** Claude Translation"    "")
       ("** Claude Grammar"        "")))
    ;; seg-002: a real passage.
    (tibetan-combine-test--write-seg
     folder 2 "རྒྱལ་དང་དེ་སྲས་"
     '(("** Wylie Transliteration" "rgyal dang de sras")
       ("** Particle Map" "[map]")
       ("** Interlinear Gloss" "rgyal [king]")
       ("** Verb Classification (Hill 2010)" "[verbs]")
       ("** Claude Translation" "The victor")
       ("** Claude Grammar" "NP coord")))
    (let ((buf (tibetan-analysis-combine-document folder)))
      (unwind-protect
          (with-current-buffer buf
            (let ((text (buffer-string)))
              ;; Segment 1 dropped entirely.
              (should-not (string-match-p "^\\* Segment 1" text))
              ;; Segment 2 retained.
              (should (string-match-p "^\\* Segment 2" text))
              (should (string-match-p "The victor" text))
              ;; Export-level TOC suppressed.
              (should (string-match-p "^#\\+OPTIONS:.*toc:nil" text))))
        (kill-buffer buf)))))

(provide 'tibetan-analysis-combine-test)
;;; tibetan-analysis-combine-test.el ends here
