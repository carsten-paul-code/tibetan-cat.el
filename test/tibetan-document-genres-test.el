;;; tibetan-document-genres-test.el --- §5.27 Phase 3 — Genre taxonomy -*- lexical-binding: t -*-

;;; Commentary:
;; ERT specs for `doc-prep/tibetan-document-genres.el' — the
;; canonical 14-entry genre taxonomy + completing-read helper.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../doc-prep" dir)))

(require 'tibetan-document-genres)

;; ============================================================================
;; TAXONOMY SHAPE
;; ============================================================================

(ert-deftest tibetan-document-genres-taxonomy-non-empty ()
  "Taxonomy is bound, non-empty, and an alist (defensive against
file load failures or post-merge collapse)."
  (should (boundp 'tibetan-document-genre-taxonomy))
  (should (listp tibetan-document-genre-taxonomy))
  (should (> (length tibetan-document-genre-taxonomy) 0)))

(ert-deftest tibetan-document-genres-taxonomy-contains-twelve-genres ()
  "Taxonomy carries the full 12 traditional Tibetan genres from
the §5.27 spec PLUS the two legacy fallbacks `classical' and
`madhyamaka-verse' → 14 total entries."
  (let ((keys (tibetan-document-genres-keys)))
    (should (= 14 (length keys)))
    ;; 12 traditional genres.
    (dolist (genre '(rnam-thar lam-rim mgur mdo rgyud bstan-bcos
                     snyan-ngag gtam-rgyud grel-pa tika
                     gter-ma gdams-ngag))
      (should (memq genre keys)))
    ;; Legacy fallbacks (backwards-compat with the pre-§5.27 list).
    (should (memq 'classical keys))
    (should (memq 'madhyamaka-verse keys))))

(ert-deftest tibetan-document-genres-every-entry-has-required-plist-keys ()
  "Every taxonomy entry has all four required plist keys
\(`:tibetan', `:label', `:description', `:claude-hint').  Guards
against an under-specified entry slipping in and crashing the
wizard's completing-read or the Claude prompt builder."
  (dolist (entry tibetan-document-genre-taxonomy)
    (let ((plist (cdr entry))
          (key (car entry)))
      (should (symbolp key))
      (should (stringp (plist-get plist :tibetan)))
      (should (stringp (plist-get plist :label)))
      (should (stringp (plist-get plist :description)))
      (should (stringp (plist-get plist :claude-hint)))
      ;; Label and hint must be non-empty.  Tibetan name MAY be
      ;; empty for the legacy fallback keys.
      (should (not (string-empty-p (plist-get plist :label))))
      (should (not (string-empty-p (plist-get plist :description))))
      (should (not (string-empty-p (plist-get plist :claude-hint)))))))

