;;; tibetan-org-structure.el --- Org-mode structure support for Tibetan CAT -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Carsten Paul
;; Keywords: Tibetan, org-mode, structure
;; Version: 2.0.0

;;; Commentary:

;; This module provides support for working with Tibetan texts structured
;; in org-mode format for classroom translation work.
;;
;; Two structural conventions are supported:
;;
;; A) Fresh-prep format (produced by `tibetan-prepare-document'):
;;
;;    * Title
;;    ** Sentence 1
;;    *** Segment 1
;;    Tibetan text here
;;    *** Segment 2
;;    More text
;;    ** Sentence 2
;;    ...
;;
;; B) Section + after-the-fact sentence-wrap format (produced when
;;    `tibetan-add-sentence-structure' demotes existing segments under
;;    `** Section' parents):
;;
;;    * Title
;;    ** Section
;;    *** Sentence 1
;;    **** Segment 1
;;    Tibetan text here
;;    **** Segment 2
;;    *** Sentence 2
;;    **** Segment 3
;;    ...
;;
;; Detection is content-based ("Segment N" / "Sentence N" in the
;; heading text), not level-based, so both layouts work transparently.
;;
;; Workflow:
;; 1. On a Segment heading: C-c u A runs word-by-word segment analysis
;; 2. On a Sentence heading: C-c u A / C-c u S runs sentence-level
;;    analysis covering Translation, Grammar (discourse-level), and
;;    Context.
;;
;; Sentences are determined by main verbs, with double-shad (།།) as
;; definite sentence boundaries.
;;
;; Functions:
;; - Get segment text from current heading
;; - Get all segments in current sentence
;; - Get combined sentence text for clause analysis
;; - Navigate between segments/sentences

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'tibetan-utils)

;;; Detection Functions

(defun tibetan-org-at-segment-p ()
  "Return t if point is in or under a Segment heading.
Detects segments at any heading level (typically *** in the
fresh-prep layout, **** in the section + sentence-wrap layout
produced by `tibetan-add-sentence-structure').
Works both when cursor is on the heading line or in the content
below it."
  (save-excursion
    (condition-case nil
        (progn
          ;; Try to go back to the current or parent heading
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (let ((heading (org-get-heading t t t t)))
            (and heading
                 (string-match-p "\\bSegment\\b" heading))))
      (error nil))))

