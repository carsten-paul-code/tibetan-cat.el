;;; cat-utils.el --- Shared utilities for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Core utility functions shared across all CAT modules.
;; This module consolidates common functionality:
;; - Safe string operations for multi-byte Tibetan text
;; - Text segmentation helpers
;; - Display formatting utilities
;; - Particle pattern definitions

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; SAFE STRING OPERATIONS (for multi-byte Tibetan text)
;; ============================================================================

(defun cat-safe-substring (str start &optional end)
  "Safely extract substring from STR between START and END.
Handles multi-byte Tibetan characters correctly.
Returns empty string if indices are out of range or invalid."
  (condition-case nil
      (let* ((len (length str))
             (s (max 0 (min start len)))
             (e (if end (max s (min end len)) len)))
        (if (and (<= 0 s) (<= s e) (<= e len))
            (substring str s e)
          ""))
    (error "")))

(defun cat-strip-particle-suffix (word particle)
  "Strip PARTICLE suffix from WORD, returning the root.
Uses safe substring for multi-byte handling."
  (if (string-suffix-p particle word)
      (cat-safe-substring word 0 (- (length word) (length particle)))
    word))

;; ============================================================================
;; TEXT SEGMENTATION
;; ============================================================================

(defun cat-segment-text (text)
  "Segment TEXT into tsheg-delimited units.
Returns list of word strings with punctuation removed."
  (let ((cleaned (replace-regexp-in-string "[།༎༏༐༑༔]" "" text)))
    (split-string cleaned "་" t)))

(defun cat-clean-tibetan-text (text)
  "Clean Tibetan TEXT by normalizing punctuation and whitespace."
  (let ((result text))
    ;; Normalize double tshegs
    (setq result (replace-regexp-in-string "་་" "་" result))
    ;; Remove trailing/leading whitespace
    (string-trim result)))

;; ============================================================================
;; PARTICLE PATTERN DEFINITIONS (shared across grammar modules)
;; ============================================================================

(defconst cat-ergative-particles
  '("ཀྱིས" "གྱིས" "གིས" "འིས" "ཡིས" "ས")
  "Ergative case particles marking the agent of transitive verbs.")

(defconst cat-genitive-particles
  '("ཀྱི" "གྱི" "གི" "འི" "ཡི")
  "Genitive case particles marking possession or modification.")

(defconst cat-dative-particles
  '("ལ" "ར" "དུ" "ཏུ" "སུ" "རུ")
  "Dative/allative case particles marking goal, recipient, or direction.")

(defconst cat-ablative-particles
  '("ནས" "ལས")
  "Ablative case particles marking source or starting point.")

(defconst cat-locative-particles
  '("ན")
  "Locative case particles marking location or condition.")

(defconst cat-converb-particles
  '("ནས" "སྟེ" "ཏེ" "དེ" "ཅིང" "ཞིང" "ཤིང")
  "Converb particles connecting clauses.")

(defconst cat-causal-particles
  '("པས" "བས")
  "Causal converb particles marking cause or reason.")

(defconst cat-nominalizer-particles
  '("པ" "བ" "པོ" "བོ" "མ" "མོ")
  "Nominalizer particles creating nouns from verbs.")

(defconst cat-concessive-particles
  '("ཀྱང" "ཡང" "འང")
  "Concessive particles meaning 'even', 'also', or 'though'.")

(defconst cat-topic-particles
  '("ནི")
  "Topic marker particles.")

(defconst cat-sentence-final-particles
  '("སོ" "ཏོ" "ནོ" "དོ" "རོ" "འོ" "ངོ")
  "Sentence-final particles.")

(defconst cat-all-case-particles
  (append cat-ergative-particles
          cat-genitive-particles
          cat-dative-particles
          cat-ablative-particles
          cat-locative-particles)
  "All case-marking particles combined.")

(defconst cat-all-particles
  (append cat-all-case-particles
          cat-converb-particles
          cat-causal-particles
          cat-nominalizer-particles
          cat-concessive-particles
          cat-topic-particles
          cat-sentence-final-particles)
  "All grammatical particles combined.")

;; ============================================================================
;; PARTICLE DETECTION HELPERS
;; ============================================================================

(defun cat-detect-particle-suffix (word particle-list)
  "Check if WORD ends with any particle in PARTICLE-LIST.
Returns (particle . root) cons cell if found, nil otherwise."
  (cl-loop for particle in particle-list
           when (string-suffix-p particle word)
           return (cons particle (cat-strip-particle-suffix word particle))))