(ert-deftest tibetan-document-genres-keys-are-unique ()
  "No duplicate KEY in the taxonomy (assq would silently pick the
first match and shadow a later definition)."
  (let ((keys (tibetan-document-genres-keys)))
    (should (= (length keys)
               (length (cl-remove-duplicates keys :test #'eq))))))

(ert-deftest tibetan-document-genres-labels-are-unique ()
  "No duplicate `:label' string in the taxonomy (otherwise
completing-read would silently collapse two genres into one
choice)."
  (let ((labels (tibetan-document-genres-labels)))
    (should (= (length labels)
               (length (cl-remove-duplicates labels :test #'equal))))))

;; ============================================================================
;; ACCESSORS
;; ============================================================================

(ert-deftest tibetan-document-genres-label-for-known-key ()
  "`label-for' returns the registered display label for a known
KEY."
  (should (equal "rNam thar — spiritual biography"
                 (tibetan-document-genres-label-for 'rnam-thar)))
  (should (equal "mGur — yogin's song / spiritual verse"
                 (tibetan-document-genres-label-for 'mgur))))

(ert-deftest tibetan-document-genres-label-for-unknown-key-is-nil ()
  "Unknown KEY → nil (the wizard handles nil gracefully)."
  (should-not (tibetan-document-genres-label-for 'no-such-genre)))

(ert-deftest tibetan-document-genres-claude-hint-for-known-key ()
  "`claude-hint-for' returns a non-empty hint for each registered
genre — Claude prompt builders depend on this."
  (dolist (key (tibetan-document-genres-keys))
    (let ((hint (tibetan-document-genres-claude-hint-for key)))
      (should (stringp hint))
      (should (not (string-empty-p hint))))))

(ert-deftest tibetan-document-genres-claude-hint-for-unknown-is-nil ()
  "Unknown KEY → nil (caller falls back to no hint)."
  (should-not (tibetan-document-genres-claude-hint-for 'foo-bar)))

(ert-deftest tibetan-document-genres-tibetan-for-twelve-genres ()
  "Each of the 12 traditional genres has its Wylie name in
`:tibetan';  the 2 legacy fallbacks carry the empty string."
  (should (equal "rnam thar"
                 (tibetan-document-genres-tibetan-for 'rnam-thar)))
  (should (equal "lam rim"
                 (tibetan-document-genres-tibetan-for 'lam-rim)))
  (should (equal "mgur" (tibetan-document-genres-tibetan-for 'mgur)))
  (should (equal "" (tibetan-document-genres-tibetan-for 'classical)))
  (should (equal "" (tibetan-document-genres-tibetan-for 'madhyamaka-verse))))

(ert-deftest tibetan-document-genres-description-for-each-key ()
  "Every key has a non-empty description (shown alongside the
label in vertico marginalia)."
  (dolist (key (tibetan-document-genres-keys))
    (let ((desc (tibetan-document-genres-description-for key)))
      (should (stringp desc))
      (should (not (string-empty-p desc))))))

;; ============================================================================
;; READER — completing-read driver
;; ============================================================================

(ert-deftest tibetan-document-genres-read-returns-key-symbol ()
  "Reader stubs out `completing-read' to pick a known label;
return value is the corresponding KEY symbol (NOT the label)."
  (cl-letf (((symbol-function 'completing-read)
             (lambda (&rest _) "rNam thar — spiritual biography")))
    (should (eq 'rnam-thar (tibetan-document-genres-read)))))

(ert-deftest tibetan-document-genres-read-uses-default-label ()
  "DEFAULT (a KEY symbol) is converted to its label and threaded
through to `completing-read' as the default selection."
  (let (captured-default)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt _collection _pred _require _initial _hist default)
                 (setq captured-default default)
                 "rNam thar — spiritual biography")))
      (tibetan-document-genres-read 'mgur)
      (should (equal "mGur — yogin's song / spiritual verse"
                     captured-default)))))

(ert-deftest tibetan-document-genres-read-nil-default-no-preselection ()
  "DEFAULT = nil → completing-read receives nil for the default
arg (no preselection;  user gets a clean prompt)."
  (let (captured-default)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt _collection _pred _require _initial _hist default)
                 (setq captured-default default)
                 "Classical prose (fallback)")))
      (tibetan-document-genres-read)
      (should-not captured-default))))

(ert-deftest tibetan-document-genres-read-unknown-default-falls-through ()
  "Unknown DEFAULT KEY → label lookup yields nil → no preselection,
no error."
  (let (captured-default)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt _collection _pred _require _initial _hist default)
                 (setq captured-default default)
                 "Classical prose (fallback)")))
      (tibetan-document-genres-read 'no-such-genre)
      (should-not captured-default))))

(ert-deftest tibetan-document-genres-read-custom-prompt ()
  "PROMPT argument is threaded through to `completing-read'."
  (let (captured-prompt)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (prompt &rest _)
                 (setq captured-prompt prompt)
                 "Classical prose (fallback)")))
      (tibetan-document-genres-read 'classical "Pick a genre, please: ")
      (should (equal "Pick a genre, please: " captured-prompt)))))

(provide 'tibetan-document-genres-test)
;;; tibetan-document-genres-test.el ends here
