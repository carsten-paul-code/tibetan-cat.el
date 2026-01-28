;;; tibetan-classroom.el --- Segment analysis for classroom use -*- lexical-binding: t -*-

;;; Commentary:
;; Main classroom analysis tool - shows comprehensive segment analysis:
;; - Tibetan text
;; - Wylie transliteration
;; - DharmaMitra translation
;; - Vocabulary with meanings
;; - Context-aware grammatical analysis
;; - Verb classification (Hill 2010 lexicon)
;;
;; Displays analysis in side window (C-c u i)
;; Supports auto-analysis mode (C-c u E)

;;; Code:

(require 'cl-lib)
(require 'tibetan-utils)
(require 'tibetan-wylie)
(require 'tibetan-vocabulary)
(require 'tibetan-vocabulary-detailed nil t)  ; Detailed dictionary entries
(require 'tibetan-particles-bialek)      ; New Bialek-based grammar analysis
(require 'tibetan-translation-suggest)   ; Translation suggestion engine
(require 'tibetan-org-structure)
(require 'tibetan-verb-classifier nil t)  ; Optional verb classification

;; ============================================================================
;; ANALYSIS CACHE (for performance)
;; ============================================================================

(defvar tibetan-analysis-cache (make-hash-table :test 'equal)
  "Cache for segment analysis results.
Key: (segment-id . content-hash)
Value: (wylie translation vocabulary grammar suggestion)")

(defun tibetan-cache-key (seg-id tibetan-text)
  "Generate cache key from segment ID and content hash."
  (cons seg-id (secure-hash 'md5 tibetan-text)))

(defun tibetan-get-cached-analysis (seg-id tibetan-text)
  "Get cached analysis for segment, or nil if not cached."
  (let ((key (tibetan-cache-key seg-id tibetan-text)))
    (gethash key tibetan-analysis-cache)))

(defun tibetan-cache-analysis (seg-id tibetan-text wylie translation vocab grammar suggestion)
  "Cache analysis results for segment."
  (let ((key (tibetan-cache-key seg-id tibetan-text)))
    (puthash key (list wylie translation vocab grammar suggestion) tibetan-analysis-cache)))


;; ============================================================================
;; DHARMAMITRA INTEGRATION
;; ============================================================================

(defun tibetan-get-dharmamitra-translation (tibetan-text)
  "Get DharmaMitra translation for TIBETAN-TEXT.
Returns translation string or error message."
  (when (and tibetan-text (not (string-empty-p tibetan-text)))
    (condition-case err
        (if (fboundp 'dharmamitra-text-get-translation)
            (let ((trans (dharmamitra-text-get-translation tibetan-text)))
              (if (and trans
                      (not (string-empty-p trans))
                      (not (string= trans "null")))
                (string-trim trans)
                "[Translation not available]"))
          "[DharmaMitra not loaded]")
      (error "[DharmaMitra error]"))))

;; ============================================================================
;; VERB ANALYSIS INTEGRATION
;; ============================================================================

(defun tibetan-extract-and-analyze-verbs (tibetan-text)
  "Extract verbs from TIBETAN-TEXT and analyze them using Hill lexicon.
Returns list of verb entries found, or nil if verb classifier not available."
  (when (and tibetan-text
             (fboundp 'tibetan-verb-lookup)
             (not (string-empty-p tibetan-text)))
    (let* ((syllables (split-string (replace-regexp-in-string "[།༎༏༐༑༔]" "" tibetan-text) "་" t))
           (verbs '()))
      ;; Try to look up each syllable as a potential verb
      (dolist (syl syllables)
        (let ((syl-clean (string-trim syl)))
          (when (not (string-empty-p syl-clean))
            (when-let ((verb-entry (tibetan-verb-lookup syl-clean)))
              ;; Avoid duplicates by checking lemma
              (let ((lemma (alist-get 'lemma verb-entry)))
                (unless (cl-find lemma verbs :key (lambda (v) (alist-get 'lemma v)) :test 'string=)
                  (push verb-entry verbs)))))))
      (nreverse verbs))))

;; ============================================================================
;; MAIN ANALYSIS FUNCTION
;; ============================================================================

(defun tibetan-segment-info (&optional silent fast)
  "Show segment analysis in RIGHT window.
Displays:
- Tibetan text
- Wylie transliteration
- DharmaMitra translation (unless FAST is non-nil)
- Vocabulary with meanings
- Context-aware grammatical analysis

Works with both:
- Org structure: *** Segment N
- Old markers: 〔seg:...〕

Bound to C-c u i.

If SILENT is non-nil, return nil instead of raising error when not in segment.
If FAST is non-nil, skip slow DharmaMitra translation (for auto-mode)."
  (interactive)
  (let* ((seg-data (tibetan-get-current-segment-any-format))
         (seg-id (car seg-data))
         (tibetan-text (cdr seg-data)))

    (if (not seg-data)
        ;; No segment data - either return nil or show error
        (unless silent
          (error "Not in a segment. Use org structure (*** Segment) or old markers 〔seg:...〕"))

      ;; We have segment data - try cache first, then compute if needed
      (let* ((cached (tibetan-get-cached-analysis seg-id tibetan-text))
             (wylie nil) (translation nil) (vocab nil) (grammar nil) (suggestion nil)
             (buffer (get-buffer-create "*Segment Info*")))

        ;; Check cache or compute
        (if cached
            ;; Use cached results
            (setq wylie (nth 0 cached)
                  translation (nth 1 cached)
                  vocab (nth 2 cached)
                  grammar (nth 3 cached)
                  suggestion (nth 4 cached))
          ;; Compute and cache results
          (setq wylie
                (condition-case err
                    (if (fboundp 'tibetan-to-wylie-fixed)
                        (tibetan-to-wylie-fixed tibetan-text)
                      "[Wylie converter not loaded]")
                  (error (format "[Wylie error: %s]" (error-message-string err)))))

          (setq translation
                (unless fast
                  (tibetan-get-dharmamitra-translation tibetan-text)))

          (setq vocab (tibetan-extract-vocabulary tibetan-text))

          (setq grammar (tibetan-analyze-grammar-bialek tibetan-text))

          (setq suggestion (tibetan-suggest-translation tibetan-text vocab grammar))

          ;; Always cache the results (even in fast mode without translation)
          ;; This ensures second visit is instant, regardless of which mode was used first
          (tibetan-cache-analysis seg-id tibetan-text wylie translation vocab grammar suggestion))

        ;; Extract verbs (not cached - fast lookup from database)
        (let ((verbs (tibetan-extract-and-analyze-verbs tibetan-text)))

        ;; Now display the results (whether cached or freshly computed)
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
              (erase-buffer)

              ;; Header
              (insert "╔══════════════════════════════════════════════════════════════╗\n")
              (insert "║         SEGMENT ANALYSIS - CLASSROOM                         ║\n")
              (insert "╚══════════════════════════════════════════════════════════════╝\n\n")
              (insert (format "Segment: %s %s\n\n" seg-id
                             (if cached "[CACHED ⚡]" "")))

              ;; Tibetan
              (insert "TIBETAN TEXT:\n")
              (insert tibetan-text)
              (insert "\n\n")

              ;; Wylie
              (insert "WYLIE (for reading aloud):\n")
              (insert wylie)
              (insert "\n\n")

              ;; Translation
              (insert "DHARMAMITRA TRANSLATION:\n")
              (tibetan-insert-separator)
              (if fast
                  (insert "[Skipped in auto-mode for speed - press C-c u i to see translation]\n\n")
                (insert (or translation "[Not available]"))
                (insert "\n\n"))

              ;; Vocabulary - use new detailed system for consistency with C-c u A
              (insert "VOCABULARY:\n")
              (tibetan-insert-separator)
              (let ((detailed-vocab (condition-case nil
                                        (when (fboundp 'tibetan-vocab-extract-detailed)
                                          (tibetan-vocab-extract-detailed tibetan-text))
                                      (error nil))))
                (if detailed-vocab
                    (progn
                      (dolist (entry detailed-vocab)
                        (let* ((tib (plist-get entry :tibetan))
                               (wy (plist-get entry :wylie))
                               (primary (plist-get entry :primary))
                               (source (plist-get entry :source)))
                          (insert (format "  %s [%s] — %s"
                                          tib
                                          (or wy "?")
                                          (or primary "[not found]")))
                          (when (and source (string= source "Resources"))
                            (insert " ★"))
                          (insert "\n")))
                      (insert "\n"))
                  ;; Fallback to old vocab system
                  (if vocab
                      (progn
                        (insert (tibetan-vocab-format-list vocab nil))
                        (insert "\n\n"))
                    (insert "  [No vocabulary extracted]\n\n"))))

              ;; Grammar Analysis (Bialek)
              (insert "GRAMMATICAL ANALYSIS (Bialek):\n")
              (tibetan-insert-separator)
              (if grammar
                  (dolist (a grammar)
                    (let ((particle (nth 0 a))
                          (word (nth 1 a))
                          (type (nth 2 a))
                          (function (nth 3 a))
                          (trans-guide (nth 4 a))
                          (reference (nth 5 a)))
                      (insert (format "  • %s in '%s'\n" particle word))
                      (insert (format "    TYPE: %s\n" type))
                      (insert (format "    FUNCTION: %s\n" function))
                      (insert (format "    TRANSLATION: %s\n" trans-guide))
                      (insert (format "    REFERENCE: %s\n\n" reference))))
                (insert "  [No grammatical markers detected]\n"))
            (insert "\n")

            ;; Verb Analysis (Hill 2010)
            (when verbs
              (insert "VERB CLASSIFICATION (Hill 2010):\n")
              (tibetan-insert-separator)
              (dolist (verb verbs)
                (let ((lemma (alist-get 'lemma verb))
                      (present (or (alist-get 'present_stem verb) "—"))
                      (past (or (alist-get 'past_stem verb) "—"))
                      (future (or (alist-get 'future_stem verb) "—"))
                      (imperative (or (alist-get 'imperative_stem verb) "—"))
                      (vol (or (alist-get 'volitionality verb) "?"))
                      (trans (or (alist-get 'transitivity verb) "?"))
                      (frame (or (alist-get 'case_frame verb) "?"))
                      (class (or (alist-get 'indigenous_class verb) "?"))
                      (meaning (alist-get 'meaning verb)))
                  (insert (format "  • %s" lemma))
                  (when meaning (insert (format " - %s" meaning)))
                  (insert "\n")
                  (insert (format "    STEMS: %s / %s / %s / %s\n" present past future imperative))
                  (insert (format "    CLASSIFICATION: %s, %s, %s\n" vol trans frame))
                  (insert (format "    TIBETAN CLASS: %s\n\n"
                                 (cond
                                  ((string= class "tha_dad_pa") "ཐ་དད་པ་ (transitive)")
                                  ((string= class "tha_mi_dad_pa") "ཐ་མི་དད་པ་ (intransitive)")
                                  (t "—"))))))
              (insert "\n"))

            ;; Translation Suggestion
            (insert "SUGGESTED TRANSLATION:\n")
            (tibetan-insert-separator)
            (if suggestion
                (insert suggestion "\n\n")
              (insert "[Generate translation with full analysis]\n\n"))

            ;; Detailed Vocabulary - full dictionary entries at the end
            (insert "DETAILED VOCABULARY:\n")
            (tibetan-insert-separator)
            (insert "Full dictionary entries for reference:\n\n")
            (if vocab
                (progn
                  (insert (tibetan-vocab-format-detailed-list vocab nil))
                  (insert "\n\n"))
              (insert "  [No vocabulary]\n\n"))

            (insert "[Press q to close]\n")

            (goto-char (point-min))
            (view-mode 1)))

          ;; Display: Create or update analysis window
          ;; In auto-mode: preserve existing window layout (don't delete workspace!)
          ;; In manual mode: create clean split
          (let* ((analysis-window (get-buffer-window "*Segment Info*"))
                 (source-window (selected-window)))
          (if analysis-window
              ;; Analysis window already exists - just update it (preserves workspace!)
              (progn
                (set-window-buffer analysis-window buffer)
                (select-window source-window))
            ;; No analysis window - create new layout
            (progn
              ;; Only delete other windows if NOT in workspace mode
              (unless (get-buffer-window "*Sentence Workspace*")
                (delete-other-windows))
              ;; Split with explicit parameters
              (let ((new-window (split-window source-window nil 'right)))
                ;; Show analysis buffer in the NEW RIGHT window
                (set-window-buffer new-window buffer)
                ;; Keep focus on SOURCE window (left)
                (select-window source-window)))))

        (message "Segment %s - Analysis on right" seg-id))))))

;; ============================================================================
;; AUTO-ANALYSIS MODE
;; ============================================================================

(defvar tibetan-auto-mode nil
  "Non-nil if auto-analysis mode is enabled.
Auto-analysis automatically updates segment analysis as you navigate.")

(defvar tibetan-auto-last-segment nil
  "Last segment ID analyzed in auto mode, to avoid redundant updates.")

(defun tibetan-auto-update ()
  "Auto-update analysis when in auto-analysis mode.
Called by post-command-hook. Uses persistent analysis (C-c u A)."
  (when tibetan-auto-mode
    ;; Only run in org-mode buffers to avoid overhead
    (when (derived-mode-p 'org-mode)
      (condition-case nil
          (let* ((seg-data (tibetan-get-current-segment-any-format))
                 (seg-id (car seg-data)))
            ;; Only update if we moved to a different segment
            (when (and seg-id (not (equal seg-id tibetan-auto-last-segment)))
              (setq tibetan-auto-last-segment seg-id)
              ;; Use persistent analysis (C-c u A) instead of simple segment-info
              (when (fboundp 'tibetan-open-segment-analysis)
                (tibetan-open-segment-analysis))))
        (error nil)))))

(defun tibetan-toggle-auto ()
  "Toggle auto-analysis mode.
When enabled, persistent analysis (C-c u A) updates automatically as you navigate.
Bound to C-c u E."
  (interactive)
  (if tibetan-auto-mode
      (progn
        (remove-hook 'post-command-hook 'tibetan-auto-update t)
        (setq tibetan-auto-mode nil)
        (setq tibetan-auto-last-segment nil)
        (message "Auto-analysis DISABLED"))
    (progn
      (add-hook 'post-command-hook 'tibetan-auto-update nil t)
      (setq tibetan-auto-mode t)
      (setq tibetan-auto-last-segment nil)
      ;; Open persistent analysis for current segment
      (when (fboundp 'tibetan-open-segment-analysis)
        (condition-case nil
            (tibetan-open-segment-analysis)
          (error nil)))
      (message "Auto-analysis ENABLED (C-c u A mode)"))))

;; Alias for convenience
(defalias 'tibetan-enable-auto-analysis 'tibetan-toggle-auto)

(provide 'tibetan-classroom)
;;; tibetan-classroom.el ends here