(defun tibetan-org-at-sentence-p ()
  "Return t if point is in or under a Sentence heading.
Detects sentences at any heading level (typically ** in the
fresh-prep layout, *** in the section + sentence-wrap layout
produced by `tibetan-add-sentence-structure').
Works both when cursor is on the heading line or in the content
below it."
  (save-excursion
    (condition-case nil
        (progn
          ;; Try to go back to the current or parent heading
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (let ((heading (org-get-heading t t t t)))
            (and heading
                 (string-match-p "\\bSentence\\b" heading))))
      (error nil))))

;;; Segment Functions

(defun tibetan-org-get-segment-text ()
  "Get Tibetan text from current segment.
Works when positioned anywhere in or under a *** Segment heading.
Returns nil if not in a segment (no error raised).

Skips an `:PROPERTIES: … :END:' drawer immediately following the
heading (used e.g. for `:FOLIO:' markers on Yogācārabhūmi segments)
so the drawer body is not mistaken for Tibetan text.  Also skips any
child `**** Working Translation' / other subheadings — only the
segment's own body text is returned."
  (condition-case nil
      (save-excursion
        (when (tibetan-org-at-segment-p)
          ;; Move to heading (handles both on heading and in content)
          (unless (org-at-heading-p)
            (org-back-to-heading t))

          ;; Use narrowing approach which is more reliable than org-element
          ;; especially when called from org-map-entries
          (save-restriction
            (org-narrow-to-subtree)
            (let* ((body-start
                    (save-excursion
                      (forward-line 1)          ; Past the heading line.
                      ;; Skip a leading `:PROPERTIES: … :END:' drawer
                      ;; if present — drawers are Org syntax for per-
                      ;; heading metadata (e.g. :FOLIO: D3a3).
                      (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
                        (when (re-search-forward
                               "^[ \t]*:END:[ \t]*$" nil t)
                          (forward-line 1)))
                      (point)))
                   (body-end
                    (save-excursion
                      (goto-char body-start)
                      ;; Stop at the first child heading (any depth).
                      (if (re-search-forward "^\\*+ " nil t)
                          (line-beginning-position)
                        (point-max))))
                   (text (buffer-substring-no-properties body-start body-end)))
              (widen)
              (when (and text (not (string-empty-p (string-trim text))))
                (string-trim text))))))
    (error nil)))

(defun tibetan-org-get-segment-id ()
  "Get segment ID (number) from current segment."
  (save-excursion
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (when (tibetan-org-at-segment-p)
      (let ((heading (org-get-heading t t t t)))
        (when (string-match "Segment \\([0-9]+\\)" heading)
          (string-to-number (match-string 1 heading)))))))

;;; Paragraph Functions
;;
;; A paragraph is a `** §N'-headed org subtree — the layout used by
;; `Rgyan-comparative.org' for Gendün Chöpel's Klu sgrub dgongs rgyan,
;; but kept generic so any document grouping segments under `** §N'
;; can drive paragraph-level analysis (C-c p A).
;;
;; The paragraph's Tibetan content lives in a `*** Tibetisch' or
;; `*** Tibetisch (B2)' child heading — other subheadings (Wylie,
;; Lopez, Wangjié, Übersetzung, Apparat) are skipped.

(defconst tibetan-org--paragraph-heading-regex
  "§\\([0-9]+\\)"
  "Regex capturing the paragraph number from a `** §N' heading.")

(defun tibetan-org-at-paragraph-p ()
  "Return t if point is in or under a `** §N' paragraph heading.
Walks up the outline via `org-up-heading-safe' so cursor position
inside any child (Tibetisch, Wylie, Übersetzung, …) still counts."
  (save-excursion
    (condition-case nil
        (let ((found nil))
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          ;; Walk up until we find a §-heading or hit the document root.
          (catch 'done
            (while t
              (let ((heading (org-get-heading t t t t)))
                (when (and heading
                           (string-match-p tibetan-org--paragraph-heading-regex
                                           heading))
                  (setq found t)
                  (throw 'done t))
                (unless (org-up-heading-safe)
                  (throw 'done nil)))))
          found)
      (error nil))))

(defun tibetan-org-get-paragraph-id ()
  "Return paragraph number (integer) for the current §-subtree, or nil.
Walks up headings until it finds one matching `** §N'."
  (save-excursion
    (condition-case nil
        (progn
          (unless (org-at-heading-p)
            (org-back-to-heading t))
          (catch 'done
            (while t
              (let ((heading (org-get-heading t t t t)))
                (when (and heading
                           (string-match tibetan-org--paragraph-heading-regex
                                         heading))
                  (throw 'done (string-to-number (match-string 1 heading))))
                (unless (org-up-heading-safe)
                  (throw 'done nil))))))
      (error nil))))

(defun tibetan-org--goto-paragraph-heading ()
  "Move point to the enclosing `** §N' heading line.
Returns t on success, nil if not in a paragraph."
  (when (tibetan-org-at-paragraph-p)
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    (catch 'done
      (while t
        (let ((heading (org-get-heading t t t t)))
          (when (and heading
                     (string-match-p tibetan-org--paragraph-heading-regex
                                     heading))
            (throw 'done t))
          (unless (org-up-heading-safe)
            (throw 'done nil)))))))

(defun tibetan-org-get-paragraph-text ()
  "Return concatenated Tibetan text of the current paragraph's Tibetisch child.
Looks for a `*** Tibetisch' or `*** Tibetisch (...)' subheading and
returns its body (whitespace-trimmed).  Returns nil if no such child
exists, or if point is not in a paragraph."
  (condition-case nil
      (save-excursion
        (when (tibetan-org--goto-paragraph-heading)
          (save-restriction
            (org-narrow-to-subtree)
            (goto-char (point-min))
            (when (re-search-forward
                   "^\\*\\{3,\\}[ \t]+Tibetisch\\(?:[ \t]+([^)]+)\\)?[ \t]*$"
                   nil t)
              (let* ((body-start
                      (save-excursion
                        (forward-line 1)
                        (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
                          (when (re-search-forward
                                 "^[ \t]*:END:[ \t]*$" nil t)
                            (forward-line 1)))
                        (point)))
                     (body-end
                      (save-excursion
                        (goto-char body-start)
                        (if (re-search-forward "^\\*+ " nil t)
                            (line-beginning-position)
                          (point-max))))
                     (text (buffer-substring-no-properties body-start body-end)))
                (widen)
                (when (and text (not (string-empty-p (string-trim text))))
                  (string-trim text)))))))
    (error nil)))

(defconst tibetan-org--paragraph-source-prefixes
  '("tibetisch" "tibetan" "tibetan text")
  "Lower-cased heading-prefix patterns for the *source* sub-heading
(the Tibetan text itself).  Excluded from reference-translation
extraction.")

(defconst tibetan-org--paragraph-non-reference-prefixes
  '("wylie"
    "eigene übersetzung" "eigene uebersetzung"
    "working translation"
    "apparat" "notes" "notizen" "my notes" "footnotes"
    "claude")
  "Lower-cased heading-prefix patterns for sub-sections that are
NOT reference translations (transliteration, user draft, philological
notes, Claude-generated content).  Excluded together with the source
prefixes; everything else under `** §N' is treated as a reference
translation.")

(defun tibetan-org--paragraph-reference-section-p (heading)
  "Return non-nil if HEADING names a reference-translation sub-section.
A reference is any sub-section that is NOT the source (Tibetisch)
and NOT a structural / scratch / philological sibling."
  (let ((nh (downcase (string-trim heading))))
    (not (or (cl-some (lambda (p) (string-prefix-p p nh))
                      tibetan-org--paragraph-source-prefixes)
             (cl-some (lambda (p) (string-prefix-p p nh))
                      tibetan-org--paragraph-non-reference-prefixes)))))

(defun tibetan-org-get-paragraph-references ()
  "Return alist of (heading . body) for reference-translation siblings.
Walks every direct `***'-child of the enclosing `** §N' paragraph
heading.  Skips the Tibetan source, transliteration, user draft,
and philological-note sections (see
`tibetan-org--paragraph-source-prefixes' and
`tibetan-org--paragraph-non-reference-prefixes').  Empty bodies are
filtered out.  Returns nil when point is not inside a paragraph or
when no reference-translation siblings exist.

Designed for the Rgyan-comparative.org layout
  ** §N
  *** Tibetisch (B2)        ← skipped (source)
  *** Wylie                 ← skipped
  *** Lopez 2006            ← extracted
  *** Wangjié & Mulligan    ← extracted
  *** Eigene Übersetzung    ← skipped (user draft)
  *** Apparat und Notizen   ← skipped (philology)
but generic to any §-based document with translation siblings."
  (condition-case nil
      (save-excursion
        (when (tibetan-org--goto-paragraph-heading)
          (save-restriction
            (org-narrow-to-subtree)
            (goto-char (point-min))
            (let ((refs '()))
              (while (re-search-forward "^\\*\\{3,\\}[ \t]+\\(.+?\\)[ \t]*$"
                                        nil t)
                (let ((heading (string-trim (match-string 1))))
                  (when (tibetan-org--paragraph-reference-section-p heading)
                    (let* ((body-start
                            (save-excursion
                              (forward-line 1)
                              (when (looking-at-p "[ \t]*:PROPERTIES:[ \t]*$")
                                (when (re-search-forward
                                       "^[ \t]*:END:[ \t]*$" nil t)
                                  (forward-line 1)))
                              (point)))
                           (body-end
                            (save-excursion
                              (goto-char body-start)
                              (if (re-search-forward "^\\*+ " nil t)
                                  (line-beginning-position)
                                (point-max))))
                           (body (string-trim
                                  (buffer-substring-no-properties
                                   body-start body-end))))
                      (when (not (string-empty-p body))
                        (push (cons heading body) refs))))))
              (widen)
              (nreverse refs)))))
    (error nil)))

;;; Sentence Functions

(defun tibetan-org-get-sentence-segments ()
  "Get all segment texts from current sentence.
Returns a list of strings, one per segment.
Works when positioned anywhere in or under a sentence."
  (save-excursion
    ;; First, ensure we're on a heading
    (unless (org-at-heading-p)
      (org-back-to-heading t))

    (unless (or (tibetan-org-at-sentence-p)
                (tibetan-org-at-segment-p))
      (error "Not in a sentence or segment"))

    ;; Move to sentence heading (level 2)
    (when (tibetan-org-at-segment-p)
      (org-up-heading-safe))

    (unless (tibetan-org-at-sentence-p)
      (error "Could not find sentence heading"))

    ;; Collect all segments under this sentence
    (let ((segments '())
          (sentence-level (org-current-level)))

      (org-map-entries
       (lambda ()
         (when (and (= (org-current-level) (1+ sentence-level))
                    (tibetan-org-at-segment-p))
           (let ((text (tibetan-org-get-segment-text)))
             (when text
               (push (cons (tibetan-org-get-segment-id) text) segments)))))
       nil 'tree)

      ;; Sort by segment number and return just the text
      (mapcar #'cdr (sort segments (lambda (a b) (< (car a) (car b))))))))

(defun tibetan-org-get-sentence-text ()
  "Get combined Tibetan text from all segments in current sentence.
Returns a single string with all segment texts joined.
Works when positioned anywhere in or under a sentence."
  (let ((segments (tibetan-org-get-sentence-segments)))
    (when segments
      (mapconcat #'identity segments " "))))

(defun tibetan-org-get-sentence-data ()
  "Get sentence data for analysis.
Returns cons cell (ID . TEXT) where ID is \='Sentence N\=' and TEXT is
combined segments. Works when positioned on a ** Sentence heading."
  (when (tibetan-org-at-sentence-p)
    (let ((sent-id (tibetan-org-get-sentence-id))
          (text (tibetan-org-get-sentence-text)))
      (when (and sent-id text)
        (cons (format "Sentence %d" sent-id) text)))))

(defun tibetan-org-get-sentence-id ()
  "Get sentence ID (number) from current sentence.
Works when positioned anywhere in or under a sentence."
  (save-excursion
    ;; First, ensure we're on a heading
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    ;; If we're at a segment, move up to sentence
    (when (tibetan-org-at-segment-p)
      (org-up-heading-safe))
    (when (tibetan-org-at-sentence-p)
      (let ((heading (org-get-heading t t t t)))
        (when (string-match "Sentence \\([0-9]+\\)" heading)
          (string-to-number (match-string 1 heading)))))))

(defun tibetan-org-get-parent-section-name ()
  "Get the name of the parent Section (level 2 heading).
Walks up from the current heading until reaching level 2 — the
canonical Section level in both supported layouts.  Useful for
files that don't use \='Sentence N\=' format (e.g.,
\='[30] Introduction\=' style headings).

In the fresh-prep layout this returns the level-2 heading
directly (which is often \='Sentence N\=' — that is the documented
fallback behaviour preserved for backward compatibility).  In the
section + sentence-wrap layout it walks up past the level-3
Sentence to return the actual Section name."
  (save-excursion
    ;; First, ensure we're on a heading
    (unless (org-at-heading-p)
      (org-back-to-heading t))
    ;; Walk up until we hit level 2 (or run out of parents).
    (while (and (> (or (org-current-level) 0) 2)
                (org-up-heading-safe)))
    ;; Get the heading text if we're at level 2.
    (when (and (org-current-level)
               (= (org-current-level) 2))
      (let ((heading (org-get-heading t t t t)))
        ;; Clean up heading - remove leading/trailing spaces and brackets
        (when heading
          (string-trim heading))))))

;;; Navigation Functions

;;;###autoload
(defun tibetan-org-next-segment ()
  "Move to next segment heading."
  (interactive)
  (when (tibetan-org-at-segment-p)
    (org-forward-heading-same-level 1)))

;;;###autoload
(defun tibetan-org-previous-segment ()
  "Move to previous segment heading."
  (interactive)
  (when (tibetan-org-at-segment-p)
    (org-backward-heading-same-level 1)))

;;;###autoload
(defun tibetan-org-next-sentence ()
  "Move to next sentence heading."
  (interactive)
  (when (tibetan-org-at-sentence-p)
    (org-forward-heading-same-level 1))
  (when (tibetan-org-at-segment-p)
    (org-up-heading-safe)
    (org-forward-heading-same-level 1)))

;;;###autoload
(defun tibetan-org-previous-sentence ()
  "Move to previous sentence heading."
  (interactive)
  (when (tibetan-org-at-sentence-p)
    (org-backward-heading-same-level 1))
  (when (tibetan-org-at-segment-p)
    (org-up-heading-safe)
    (org-backward-heading-same-level 1)))

;;; Display Functions

;;;###autoload
(defun tibetan-org-show-segment-info ()
  "Show information about current segment."
  (interactive)
  (if (tibetan-org-at-segment-p)
      (let ((seg-id (tibetan-org-get-segment-id))
            (sent-id (tibetan-org-get-sentence-id))
            (text (tibetan-org-get-segment-text)))
        (message "Sentence %d, Segment %d: %s"
                 sent-id seg-id
                 (if (> (length text) 50)
                     (concat (substring text 0 47) "...")
                   text)))
    (message "Not in a segment heading")))

;;;###autoload
(defun tibetan-org-show-sentence-info ()
  "Show information about current sentence."
  (interactive)
  (let ((sent-id (tibetan-org-get-sentence-id))
        (segments (tibetan-org-get-sentence-segments)))
    (if segments
        (message "Sentence %d has %d segments"
                 sent-id (length segments))
      (message "Not in a sentence heading"))))

;;; Integration with Existing CAT Functions

(defun tibetan-org-segment-for-analysis ()
  "Get segment text for analysis.
Returns segment text if in org structure, nil otherwise.
This integrates with tibetan-classroom.el."
  (when (and (derived-mode-p 'org-mode)
             (tibetan-org-at-segment-p))
    (tibetan-org-get-segment-text)))

(defun tibetan-org-segments-for-workspace ()
  "Get sentence segments for workspace.
Returns list of segment texts if in org structure, nil otherwise.
This integrates with tibetan-sentence-workspace.el."
  (when (and (derived-mode-p 'org-mode)
             (or (tibetan-org-at-sentence-p)
                 (tibetan-org-at-segment-p)))
    (tibetan-org-get-sentence-segments)))

;;; Document Preparation Functions

;;;###autoload
(defun tibetan-prepare-document (&optional title)
  "Prepare current buffer for Tibetan translation work.
Segments the Tibetan text and adds org-mode headers.

Call this after pasting Tibetan text into a new .org buffer.
The function will:
1. Add org-mode headers (title, startup options)
2. Group segments into sentences (by main verb / double-shad)
3. Create * Sentence N / ** Segment N structure

Structure created:
  * Title
  ** Sentence 1
  *** Segment 1
  text...
  *** Segment 2
  text...
  ** Sentence 2
  ...

Workflow:
- C-c u A on *** Segment: word-by-word analysis
- C-c u A on ** Sentence: clause structure analysis

With prefix arg or TITLE, prompts for document title."
  (interactive
   (list (when current-prefix-arg
           (read-string "Document title: "))))
  (unless (derived-mode-p 'org-mode)
    (org-mode))

  (let* ((title (if title
                    title
                  (if noninteractive
                      "Tibetan Text"  ; Default for batch mode
                    (read-string "Document title (or press Enter for default): "
                                 nil nil "Tibetan Text"))))
         (raw-text (string-trim (buffer-string)))
         (_ (message "Segmenting text..."))
         (sentences (tibetan--group-into-sentences raw-text))
         (_ (message "Creating document structure..."))
         (total-segments 0))

    ;; Clear buffer
    (erase-buffer)

    ;; Insert headers
    (insert (format "#+TITLE: %s\n" title))
    (insert (format "#+DATE: %s\n" (format-time-string "%Y-%m-%d")))
    ;; `showall' so newly-prepared documents open with every sentence
    ;; and segment heading already expanded — scholars want to see the
    ;; whole text at once, not have to TAB through folds.
    (insert "#+STARTUP: showall\n")
    (insert "#+PROPERTY: header-args :eval no\n\n")

    ;; Insert main heading
    (insert (format "* %s\n\n" title))

    ;; Insert sentences with their segments
    (let ((sent-num 0)
          (global-seg-num 0))

      (dolist (sentence sentences)
        (setq sent-num (1+ sent-num))
        (insert (format "** Sentence %d\n\n" sent-num))

        ;; Insert segments for this sentence
        (let ((local-seg-num 0))
          (dolist (seg sentence)
            (setq local-seg-num (1+ local-seg-num))
            (setq global-seg-num (1+ global-seg-num))
            (insert (format "*** Segment %d\n" global-seg-num))
            (insert seg)
            (insert "\n\n")))

        (setq total-segments (+ total-segments (length sentence))))

      ;; Add vocabulary section
      (insert "* Vocabulary\n")
      (insert ":PROPERTIES:\n")
      (insert ":VISIBILITY: folded\n")
      (insert ":END:\n\n")
      (insert "| Tibetan | Wylie | English |\n")
      (insert "|---------+-------+---------|\n")
      (insert "|         |       |         |\n\n")

      ;; Add notes section
      (insert "* Notes\n\n")

      ;; Go back to beginning
      (goto-char (point-min))

      ;; Fold the document (only in interactive mode)
      (unless noninteractive
        (org-global-cycle 1))

      (message "Prepared document with %d segments in %d sentences. C-c u A on segment for word analysis, on sentence for clause analysis."
               total-segments sent-num))))

(defun tibetan--group-into-sentences (text)
  "Group Tibetan TEXT into sentences, each containing multiple segments.
Returns list of lists: ((seg1 seg2) (seg3 seg4 seg5) ...).

Uses fast heuristic sentence boundary detection:
1. Double-shad (།།) - always ends sentence
2. Final particles (སོ། འོ། etc.) - ends sentence
3. Copula/existentials at end (ཡིན། མེད། etc.) - ends sentence
4. Converb particles (ནས། ཏེ། ཅིང། etc.) - do NOT end sentence

This is the FAST version used during document preparation.
For more accurate analysis, use C-c u A on individual segments."
  (let ((segments (tibetan--segment-text text)))
    (if (null segments)
        nil
      (let ((sentences '())
            (current-sentence '()))

        (dolist (seg segments)
          (push seg current-sentence)

          ;; Use FAST sentence boundary detection (no verb analysis)
          (when (tibetan--segment-ends-sentence-fast-p seg)
            (push (nreverse current-sentence) sentences)
            (setq current-sentence '())))

        ;; Don't forget remaining segments (incomplete sentence at end)
        (when current-sentence
          (push (nreverse current-sentence) sentences))

        (nreverse sentences)))))

(defun tibetan--segment-ends-sentence-fast-p (segment)
  "Fast check if SEGMENT ends a sentence (no verb analysis).
Uses simple pattern matching - much faster than full verb analysis."
  (when (and segment (stringp segment) (not (string-empty-p segment)))
    (let ((seg (string-trim segment)))
      (or
       ;; Double-shad always marks sentence end
       (string-match-p "།།[ \t]*$" seg)
       ;; Final particles always mark sentence end
       (string-match-p "[སའཏདནབམགངརལ]ོ།[ \t]*$" seg)  ; -o finals
       ;; Copulas and existentials at end
       (string-match-p "ཡིན།[ \t]*$\\|མིན།[ \t]*$\\|ཡོད།[ \t]*$\\|མེད།[ \t]*$\\|འདུག།[ \t]*$\\|རེད།[ \t]*$" seg)
       ;; Honorific verbs at end
       (string-match-p "གསུངས།[ \t]*$\\|བཞུགས།[ \t]*$\\|མཛད།[ \t]*$\\|གཟིགས།[ \t]*$" seg)
       ;; NOT a converb ending (converbs chain to next clause)
       (and (not (string-match-p "ནས།[ \t]*$\\|ཏེ།[ \t]*$\\|སྟེ།[ \t]*$\\|དེ།[ \t]*$" seg))
            (not (string-match-p "ཅིང།[ \t]*$\\|ཞིང།[ \t]*$\\|ཤིང།[ \t]*$" seg))
            (not (string-match-p "པས།[ \t]*$\\|བས།[ \t]*$" seg))
            ;; If none of the above, check if it just ends with shad (simple clause)
            ;; Group every 3 simple clauses into a sentence as fallback
            nil)))))

(defun tibetan--segment-has-main-verb-p (segment)
  "Check if SEGMENT likely contains a main verb (sentence-final).
Uses clause analysis when available, otherwise falls back to heuristics.

A segment has a main verb if:
1. It ends with double-shad (།།)
2. It ends with a final particle (སོ། འོ། etc.)
3. It contains a verb that is NOT followed by a converb particle
4. It contains copula (ཡིན/མིན) or existential (ཡོད/མེད/འདུག/རེད)"
  (when (and segment (stringp segment) (not (string-empty-p segment)))
    (or
     ;; Double-shad always marks sentence end
     (string-match-p "།།$" segment)
     ;; Final particles always mark sentence end
     (string-match-p "སོ།$\\|འོ།$\\|ཏོ།$\\|དོ།$\\|ནོ།$\\|བོ།$\\|མོ།$\\|གོ།$\\|ངོ།$\\|རོ།$\\|ལོ།$" segment)
     ;; Use clause analysis if available
     (and (fboundp 'tibetan-find-main-verb)
          (tibetan-find-main-verb segment))
     ;; Fallback: check for copulas and existentials
     (string-match-p "ཡིན།$\\|མིན།$\\|ཡོད།$\\|མེད།$\\|འདུག།$\\|རེད།$" segment)
     ;; Fallback: honorific verbs at end
     (string-match-p "གསུངས།$\\|བཞུགས།$\\|མཛད།$\\|གཟིགས།$\\|མཁྱེན།$" segment))))

(defun tibetan--segment-is-converb-only-p (segment)
  "Check if SEGMENT ends with a converb particle (dependent clause marker).
Such segments cannot end a sentence - they connect to the following clause.

Converb particles include:
- Ablative: ནས (having V-ed, after V-ing)
- Coordinative: ཏེ/སྟེ/དེ (V-ed and...)
- Simultaneous: ཞིང/ཅིང/ཤིང (while V-ing)
- Causal: པས/བས (because V-ed) - NOTE: can also be agentive
- Concessive: ཀྱང/ཡང/འང (even though V)"
  (when (and segment (stringp segment) (not (string-empty-p segment)))
    ;; Use clause analysis if available
    (if (fboundp 'tibetan-detect-converbs)
        (let ((converbs (tibetan-detect-converbs segment)))
          (when converbs
            ;; Check if the LAST element is a converb (not just any converb in text)
            ;; A segment is converb-only if it ends with a converb, not a main verb
            (let* ((main-verb (and (fboundp 'tibetan-find-main-verb)
                                   (tibetan-find-main-verb segment)))
                   (last-converb (car (last converbs))))
              ;; If there's no main verb, or the converb comes after any main verb
              (and last-converb
                   (or (not main-verb)
                       (> (plist-get last-converb :position)
                          (plist-get main-verb :position)))))))
      ;; Fallback heuristics when clause analysis not available
      (or
       ;; Ablative converb
       (string-match-p "ནས།$" segment)
       ;; Coordinative converbs
       (string-match-p "ཏེ།$\\|སྟེ།$\\|དེ།$" segment)
       ;; Simultaneous converbs
       (string-match-p "ཞིང།$\\|ཅིང།$\\|ཤིང།$" segment)
       ;; Note: པས/བས excluded as they can be agentive
       ;; Concessive
       (string-match-p "ཀྱང།$\\|ཡང།$\\|འང།$" segment)))))

(defun tibetan--segment-ends-sentence-p (segment)
  "Determine if SEGMENT marks a sentence boundary.
Returns t if the segment should end the current sentence.

Sentence ends are marked by:
1. Double-shad (།།) - always a boundary
2. Final particles (སོ། འོ། etc.)
3. Main verb without following converb or subordinating particle

Does NOT end sentence if:
- Segment ends with a converb particle (dependent clause)
- Segment ends with temporal/conditional markers (ཚེ། ན། etc.)"
  (when (and segment (stringp segment) (not (string-empty-p segment)))
    (cond
     ;; Double-shad always ends sentence
     ((string-match-p "།།" segment) t)
     ;; Final particles always end sentence
     ((string-match-p "སོ།\\|འོ།\\|ཏོ།\\|དོ།\\|ནོ།\\|བོ།\\|མོ།\\|གོ།\\|ངོ།\\|རོ།\\|ལོ།" segment) t)
     ;; Converb-only segments do NOT end sentence
     ((tibetan--segment-is-converb-only-p segment) nil)
     ;; Temporal/conditional particles do NOT end sentence
     ;; ཚེ (when), ན (if/when after tsheg), དུས (time when)
     ;; Note: ན must be preceded by tsheg to distinguish from ཡིན།
     ((string-match-p "ཚེ།$\\|་ན།$\\|དུས།$" segment) nil)
     ;; Agentive གིས། at end - likely continues to next segment
     ;; Note: ས། alone could be part of words, so require གིས/ཀྱིས/etc.
     ((string-match-p "གིས།$\\|ཀྱིས།$\\|གྱིས།$" segment) nil)
     ;; Check for main verb (copula, existential, etc.)
     ((tibetan--segment-has-main-verb-p segment) t)
     ;; Default: don't end sentence
     (t nil))))

(defun tibetan--segment-text (text)
  "Segment Tibetan TEXT into translation units.
Splits on:
1. Hard line breaks (\\n) - each line becomes a segment
2. Double-shad (།།) - sentence boundaries
3. Single shad (།) - clause boundaries (only if no line breaks found)

Returns list of segment strings."
  (let ((segments '()))

    ;; Check if text has meaningful line breaks (more than one non-empty line)
    (let* ((lines (split-string text "[\n\r]+" t))
           (non-empty-lines (cl-remove-if
                             (lambda (l) (string-empty-p (string-trim l)))
                             lines)))

      (if (> (length non-empty-lines) 1)
          ;; Multiple lines found - use line breaks as primary segmentation
          (dolist (line non-empty-lines)
            (let ((trimmed (string-trim line)))
              (when (not (string-empty-p trimmed))
                ;; Keep the line as-is (it may or may not end with shad)
                (push trimmed segments))))

        ;; Single block of text - segment by shad
        (let ((normalized-text (string-trim text)))
          (setq normalized-text (replace-regexp-in-string "[\n\r]+" " " normalized-text))
          (setq normalized-text (replace-regexp-in-string "  +" " " normalized-text))

          ;; Split on shad patterns
          (let ((parts (split-string normalized-text "།།\\|།" t)))
            (dolist (part parts)
              (let ((trimmed (string-trim part)))
                (when (not (string-empty-p trimmed))
                  ;; Add shad back for proper Tibetan
                  (push (concat trimmed "།") segments))))))))

    ;; Return in original order
    (nreverse segments)))

;;;###autoload
(defun tibetan-prepare-document-from-region (start end &optional title)
  "Prepare Tibetan text in region for translation work.
Creates segments from the selected Tibetan text.
Result replaces the region content."
  (interactive "r\nsDocument title (Enter for default): ")
  (let ((text (buffer-substring-no-properties start end))
        (title (if (string-empty-p title) "Tibetan Text" title)))
    (delete-region start end)
    (insert text)
    (goto-char start)
    (narrow-to-region start (point-max))
    (tibetan-prepare-document title)
    (widen)))

;;;###autoload
(defun tibetan-prepare-new-document ()
  "Create a new buffer and prepare it for Tibetan translation.
Prompts for title and then for the Tibetan text to paste."
  (interactive)
  (let* ((title (read-string "Document title: " nil nil "Tibetan Text"))
         (buf-name (concat title ".org"))
         (buf (generate-new-buffer buf-name)))
    (switch-to-buffer buf)
    (org-mode)
    (message "Paste your Tibetan text, then run M-x tibetan-prepare-document or C-c u P")))

;; Keybinding for document preparation
(global-set-key (kbd "C-c u P") 'tibetan-prepare-document)

(provide 'tibetan-org-structure)
;;; tibetan-org-structure.el ends here
