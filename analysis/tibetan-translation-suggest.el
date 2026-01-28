;;; tibetan-translation-suggest.el --- Suggest translations based on grammar + vocabulary -*- lexical-binding: t -*-

;;; Commentary:
;; Generates suggested translations by combining:
;; - Vocabulary analysis (word meanings)
;; - Bialek grammar analysis (case particles, converbs)
;; - Translation guidance for each grammatical construction
;;
;; Provides a STARTING POINT for classroom translation discussion,
;; not a final translation!

;;; Code:

(require 'cl-lib)
(require 'tibetan-vocabulary)
(require 'tibetan-particles-bialek)

;; ============================================================================
;; TRANSLATION SUGGESTION ENGINE
;; ============================================================================

(defun tibetan-suggest-translation (tibetan-text vocab-list grammar-list)
  "Suggest a translation based on VOCAB-LIST and GRAMMAR-LIST.

VOCAB-LIST: list of (tibetan-word . english-meaning)
GRAMMAR-LIST: Bialek grammar analysis from tibetan-analyze-grammar-bialek

Returns a suggested translation with grammatical notes."
  (let ((vocab-map (make-hash-table :test 'equal))
        (translation-parts '())
        (grammar-notes '()))

    ;; Build vocabulary lookup map
    (dolist (v vocab-list)
      (puthash (car v) (cdr v) vocab-map))

    ;; Process vocabulary items in order they appear
    (dolist (vocab-pair vocab-list)
      (let* ((tib-word (car vocab-pair))
             (meaning (cdr vocab-pair)))
        ;; Just use the vocabulary meanings directly
        (push meaning translation-parts)))

    ;; Add grammatical notes for REAL case particles only
    ;; Filter out false positives (particles inside compound words)
    (dolist (g grammar-list)
      (let* ((particle (nth 0 g))
             (word (nth 1 g))
             (gram-type (nth 2 g))
             (function (nth 3 g)))
        ;; Only include if this looks like a real grammatical word
        ;; Real particles: པ, བ, པའི, འི, ས, གིས, ན, ལ, ར, etc. as separate words
        (when (and (member gram-type
                          '("CONVERBIAL (ནས)" "CONVERBIAL (ཏེ)"
                            "CONVERBIAL (པས)" "CONVERBIAL (བས)"
                            "GENITIVE (GEN)" "ERGATIVE (ERG)"
                            "DATIVE (DAT)" "INSTRUMENTAL (INSTR)"
                            "TERMINATIVE (TERM)" "NOMINALIZER"))
                   ;; Word should be short (real particles are usually 1-3 chars)
                   (< (length word) 4))
          (push (format "  • %s (%s): %s" word gram-type function) grammar-notes))))

    ;; Build result
    (let ((suggested (string-join (nreverse translation-parts) " + "))
          (grammar-note-text
           (if grammar-notes
               (concat "\n\nKEY GRAMMATICAL MARKERS:\n"
                      (string-join (nreverse grammar-notes) "\n"))
             "")))
      (concat "WORD-BY-WORD GLOSS:\n"
              suggested
              grammar-note-text
              "\n\nNOTE: Compare with DharmaMitra translation above for natural phrasing.\n"
              "This gloss shows vocabulary + key grammatical particles."))))

;; ============================================================================
;; CONVERBIAL CONSTRUCTION TRANSLATION GUIDE
;; ============================================================================

(defun tibetan-explain-converb-translation (grammar-list)
  "Generate specific translation guidance for converbial constructions.
This helps students understand HOW to translate converbs correctly."
  (let ((converbs (cl-remove-if-not
                   (lambda (item) (string-match-p "CONVERBIAL" (nth 2 item)))
                   grammar-list)))
    (if (not converbs)
        ""
      (concat
       "\n═══════════════════════════════════════════════════════\n"
       "CONVERBIAL CONSTRUCTION TRANSLATION GUIDE\n"
       "═══════════════════════════════════════════════════════\n\n"
       "This segment contains CONVERBIAL CONSTRUCTIONS.\n"
       "These are DEPENDENT CLAUSES that connect to the main verb.\n\n"
       (mapconcat
        (lambda (item)
          (let ((particle (nth 0 item))
                (word (nth 1 item))
                (gram-type (nth 2 item))
                (translation-guide (nth 4 item)))
            (format "• Word: %s\n  Construction: %s\n  How to translate: %s\n"
                   word gram-type translation-guide)))
        converbs
        "\n")
       "\nSTRATEGY:\n"
       "1. Identify the MAIN VERB (final verb in Tibetan)\n"
       "2. Translate converbs as SUBORDINATE CLAUSES\n"
       "3. Connect them logically (sequence, cause, manner)\n"
       "4. Check: Does the English make sense?\n"))))

;; ============================================================================
;; COMPREHENSIVE TRANSLATION ASSISTANT
;; ============================================================================


(provide 'tibetan-translation-suggest)
;;; tibetan-translation-suggest.el ends here
