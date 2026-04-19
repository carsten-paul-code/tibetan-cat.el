;;; tibetan-interlinear-test.el --- Tests for tibetan-interlinear.el -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for the interlinear gloss and particle overview module.
;; Tests cover:
;;   1. Word/particle splitting
;;   2. Portfolio parser
;;   3. Interlinear gloss generation
;;   4. Particle Overview generation

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-interlinear)

;; ============================================================================
;; WORD/PARTICLE SPLITTING
;; ============================================================================

(ert-deftest tibetan-interlinear-split-concessive ()
  "Split verb+kyang into stem and concessive particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "སྐྱེས་གྱུར་ཀྱང" "CONCESSIVE PARTICLE")))
    (should (equal (car result) "སྐྱེས་གྱུར"))
    (should (equal (cadr result) "ཀྱང"))
    (should (equal (cddr result) "CONC"))))

(ert-deftest tibetan-interlinear-split-genitive ()
  "Split noun+kyi into stem and genitive particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "བློ་རྒོད་ཀྱི" "GENITIVE (GEN)")))
    (should (equal (car result) "བློ་རྒོད"))
    (should (equal (cadr result) "ཀྱི"))
    (should (equal (cddr result) "GEN"))))

(ert-deftest tibetan-interlinear-split-ergative ()
  "Split noun+kyis into stem and ergative particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "རྡོས་ཀྱིས" "ERGATIVE/INSTRUMENTAL (ERG/INST)")))
    (should (equal (car result) "རྡོས"))
    (should (equal (cadr result) "ཀྱིས"))
    (should (equal (cddr result) "ERG"))))

(ert-deftest tibetan-interlinear-split-ablative-converb ()
  "Split verb+nas into stem and ablative converb particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "ཤེས་ནས" "CONVERBIAL: ABLATIVE CONVERB")))
    (should (equal (car result) "ཤེས"))
    (should (equal (cadr result) "ནས"))
    (should (string-match-p "nas" (cddr result)))))

(ert-deftest tibetan-interlinear-split-no-particle ()
  "Pure lexical word returns whole word as stem, nil particle."
  (let ((result (tibetan-interlinear--split-word-particle
                 "འཁོར་བ" nil)))
    (should (equal (car result) "འཁོར་བ"))
    (should (null (cdr result)))))

(ert-deftest tibetan-interlinear-split-noun-tag-no-split ()
  "Word tagged as Noun should not be split."
  (let ((result (tibetan-interlinear--split-word-particle
                 "སྡུག་བསྔལ" "Noun")))
    (should (equal (car result) "སྡུག་བསྔལ"))
    (should (null (cdr result)))))

(ert-deftest tibetan-interlinear-split-verb-tag-no-split ()
  "Word tagged as Verb should not be split."
  (let ((result (tibetan-interlinear--split-word-particle
                 "འདྲ" "Verb")))
    (should (equal (car result) "འདྲ"))
    (should (null (cdr result)))))

(ert-deftest tibetan-interlinear-split-terminative ()
  "Split terminative particle du."
  (let ((result (tibetan-interlinear--split-word-particle
                 "གནས་སུ" "TERMINATIVE (ALL)")))
    (should (equal (car result) "གནས"))
    (should (equal (cadr result) "སུ"))
    (should (equal (cddr result) "TERM"))))

;; ============================================================================
;; PORTFOLIO PARSER
;; ============================================================================

(ert-deftest tibetan-interlinear-portfolio-parse-basic ()
  "Parse a minimal Portfolio org file."
  (let ((test-file (make-temp-file "portfolio-test" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Part 1: Case Suffixes\n\n")
            (insert "** 1.1 Genitive\n\n")
            (insert "The genitive suffixes establish a dependency relation.\n\n")
            (insert "*** 1.1.1 Genitive Attribute\n\n")
            (insert "Marks a nominal attribute.\n\n")
            (insert "- example 1\n\n")
            (insert "*** 1.1.2 Genitive with Postpositions\n\n")
            (insert "Connects a noun to a postposition.\n\n")
            (insert "** 1.3 Ergative\n\n")
            (insert "The ergative marks the agent of a transitive verb.\n\n")
            (insert "*** 1.3.1 Subject (Agent)\n\n")
            (insert "Marks the volitional agent.\n"))
          (let ((result (tibetan-interlinear--parse-portfolio test-file)))
            ;; Should have two entries
            (should (= (length result) 2))
            ;; First: genitive
            (let ((gen (cdr (assoc "genitive" result))))
              (should gen)
              (should (equal (plist-get gen :section) "1.1"))
              (should (string-match-p "Genitive" (plist-get gen :title)))
              (should (string-match-p "dependency" (plist-get gen :intro)))
              ;; Should have 2 sub-functions
              (should (= (length (plist-get gen :functions)) 2)))
            ;; Second: ergative
            (let ((erg (cdr (assoc "ergative" result))))
              (should erg)
              (should (equal (plist-get erg :section) "1.3"))
              (should (= (length (plist-get erg :functions)) 1)))))
      (delete-file test-file))))

