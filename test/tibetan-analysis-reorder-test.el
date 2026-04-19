;;; tibetan-analysis-reorder-test.el --- Tests for auto-content reorder -*- lexical-binding: t -*-

;;; Commentary:
;; Exercises `tibetan-analysis--reorder-auto-content' and its two
;; helpers.  The reorder is a post-pass on the content string emitted
;; by `tibetan-analysis-generate-content', so all the tests feed it
;; synthetic level-2 section blocks and check the reassembled output.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tibetan-analysis-persist)

;; Small helper — build a synthetic auto-content blob from a list of
;; (HEADING BODY) pairs, in the given order.
(defun tibetan-analysis-reorder-test--build (pairs)
  (mapconcat (lambda (p) (concat (car p) "\n" (cadr p)))
             pairs ""))

;; Extract just the level-2 heading names from a content blob, in
;; order.  Used to assert "the reorder put X before Y".
(defun tibetan-analysis-reorder-test--headings (content)
  (let ((result '())
        (idx 0))
    (while (string-match "^\\*\\* .*$" content idx)
      (push (match-string 0 content) result)
      (setq idx (match-end 0)))
    (nreverse result)))

;; ----------------------------------------------------------------------------
;; Splitter
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-reorder-splitter-returns-headings-in-order ()
  (let* ((content (tibetan-analysis-reorder-test--build
                   '(("** Foo" "body 1\n")
                     ("** Bar" "body 2\n")
                     ("** Baz" "body 3\n"))))
         (split (tibetan-analysis--split-level2-sections content))
         (headings (mapcar #'car (cdr split))))
    (should (equal headings '("** Foo" "** Bar" "** Baz")))))

(ert-deftest tibetan-analysis-reorder-splitter-body-excludes-next-heading ()
  (let* ((content "** A\nalpha\nalpha2\n** B\nbeta\n")
         (split (tibetan-analysis--split-level2-sections content))
         (sections (cdr split)))
    (should (equal (cdr (assoc "** A" sections)) "alpha\nalpha2\n"))
    (should (equal (cdr (assoc "** B" sections)) "beta\n"))))

;; ----------------------------------------------------------------------------
;; Claude Grammar promotion
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-reorder-promotes-claude-grammar ()
  "A `*** Claude Grammar' subsection inside `** Provided Translations'
must be promoted to a top-level `** Claude Grammar' entry, and its
body must be removed from the Provided Translations body."
  (let* ((content (concat
                   "** Wylie Transliteration\nwylie body\n\n"
                   "** Provided Translations\n"
                   "*** DharmaMitra\ndm body\n\n"
                   "*** Claude Grammar\nExplanation of the grammar.\n"
                   "Multi-line body.\n\n"
                   "*** CAT Gloss\ncat body\n"))
         (reordered (tibetan-analysis--reorder-auto-content content))
         (headings (tibetan-analysis-reorder-test--headings reordered)))
    (should (member "** Claude Grammar" headings))
    ;; Body promoted verbatim (whitespace trimmed).
    (should (string-match-p
             "\\*\\* Claude Grammar\n\\(?:Explanation of the grammar\\.\\)"
             reordered))
    ;; Original *** Claude Grammar inside Provided Translations is gone.
    (let* ((split (tibetan-analysis--split-level2-sections reordered))
           (pt (cdr (assoc "** Provided Translations" (cdr split)))))
      (should pt)
      (should-not (string-match-p "\\*\\*\\* Claude Grammar" pt)))))

;; ----------------------------------------------------------------------------
;; Priority ordering
;; ----------------------------------------------------------------------------

(ert-deftest tibetan-analysis-reorder-priority-order-applied ()
  "The six priority sections must appear in the configured order
first, before any other sections."
  (let* ((content (concat
                   "** Word / Particle List\nwpl\n\n"
                   "** Verb Classification (Hill 2010)\nverbs\n\n"
                   "** Particle Map\npmap\n\n"
                   "** Wylie Transliteration\nwylie\n\n"
                   "** Sentence Structure\nsent\n\n"
                   "** Claude Translation\nct\n\n"
                   "** Interlinear Gloss\nig\n\n"
                   "** Grammatical Markers\ngm\n\n"
                   "** Detailed Dictionary\ndd\n\n"))
         (reordered (tibetan-analysis--reorder-auto-content content))
         (headings (tibetan-analysis-reorder-test--headings reordered))
         (expected-prefix '("** Wylie Transliteration"
                            "** Particle Map"
                            "** Interlinear Gloss"
                            "** Verb Classification (Hill 2010)"
                            "** Claude Translation")))
    (should (equal (cl-subseq headings 0 (length expected-prefix))
                   expected-prefix))
    ;; Every unlisted section still appears somewhere in the output.
    (dolist (keep '("** Word / Particle List"
                    "** Sentence Structure"
                    "** Grammatical Markers"
                    "** Detailed Dictionary"))
      (should (member keep headings)))))

(ert-deftest tibetan-analysis-reorder-preserves-unlisted-section-order ()
  "Sections NOT in the priority list retain their original relative
order after reorder."
  (let* ((content (concat
                   "** Zeta\n1\n\n"
                   "** Wylie Transliteration\nw\n\n"
                   "** Alpha\n2\n\n"
                   "** Particle Map\np\n\n"
                   "** Beta\n3\n\n"))
         (reordered (tibetan-analysis--reorder-auto-content content))
         (headings (tibetan-analysis-reorder-test--headings reordered))
         (tail (cl-subseq headings 2)))
    ;; Priority first: Wylie, then Particle Map.
    (should (equal (cl-subseq headings 0 2)
                   '("** Wylie Transliteration" "** Particle Map")))
    ;; Non-priority preserve their original order (Zeta before Alpha
    ;; before Beta).
    (should (equal tail '("** Zeta" "** Alpha" "** Beta")))))

(ert-deftest tibetan-analysis-reorder-missing-priority-section-is-ok ()
  "The reorder must not require every priority section to be present —
sections that don't exist in the input are simply skipped in the
output, and the existing ones still appear in priority order."
  (let* ((content (concat
                   "** Wylie Transliteration\nw\n\n"
                   "** Word / Particle List\nwpl\n\n"
                   "** Claude Translation\nct\n\n"))
         (reordered (tibetan-analysis--reorder-auto-content content))
         (headings (tibetan-analysis-reorder-test--headings reordered)))
    (should (equal headings
                   '("** Wylie Transliteration"
                     "** Claude Translation"
                     "** Word / Particle List")))))

(ert-deftest tibetan-analysis-reorder-empty-input-returns-empty ()
  (should (equal "" (tibetan-analysis--reorder-auto-content ""))))

(provide 'tibetan-analysis-reorder-test)
;;; tibetan-analysis-reorder-test.el ends here
