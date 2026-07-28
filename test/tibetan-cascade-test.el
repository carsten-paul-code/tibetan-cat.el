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

(provide 'tibetan-cascade-test)
;;; tibetan-cascade-test.el ends here