(ert-deftest tibetan-interlinear-portfolio-parse-converbs ()
  "Parse converb sections from Portfolio."
  (let ((test-file (make-temp-file "portfolio-conv" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "* Part 2: Converb Constructions\n\n")
            (insert "** 2.1 Verb Stem + /kyang/\n\n")
            (insert "The concessive converb expresses although.\n\n")
            (insert "** 2.3 Verb Stem + /cing/\n\n")
            (insert "The coordinative converb connects simultaneous events.\n"))
          (let ((result (tibetan-interlinear--parse-portfolio test-file)))
            (should (= (length result) 2))
            (should (assoc "converb-kyang" result))
            (should (assoc "converb-cing" result))
            (should (string-match-p "concessive"
                                    (plist-get (cdr (assoc "converb-kyang" result))
                                               :intro)))))
      (delete-file test-file))))

(ert-deftest tibetan-interlinear-portfolio-nil-file ()
  "Nil or missing file returns nil."
  (should (null (tibetan-interlinear--parse-portfolio nil)))
  (should (null (tibetan-interlinear--parse-portfolio "/nonexistent/file.org"))))

;; ============================================================================
;; PORTFOLIO KEY MAPPING
;; ============================================================================

(ert-deftest tibetan-interlinear-portfolio-key-mapping ()
  "Bialek type labels map to correct portfolio keys."
  (should (equal (tibetan-interlinear--portfolio-key "GENITIVE (GEN)")
                 "genitive"))
  (should (equal (tibetan-interlinear--portfolio-key "ERGATIVE/INSTRUMENTAL (ERG/INST)")
                 "ergative"))
  (should (equal (tibetan-interlinear--portfolio-key "TERMINATIVE (ALL)")
                 "terminative"))
  (should (equal (tibetan-interlinear--portfolio-key "CONCESSIVE PARTICLE")
                 "converb-kyang"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: ABLATIVE CONVERB")
                 "converb-nas"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: COORDINATIVE CONVERB")
                 "converb-ste"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: SIMULTANEOUS CONVERB")
                 "converb-cing"))
  (should (equal (tibetan-interlinear--portfolio-key "CONVERBIAL: CAUSAL CONVERB")
                 "converb-pas"))
  (should (equal (tibetan-interlinear--portfolio-key "DATIVE (DAT)")
                 "dative"))
  (should (equal (tibetan-interlinear--portfolio-key "LOCATIVE (LOC)")
                 "locative"))
  (should (equal (tibetan-interlinear--portfolio-key "TOPIC (TOP)")
                 "topic"))
  (should (equal (tibetan-interlinear--portfolio-key "COMITATIVE (COM)")
                 "comitative")))

;; ============================================================================
;; GLOSS TRUNCATION
;; ============================================================================

(ert-deftest tibetan-interlinear-truncate-gloss ()
  "Gloss truncation respects word boundaries."
  ;; Short enough — unchanged
  (should (equal (tibetan-interlinear--truncate-gloss "suffering" 30)
                 "suffering"))
  ;; Needs truncation — cut at word boundary
  (let ((long "cyclic existence; cycle of powerless birth"))
    (should (<= (length (tibetan-interlinear--truncate-gloss long 20)) 21))
    ;; Single long word without spaces — falls back to char-level cut + ellipsis
    (let ((truncated (tibetan-interlinear--truncate-gloss "abcdefghijklmnop" 10)))
      (should (string-suffix-p "…" truncated))
      (should (<= (length truncated) 10)))
    ;; Multi-word string — cuts at word boundary, result is prefix of original
    (let ((truncated (tibetan-interlinear--truncate-gloss
                      "cyclic existence and rebirth" 20)))
      (should (<= (length truncated) 20))
      ;; Should be "cyclic existence" — clean word boundary, no ellipsis
      (should (string-prefix-p truncated "cyclic existence and rebirth"))
      (should (not (string-suffix-p "…" truncated))))))

;; ============================================================================
;; INTERLINEAR FORMAT ENTRY
;; ============================================================================

(ert-deftest tibetan-interlinear-format-entry-lexical ()
  "Lexical word with Steinert link and gloss."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "'khor ba"
                 "[[https://steinert.example.com][Steinert]]"
                 "cyclic existence"
                 nil nil)))
    ;; Should contain the wylie with gloss
    (should (string-match-p "'khor ba\\[cyclic existence\\]" result))
    ;; Should contain the URL
    (should (string-match-p "steinert.example.com" result))))

(ert-deftest tibetan-interlinear-format-entry-with-particle ()
  "Entry with both lexical stem and particle."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "blo rgod" nil "agitated mind"
                 "kyi" "GEN")))
    ;; Should have two parts
    (should (string-match-p "blo rgod\\[agitated mind\\]" result))
    (should (string-match-p "kyi\\[GEN\\]" result))
    ;; Particle should be a link
    (should (string-match-p "\\[\\[particle:kyi\\]" result))))

(ert-deftest tibetan-interlinear-format-entry-no-gloss ()
  "Entry without gloss shows just the wylie."
  (let ((result (tibetan-interlinear--format-gloss-entry
                 "ma" nil nil nil nil)))
    (should (equal result "ma"))))

(provide 'tibetan-interlinear-test)
;;; tibetan-interlinear-test.el ends here
