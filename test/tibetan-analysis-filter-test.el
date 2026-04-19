;;; tibetan-analysis-filter-test.el --- Tests for input-text filtering -*- lexical-binding: t -*-

;;; Commentary:
;; Regression tests for `tibetan-analysis--filter-to-tibetan-lines',
;; the sanitiser that runs before Wylie conversion and parser
;; tokenisation in `tibetan-analysis-generate-content'.
;;
;; Motivating case: real-world `* Tibetan Text' sections interleave
;; parenthetical English descriptions, `#' comments, and Tibetan
;; body.  Without filtering, the English text bled into every
;; downstream section — a ~30-space leading indent on the Wylie
;; output and bogus Interlinear Gloss entries like `[number 100]'
;; and `[set]' (English words like \"The\" and \"on\" accidentally
;; matched Wylie glossary keys).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tibetan-analysis-persist)

;; ----------------------------------------------------------------------------
;; Basic filter invariants
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-filter-drops-english-description ()
  "A parenthetical English description line must be dropped."
  (let ((input "(Homage / author's dedication verses)
གཞོན་ནུར་གྱུར་པ་ལ་ཕྱག་འཚལ་ལོ༎"))
    (should-not (string-match-p "Homage"
                                (tibetan-analysis--filter-to-tibetan-lines
                                 input)))
    (should (string-match-p "གཞོན"
                            (tibetan-analysis--filter-to-tibetan-lines
                             input)))))

(ert-deftest tibetan-analysis-filter-drops-hash-comments ()
  "Org comment lines starting with `#' must be dropped."
  (let ((input "# This is an editorial note
# Continuation of the note
གཞོན་ནུར་གྱུར་པ་"))
    (let ((out (tibetan-analysis--filter-to-tibetan-lines input)))
      (should-not (string-match-p "editorial" out))
      (should-not (string-match-p "Continuation" out))
      (should (string-match-p "གཞོན" out)))))

(ert-deftest tibetan-analysis-filter-drops-blank-lines ()
  "Blank separators between Tibetan lines must be dropped."
  (let* ((input "གཞོན་ནུར་

རྒྱལ་དང་")
         (out (tibetan-analysis--filter-to-tibetan-lines input)))
    ;; No empty segment between the two joined lines.
    (should-not (string-match-p "\n\n" out))))

(ert-deftest tibetan-analysis-filter-keeps-mixed-lines ()
  "A line that contains BOTH Tibetan and Latin characters is kept."
  (let ((input "(12a2) གཞོན་ནུར་"))
    (should (string-match-p "གཞོན"
                            (tibetan-analysis--filter-to-tibetan-lines
                             input)))
    (should (string-match-p "12a2"
                            (tibetan-analysis--filter-to-tibetan-lines
                             input)))))

(ert-deftest tibetan-analysis-filter-joins-lines-with-tsheg ()
  "Adjacent Tibetan lines are joined with a tsheg so the parser splits
them cleanly instead of treating `XY\\nZW' as a single token."
  (let* ((input "གཞོན་ནུར་ལོ༎
རྒྱལ་དང་")
         (out (tibetan-analysis--filter-to-tibetan-lines input)))
    ;; No literal newline survives; a tsheg sits between the two halves.
    (should-not (string-match-p "\n" out))
    (should (string-match-p "ལོ༎་རྒྱལ" out))))

(ert-deftest tibetan-analysis-filter-handles-nil-and-empty ()
  (should (null (tibetan-analysis--filter-to-tibetan-lines nil)))
  (should (equal "" (tibetan-analysis--filter-to-tibetan-lines ""))))

;; ----------------------------------------------------------------------------
;; End-to-end: the seg-003 scenario
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-filter-no-english-bleed-through-into-wylie ()
  "Filtered text, when converted to Wylie, must not start with leading
whitespace (the seg-003 \"30-space indent\" regression)."
  (skip-unless (fboundp 'tibetan-to-wylie-fixed))
  (let* ((input "(Homage / author's dedication verses)

# OCR notes elided

གཞོན་ནུར་གྱུར་པ་ལ་ཕྱག་འཚལ་ལོ༎
རྒྱལ་དང་དེ་སྲས་")
         (cleaned (tibetan-analysis--filter-to-tibetan-lines input))
         (wylie (tibetan-to-wylie-fixed cleaned)))
    ;; No leading whitespace.
    (should (equal wylie (string-trim-left wylie)))
    ;; Actual words present.
    (should (string-match-p "gzhon" wylie))
    (should (string-match-p "rgyal" wylie))
    ;; Proper space between shad and the next word (not `lo//rgyal').
    (should (string-match-p "// rgyal" wylie))))

(ert-deftest tibetan-analysis-filter-no-english-bleed-through-into-vocab ()
  "Filtered text, when fed to the extractor, must not produce vocab
pairs whose KEY is an English word.  Previously `The', `on',
`author's' etc. all appeared as vocab-pair keys."
  (skip-unless (fboundp 'tibetan-extract-vocabulary))
  (let* ((input "(Homage / author's dedication verses)

# The opening salutation. OCR on the illuminated folio was fragmentary.

གཞོན་ནུར་གྱུར་པ་ལ་ཕྱག་འཚལ་ལོ༎")
         (cleaned (tibetan-analysis--filter-to-tibetan-lines input))
         (pairs (tibetan-extract-vocabulary cleaned))
         (keys (mapcar #'car pairs))
         (tibetan-char-re "[ༀ-࿿]"))
    (dolist (k keys)
      (should (string-match-p tibetan-char-re k)))))

(provide 'tibetan-analysis-filter-test)
;;; tibetan-analysis-filter-test.el ends here
