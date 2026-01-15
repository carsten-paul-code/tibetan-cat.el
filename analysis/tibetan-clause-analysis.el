;;; tibetan-clause-analysis.el --- Clause structure analysis -*- lexical-binding: t -*-

;;; Commentary:
;; Provides clause-level analysis for Tibetan text:
;; - Main verb identification
;; - Converb detection and classification
;; - Converb scoping (which converbs depend on which verbs)
;; - Clause tree building for nested structures
;;
;; Based on Bialek's converbial construction theory from
;; "A Textbook in Classical Tibetan"
;;
;; Converbial constructions (dependent clauses):
;; - Ablative converb (ནས) - sequential action: "having done X"
;; - Coordinative converb (ཏེ/སྟེ/དེ) - coordination: "X and..."
;; - Simultaneous converb (ཞིང/ཅིང/ཤིང) - accompanying: "while doing X"
;; - Causal converb (པས/བས) - reason: "because of X"
;; - Concessive (ཀྱང/ཡང/འང) - contrast: "even though X"

;;; Code:

(require 'cl-lib)

;; Load verb classifier if available
(require 'tibetan-verb-classifier nil t)

;; ============================================================================
;; CONVERB PARTICLE DEFINITIONS
;; ============================================================================

(defconst tibetan-converb-particles
  '(;; Ablative converb - sequential action
    (ablative . ("ནས"))
    ;; Coordinative converb - coordination/sequence
    (coordinative . ("ཏེ" "སྟེ" "དེ"))
    ;; Simultaneous converb - accompanying action
    (simultaneous . ("ཞིང" "ཅིང" "ཤིང"))
    ;; Causal converb - reason/cause
    (causal . ("པས" "བས"))
    ;; Concessive - "even though"
    (concessive . ("ཀྱང" "ཡང" "འང")))
  "Converb particles organized by type.")

(defconst tibetan-final-particles
  '("སོ" "འོ" "ཏོ" "དོ" "ནོ" "བོ" "མོ" "གོ" "ངོ" "རོ" "ལོ")
  "Final sentence particles that follow the main verb.")

(defconst tibetan-negative-particles
  '("མ" "མི" "མེད" "མིན")
  "Negative particles.")

;; ============================================================================
;; HELPER FUNCTIONS
;; ============================================================================

(defun tibetan-clause--clean-text (text)
  "Clean TEXT for analysis by normalizing punctuation."
  (when (and text (stringp text))
    (let ((clean text))
      ;; Remove final punctuation
      (setq clean (replace-regexp-in-string "[།༎༏༐༑༔]+$" "" clean))
      ;; Normalize internal spaces
      (setq clean (replace-regexp-in-string "  +" " " clean))
      (string-trim clean))))

(defun tibetan-clause--split-syllables (text)
  "Split TEXT into syllables by tsheg (་)."
  (when (and text (not (string-empty-p text)))
    (split-string (tibetan-clause--clean-text text) "་" t)))

(defun tibetan-clause--is-verb-p (word)
  "Check if WORD is a known or likely verb.
Uses verb database if available, otherwise falls back to heuristics."
  (and word
       (not (string-empty-p word))
       (or
        ;; Check verb database first
        (and (fboundp 'tibetan-verb-lookup)
             (tibetan-verb-lookup word))
        (and (fboundp 'tibetan-is-verb-p)
             (tibetan-is-verb-p word))
        ;; Fallback heuristics for common verbs not in database
        ;; Common verb stems (these are reliable indicators)
        (member word '("བཤད" "རྟོགས" "བསམ" "བསམས" "བལྟ" "བལྟས"
                       "ཐོས" "མཐོང" "ཤེས" "འདོད" "དགའ" "སྡུག"
                       "བཟོད" "སྐྱེས" "སྐྱེ" "གྲུབ" "ཐོབ"))
        ;; Honorific verbs
        (string-match-p "གསུང\\|བཞུགས\\|མཛད\\|གཟིགས\\|མཁྱེན" word)
        ;; Copulas and existentials
        (member word '("ཡིན" "མིན" "ཡོད" "མེད" "འདུག" "རེད"))
        ;; Motion verbs
        (string-match-p "འགྲོ\\|འོང\\|སོང" word))))

(defun tibetan-clause--get-converb-type (particle)
  "Get the converb type for PARTICLE."
  (cl-loop for (type . particles) in tibetan-converb-particles
           when (member particle particles)
           return type))

(defun tibetan-clause--strip-particle (word particle)
  "Strip PARTICLE suffix from WORD and return the stem."
  (when (and word particle (string-suffix-p particle word))
    (let ((stem (substring word 0 (- (length word) (length particle)))))
      (when (> (length stem) 0)
        stem))))

;; ============================================================================
;; CONVERB DETECTION
;; ============================================================================

(defun tibetan-detect-converbs (text)
  "Detect converbs in TEXT.
Returns a list of plists with :particle, :type, :stem, :position, and :word.

Converbs can appear in two forms:
1. As standalone particles: བཞུགས་ནས (two syllables: བཞུགས + ནས)
2. As suffixes attached to verb stems: ཐོས་པས (one syllable with suffix)

This function handles both cases."
  (when (and text (stringp text) (not (string-empty-p text)))
    (let ((syllables (tibetan-clause--split-syllables text))
          (converbs '())
          (pos 0))
      (dolist (syllable syllables)
        ;; Check each converb particle type
        (cl-loop for (type . particles) in tibetan-converb-particles
                 do (dolist (particle particles)
                      (cond
                       ;; Case 1: Particle is the whole syllable (standalone)
                       ;; The verb stem is the previous syllable
                       ((string= particle syllable)
                        (when (> pos 0)
                          (let ((prev-syllable (nth (1- pos) syllables)))
                            (push (list :particle particle
                                       :type type
                                       :stem prev-syllable
                                       :word syllable
                                       :position pos)
                                  converbs))))
                       ;; Case 2: Particle is a suffix on the syllable
                       ((and (string-suffix-p particle syllable)
                             (> (length syllable) (length particle)))
                        (let ((stem (tibetan-clause--strip-particle syllable particle)))
                          (when stem
                            (push (list :particle particle
                                       :type type
                                       :stem stem
                                       :word syllable
                                       :position pos)
                                  converbs)))))))
        (setq pos (1+ pos)))
      ;; Return in order of appearance
      (nreverse converbs))))

;; ============================================================================
;; MAIN VERB IDENTIFICATION
;; ============================================================================

(defun tibetan-find-main-verb (text)
  "Find the main verb in TEXT.
Returns a plist with :verb, :type, :position, :stem.
The main verb is typically the final verb not marked with a converb particle."
  (when (and text (stringp text) (not (string-empty-p text)))
    (let* ((clean-text (tibetan-clause--clean-text text))
           (syllables (tibetan-clause--split-syllables clean-text))
           (converbs (tibetan-detect-converbs text))
           ;; For standalone converb particles, position is the particle's position
           ;; The verb stem at (position - 1) is still part of the converb construction
           (converb-positions (mapcar (lambda (c) (plist-get c :position)) converbs))
           ;; Also exclude the stem positions for standalone converbs
           (converb-stem-positions
            (cl-loop for c in converbs
                     when (string= (plist-get c :word) (plist-get c :particle))
                     collect (1- (plist-get c :position))))
           (excluded-positions (append converb-positions converb-stem-positions))
           (main-verb nil)
           (pos (1- (length syllables))))

      ;; Scan from end to find main verb
      (while (and (>= pos 0) (not main-verb))
        (let ((syllable (nth pos syllables)))
          ;; Skip final particles and converb-related positions
          (unless (or (member syllable tibetan-final-particles)
                      (member pos excluded-positions)
                      ;; Also check if this syllable IS a converb particle
                      (tibetan-clause--get-converb-type syllable))
            ;; Check if this could be a verb
            (when (or (tibetan-clause--is-verb-p syllable)
                      ;; Copulas and existentials
                      (member syllable '("ཡིན" "མིན" "ཡོད" "མེད" "འདུག" "རེད")))
              (setq main-verb (list :verb syllable
                                   :type 'main
                                   :position pos
                                   :stem syllable)))))
        (setq pos (1- pos)))

      ;; If no explicit verb found, check for verb stems
      (unless main-verb
        (setq pos (1- (length syllables)))
        (while (and (>= pos 0) (not main-verb))
          (let ((syllable (nth pos syllables)))
            (unless (or (member syllable tibetan-final-particles)
                        (member pos excluded-positions)
                        (tibetan-clause--get-converb-type syllable))
              ;; Check verb database if available
              (when (and (fboundp 'tibetan-verb-lookup)
                        (tibetan-verb-lookup syllable))
                (setq main-verb (list :verb syllable
                                     :type 'main
                                     :position pos
                                     :stem syllable)))))
          (setq pos (1- pos))))

      main-verb)))

;; ============================================================================
;; CONVERB SCOPING
;; ============================================================================

(defun tibetan-scope-converbs (text)
  "Determine scoping relationships between converbs and main verbs in TEXT.
Returns a list of plists, each with :converb and :main-verb.
Each converb is paired with the verb it modifies."
  (when (and text (stringp text) (not (string-empty-p text)))
    (let* ((converbs (tibetan-detect-converbs text))
           (main-verb (tibetan-find-main-verb text))
           (scoped '()))

      (when (and converbs main-verb)
        ;; For now, use simple scoping: each converb scopes to the next verb
        ;; More sophisticated scoping would consider clause boundaries
        (let ((syllables (tibetan-clause--split-syllables text))
              (main-pos (plist-get main-verb :position)))

          (dolist (converb converbs)
            (let ((conv-pos (plist-get converb :position)))
              ;; Find the verb this converb scopes to
              ;; By default, scope to the final main verb
              ;; But if there's a coordinative converb between, scope to that
              (let ((target-verb main-verb))
                ;; Check for intermediate coordinative converbs
                (dolist (other-conv converbs)
                  (when (and (> (plist-get other-conv :position) conv-pos)
                            (eq 'coordinative (plist-get other-conv :type))
                            (< (plist-get other-conv :position) main-pos))
                    ;; This converb might scope to an intermediate verb
                    ;; For simplicity, we still scope to the main verb
                    nil))

                (push (list :converb converb
                           :main-verb target-verb)
                      scoped))))))

      ;; Return in order of appearance
      (nreverse scoped))))

;; ============================================================================
;; CLAUSE TREE BUILDING
;; ============================================================================

(defun tibetan-build-clause-tree (text)
  "Build a hierarchical clause tree from TEXT.
Returns a plist representing the clause structure:
  :type - 'clause
  :text - original text
  :main-verb - the main verb plist
  :dependent-clauses - list of dependent clause plists"
  (when (and text (stringp text) (not (string-empty-p text)))
    (let* ((main-verb (tibetan-find-main-verb text))
           (scoped (tibetan-scope-converbs text))
           (dependents '()))

      ;; Build dependent clauses from scoped converbs
      (dolist (scope scoped)
        (let ((converb (plist-get scope :converb)))
          (push (list :type 'dependent
                     :converb-type (plist-get converb :type)
                     :converb-particle (plist-get converb :particle)
                     :verb-stem (plist-get converb :stem)
                     :position (plist-get converb :position))
                dependents)))

      ;; Build the tree
      (when main-verb
        (list :type 'clause
              :text text
              :main-verb main-verb
              :dependent-clauses (nreverse dependents))))))

;; ============================================================================
;; FORMATTING FOR DISPLAY
;; ============================================================================

(defun tibetan-format-clause-tree (tree &optional indent)
  "Format TREE for display with optional INDENT level."
  (let ((indent (or indent 0))
        (prefix (make-string (* indent 2) ?\s)))
    (if (not tree)
        (concat prefix "[No clause structure detected]\n")
      (concat
       ;; Main clause
       (format "%sMain Clause:\n" prefix)
       (when (plist-get tree :main-verb)
         (format "%s  Main verb: %s\n" prefix
                 (plist-get (plist-get tree :main-verb) :verb)))
       ;; Dependent clauses
       (when (plist-get tree :dependent-clauses)
         (concat
          (format "%s  Dependent clauses (%d):\n" prefix
                  (length (plist-get tree :dependent-clauses)))
          (mapconcat
           (lambda (dep)
             (format "%s    - %s (%s): '%s' + %s"
                     prefix
                     (plist-get dep :converb-type)
                     (plist-get dep :converb-particle)
                     (plist-get dep :verb-stem)
                     (tibetan-clause--get-converb-translation
                      (plist-get dep :converb-type))))
           (plist-get tree :dependent-clauses)
           "\n")))))))

(defun tibetan-clause--get-converb-translation (type)
  "Get English translation hint for converb TYPE."
  (pcase type
    ('ablative "having V-ed / after V-ing")
    ('coordinative "V-ed and... / having V-ed")
    ('simultaneous "while V-ing / V-ing and...")
    ('causal "because V-ed / since V-ing")
    ('concessive "even though V / although V")
    (_ "V...")))

;; ============================================================================
;; INTEGRATION WITH EXISTING SYSTEM
;; ============================================================================

(defun tibetan-analyze-clause-structure (text)
  "Analyze clause structure in TEXT and return formatted analysis.
This is the main entry point for clause analysis."
  (when (and text (stringp text) (not (string-empty-p text)))
    (let ((tree (tibetan-build-clause-tree text)))
      (if tree
          (concat
           "CLAUSE STRUCTURE ANALYSIS\n"
           "========================\n\n"
           (tibetan-format-clause-tree tree)
           "\n")
        "No clause structure detected.\n"))))

(provide 'tibetan-clause-analysis)
;;; tibetan-clause-analysis.el ends here