(defun cat-detect-ergative (word)
  "Detect ergative particle suffix in WORD."
  (cat-detect-particle-suffix word cat-ergative-particles))

(defun cat-detect-genitive (word)
  "Detect genitive particle suffix in WORD."
  (cat-detect-particle-suffix word cat-genitive-particles))

(defun cat-detect-dative (word)
  "Detect dative/allative particle suffix in WORD."
  (cat-detect-particle-suffix word cat-dative-particles))

(defun cat-detect-ablative (word)
  "Detect ablative particle suffix in WORD."
  (cat-detect-particle-suffix word cat-ablative-particles))

(defun cat-detect-converb (word)
  "Detect converb particle suffix in WORD."
  (cat-detect-particle-suffix word cat-converb-particles))

(defun cat-detect-nominalizer (word)
  "Detect nominalizer particle suffix in WORD."
  (cat-detect-particle-suffix word cat-nominalizer-particles))

;; ============================================================================
;; DISPLAY FORMATTING
;; ============================================================================

(defconst cat-separator-line
  "────────────────────────────────────────────────────────────────"
  "Standard separator line for display output.")

(defun cat-insert-separator ()
  "Insert a standard separator line."
  (insert cat-separator-line "\n"))

(defun cat-insert-header (title)
  "Insert a formatted section header with TITLE."
  (insert (format "%s:\n" (upcase title)))
  (cat-insert-separator))

(defun cat-insert-box-header (title)
  "Insert a boxed header with TITLE."
  (insert "╔══════════════════════════════════════════════════════════════╗\n")
  (insert (format "║         %-54s ║\n" title))
  (insert "╚══════════════════════════════════════════════════════════════╝\n\n"))

;; ============================================================================
;; BUFFER/WINDOW MANAGEMENT
;; ============================================================================

(defun cat-get-or-create-buffer (name)
  "Get or create buffer with NAME, returning the buffer."
  (get-buffer-create name))

(defun cat-display-in-side-window (buffer &optional source-window)
  "Display BUFFER in a side window, keeping SOURCE-WINDOW selected."
  (let ((source (or source-window (selected-window))))
    (if-let ((existing (get-buffer-window buffer)))
        (progn
          (set-window-buffer existing buffer)
          (select-window source))
      (let ((new-window (split-window source nil 'right)))
        (set-window-buffer new-window buffer)
        (select-window source)))))

(defun cat-close-side-window (buffer-name)
  "Close side window displaying BUFFER-NAME if it exists."
  (when-let ((window (get-buffer-window buffer-name)))
    (delete-window window)))

;; ============================================================================
;; VOCABULARY LOOKUP INTERFACE
;; ============================================================================

(defun cat-lookup-word (word)
  "Look up WORD in available vocabulary sources.
Returns meaning string or nil."
  (when (boundp 'tibetan-comprehensive-vocabulary)
    (gethash word tibetan-comprehensive-vocabulary)))

(defun cat-lookup-with-particle-strip (word)
  "Look up WORD, trying with particles stripped if initial lookup fails."
  (or (cat-lookup-word word)
      ;; Try stripping common particles
      (cl-loop for particle in cat-all-particles
               when (string-suffix-p particle word)
               thereis (cat-lookup-word (cat-strip-particle-suffix word particle)))))

;; ============================================================================
;; TEXT TYPE DETECTION
;; ============================================================================

(defun cat-get-text-context ()
  "Get the text context from buffer-local variable or file header.
Returns context symbol or 'classical-prose as default."
  (or (when (boundp 'tibetan-text-context) tibetan-text-context)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+TIBETAN_CONTEXT:\\s-*\\(.+\\)$" nil t)
          (intern (string-trim (match-string 1)))))
      'classical-prose))

(defun cat-madhyamaka-context-p ()
  "Check if current context is Madhyamaka-related."
  (let ((ctx (cat-get-text-context)))
    (memq ctx '(bhutan-kagyu-madhyamaka gelug-madhyamaka madhyamaka))))

(defun cat-verse-context-p ()
  "Check if current context is verse-related."
  (let ((ctx (cat-get-text-context)))
    (or (memq ctx '(bhutan-kagyu-madhyamaka gelug-madhyamaka))
        (string-match-p "verse" (symbol-name ctx)))))

(provide 'cat-utils)
;;; cat-utils.el ends here
