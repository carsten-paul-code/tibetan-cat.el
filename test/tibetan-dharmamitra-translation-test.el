;;; tibetan-dharmamitra-translation-test.el --- Tests for DM as a translator -*- lexical-binding: t -*-

;;; Commentary:
;;
;; Phase A of the multi-translator-parallel-reading feature
;; (2026-04-30):  DharmaMitra alongside Claude as a translation
;; engine in the per-segment analysis files.  Each segment gets
;; a `** DharmaMitra Translation (Tibetan)' section (and, in
;; parallel-Sanskrit mode, a `** DharmaMitra Translation
;; (Sanskrit)' section) at level 2 — sibling of `** Claude
;; Translation (Tibetan)' / `** Claude Translation (Sanskrit)'.
;;
;; Tests stub `tibetan-dharmamitra-api-chat-translate' so no
;; network calls happen.  The writer is exercised against real
;; temp org files.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../persist" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-dharmamitra-api)
(require 'tibetan-dharmamitra-translation)

;; ============================================================================
;; Fixture
;; ============================================================================

(defmacro tibetan-dm-trans-test--with-analysis-file (initial-content &rest body)
  "Write INITIAL-CONTENT to a temp seg-005.org and bind ANALYSIS-FILE."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "tibetan-dm-trans-" t))
          (analysis-file (expand-file-name "seg-005.org" dir)))
     (unwind-protect
         (progn
           (with-temp-file analysis-file (insert ,initial-content))
           ,@body)
       (delete-directory dir t))))

(defun tibetan-dm-trans-test--baseline-analysis ()
  "Return baseline analysis-file content for tests."
  (concat "#+TITLE: Segment 5 Analysis\n\n"
          "* Tibetan Text\n"
          "བདག་གིས་ལས་བྱས།\n\n"
          "* Auto-Analysis\n"
          ":PROPERTIES:\n:GENERATED: t\n:END:\n\n"
          "** Wylie Transliteration\nbdag gis las byas /\n\n"
          "** Claude Translation (Tibetan)\n[Requesting...]\n\n"
          "* My Notes\n\n* Working Translation\n\n* Footnotes\n"))

;; ============================================================================
;; Writer — `--write-section'
;; ============================================================================

(ert-deftest tibetan-dm-trans-write-section-creates-tibetan-section ()
  "Writer adds `** DharmaMitra Translation (Tibetan)' to the
analysis file when none exists yet."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (let ((ok (tibetan-dharmamitra-translation--write-section
               analysis-file "By me, the work was done." "Tibetan")))
      (should ok)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p
                   "^\\* DharmaMitra Translation (Tibetan)$" s))
          (should (string-match-p "By me, the work was done\\." s)))))))

(ert-deftest tibetan-dm-trans-write-section-creates-sanskrit-section ()
  "Writer parameterises the heading on SOURCE-LANG: `Sanskrit'
yields `** DharmaMitra Translation (Sanskrit)'."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (tibetan-dharmamitra-translation--write-section
     analysis-file "In this context, a Bodhisattva ..." "Sanskrit")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p
                 "^\\* DharmaMitra Translation (Sanskrit)$" s))
        (should (string-match-p "In this context, a Bodhisattva" s))))))

(ert-deftest tibetan-dm-trans-write-section-replaces-existing-section ()
  "Re-writing replaces the body in place; old content is gone."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (concat (tibetan-dm-trans-test--baseline-analysis)
              "\n* DharmaMitra Translation (Tibetan)\nOLD STALE\n")
    (tibetan-dharmamitra-translation--write-section
     analysis-file "FRESH NEW TRANSLATION" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "FRESH NEW TRANSLATION" s))
        (should-not (string-match-p "OLD STALE" s))
        ;; My Notes etc still present.
        (should (string-match-p "* My Notes" s))))))

(ert-deftest tibetan-dm-trans-write-section-preserves-other-content ()
  "All other top-level sections + Auto-Analysis content are
untouched by the writer."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (concat "#+TITLE: T\n\n"
              "* Tibetan Text\nTIBETAN_BODY\n\n"
              "* Auto-Analysis\nAUTO_BODY\n** Wylie\nWYLIE_BODY\n\n"
              "* My Notes\nNOTES_BODY\n\n"
              "* Working Translation\nWT_BODY\n\n"
              "* Footnotes\nFOOTNOTES_BODY\n")
    (tibetan-dharmamitra-translation--write-section
     analysis-file "DM translation" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p "TIBETAN_BODY" s))
        (should (string-match-p "AUTO_BODY" s))
        (should (string-match-p "WYLIE_BODY" s))
        (should (string-match-p "NOTES_BODY" s))
        (should (string-match-p "WT_BODY" s))
        (should (string-match-p "FOOTNOTES_BODY" s))
        ;; New section also added.
        (should (string-match-p "DM translation" s))))))

(ert-deftest tibetan-dm-trans-write-section-nil-when-file-missing ()
  "Non-existent ANALYSIS-FILE returns nil without crashing."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (should-not (tibetan-dharmamitra-translation--write-section
               "/nonexistent/path/seg-005.org"
               "translation" "Tibetan")))

(ert-deftest tibetan-dm-trans-write-section-property-drawer-stamps-metadata ()
  "Section's property drawer carries `:DM_BACKEND:' /
`:LAST_TRANSLATED:' for provenance + freshness tracking."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation--write-section))
  (tibetan-dm-trans-test--with-analysis-file
      (tibetan-dm-trans-test--baseline-analysis)
    (tibetan-dharmamitra-translation--write-section
     analysis-file "translation" "Tibetan")
    (with-temp-buffer
      (insert-file-contents analysis-file)
      (let ((s (buffer-string)))
        (should (string-match-p ":LAST_TRANSLATED:" s))))))

;; ============================================================================
;; Fire function — orchestrates API call + write
;; ============================================================================

(ert-deftest tibetan-dm-trans-fire-tibetan-calls-chat-translate ()
  "`tibetan-dharmamitra-translation-fire-tibetan' calls
`tibetan-dharmamitra-api-chat-translate' once with the segment's
Tibetan text."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (let (translate-calls)
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (text &rest _)
                 (push text translate-calls)
                 "stub English translation")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-tibetan
         "བདག་གིས་ལས་བྱས།" analysis-file)
        (should (= (length translate-calls) 1))
        (should (equal (car translate-calls) "བདག་གིས་ལས་བྱས།"))))))

(ert-deftest tibetan-dm-trans-fire-tibetan-writes-result-to-section ()
  "After firing, the analysis file contains the translation under
`** DharmaMitra Translation (Tibetan)'."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
             (lambda (&rest _) "By me, the work was done.")))
    (tibetan-dm-trans-test--with-analysis-file
        (tibetan-dm-trans-test--baseline-analysis)
      (tibetan-dharmamitra-translation-fire-tibetan
       "བདག་གིས་ལས་བྱས།" analysis-file)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (let ((s (buffer-string)))
          (should (string-match-p
                   "^\\* DharmaMitra Translation (Tibetan)$" s))
          (should (string-match-p "By me, the work was done\\." s)))))))

(ert-deftest tibetan-dm-trans-fire-tibetan-skips-empty-text ()
  "Empty / nil Tibetan text → no API call, no write.  REGRESSION
GUARD against silent empty-translation writes."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (let ((translate-calls 0))
    (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
               (lambda (&rest _) (cl-incf translate-calls) "x")))
      (tibetan-dm-trans-test--with-analysis-file
          (tibetan-dm-trans-test--baseline-analysis)
        (tibetan-dharmamitra-translation-fire-tibetan "" analysis-file)
        (tibetan-dharmamitra-translation-fire-tibetan nil analysis-file)
        (should (= translate-calls 0))))))

(ert-deftest tibetan-dm-trans-fire-tibetan-skips-when-translation-nil ()
  "When chat-translate returns nil (HTTP error / empty response),
the writer is NOT called — analysis file unchanged.  Avoids
overwriting a previous good translation with a failed one."
  (skip-unless (fboundp 'tibetan-dharmamitra-translation-fire-tibetan))
  (cl-letf (((symbol-function 'tibetan-dharmamitra-api-chat-translate)
             (lambda (&rest _) nil)))
    (tibetan-dm-trans-test--with-analysis-file
        (concat (tibetan-dm-trans-test--baseline-analysis)
                "\n* DharmaMitra Translation (Tibetan)\nPRIOR GOOD TRANSLATION\n")
      (tibetan-dharmamitra-translation-fire-tibetan
       "བདག་གིས་ལས་བྱས།" analysis-file)
      (with-temp-buffer
        (insert-file-contents analysis-file)
        (should (string-match-p "PRIOR GOOD TRANSLATION" (buffer-string)))))))

(provide 'tibetan-dharmamitra-translation-test)
;;; tibetan-dharmamitra-translation-test.el ends here
