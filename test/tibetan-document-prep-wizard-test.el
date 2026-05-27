;;; tibetan-document-prep-wizard-test.el --- §5.27 Phase 6 — Wizard orchestrator -*- lexical-binding: t -*-

;;; Commentary:
;; ERT specs for `doc-prep/tibetan-document-prep-wizard.el'.
;;
;; Interactive prompts (`read-file-name', `completing-read', etc.)
;; are stubbed via `cl-letf' so the wizard's state-threading and
;; header-write side effects are exercised non-interactively.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../doc-prep" dir)))

(require 'tibetan-document-genres)
(require 'tibetan-document-prep-claude)
(require 'tibetan-document-prep-wizard)

;; ============================================================================
;; ROUTE READER
;; ============================================================================

(ert-deftest tibetan-document-prep-wizard-route-reader-returns-key ()
  "Route reader runs `completing-read' over the LABELS and returns
the corresponding KEY symbol from the routes alist."
  (cl-letf (((symbol-function 'completing-read)
             (lambda (&rest _)
               "Wylie file (.org with Wylie body) — converts via pyewts")))
    (should (eq 'wylie (tibetan-document-prep-wizard--read-route)))))

(ert-deftest tibetan-document-prep-wizard-route-reader-existing-key ()
  "Route alist exposes `existing' for resume runs."
  (cl-letf (((symbol-function 'completing-read)
             (lambda (&rest _)
               "Existing file — resume / re-run wizard on a prepared source")))
    (should (eq 'existing (tibetan-document-prep-wizard--read-route)))))

;; ============================================================================
;; HEADER WRITE HELPER
;; ============================================================================

(ert-deftest tibetan-document-prep-wizard-write-header-creates-or-replaces ()
  "Wizard's header-write helper writes the header to the source
file:  first call inserts after `#+TITLE:', second replaces in
place — no duplicates."
  (let ((dir (make-temp-file "wiz-hdr-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n\n* Tibetan Text\nx\n"))
          (tibetan-document-prep-wizard--write-header
           src "TIBETAN_TARGET_LANG" "de")
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p "#\\+TIBETAN_TARGET_LANG: de" out)))
          ;; Second write replaces in place.
          (tibetan-document-prep-wizard--write-header
           src "TIBETAN_TARGET_LANG" "en")
          (let ((out (with-temp-buffer (insert-file-contents src)
                                       (buffer-string))))
            (should (string-match-p "#\\+TIBETAN_TARGET_LANG: en" out))
            (should-not (string-match-p "#\\+TIBETAN_TARGET_LANG: de" out))))
      (delete-directory dir t))))

;; ============================================================================
;; INDIVIDUAL STEPS
;; ============================================================================

(ert-deftest tibetan-document-prep-wizard-target-lang-writes-and-returns ()
  "Target-lang step:  user picks `en' → header is written, value
returned."
  (let ((dir (make-temp-file "wiz-lang-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _) "en")))
            (let ((ret
                   (tibetan-document-prep-wizard--read-target-lang src)))
              (should (equal "en" ret))
              (let ((out (with-temp-buffer (insert-file-contents src)
                                           (buffer-string))))
                (should (string-match-p
                         "#\\+TIBETAN_TARGET_LANG: en" out))))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-genre-uses-claude-default ()
  "Genre step consults the buffer-local Claude suggestion (when
present) as the completing-read default — Carsten's preferred
\"async pre-fill\" behaviour."
  (let ((dir (make-temp-file "wiz-genre-" t)))
    (unwind-protect
        (let* ((src (expand-file-name "source.org" dir))
               (buf nil)
               captured-default)
          (with-temp-file src (insert "#+TITLE: T\n"))
          (setq buf (find-file-noselect src))
          (with-current-buffer buf
            (setq tibetan-document-prep--claude-suggestions
                  '(:genre mgur :author nil :context nil)))
          (unwind-protect
              (cl-letf
                  (((symbol-function 'completing-read)
                    (lambda (_p _coll _pred _req _init _hist default)
                      (setq captured-default default)
                      ;; Whatever the wizard suggests, the user picks.
                      default)))
                (tibetan-document-prep-wizard--read-genre src)
                (should (equal "mGur — yogin's song / spiritual verse"
                               captured-default))
                (let ((out (with-temp-buffer (insert-file-contents src)
                                             (buffer-string))))
                  (should (string-match-p
                           "#\\+TIBETAN_TEXT_TYPE: mgur" out))))
            (kill-buffer buf)))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-genre-falls-back-to-classical ()
  "Without Claude suggestion or existing header, the genre default
falls through to `classical'."
  (let ((dir (make-temp-file "wiz-classical-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir))
              captured-default)
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_p _coll _pred _req _init _hist default)
                       (setq captured-default default)
                       default)))
            (tibetan-document-prep-wizard--read-genre src)
            (should (equal "Classical prose (fallback)" captured-default))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-author-step-writes-when-given ()
  "Author step writes `#+TIBETAN_AUTHOR:' when user supplies a
non-empty value."
  (let ((dir (make-temp-file "wiz-author-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'read-string)
                     (lambda (&rest _) "Milarepa")))
            (tibetan-document-prep-wizard--read-author src)
            (let ((out (with-temp-buffer (insert-file-contents src)
                                         (buffer-string))))
              (should (string-match-p
                       "#\\+TIBETAN_AUTHOR: Milarepa" out)))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-author-step-skips-on-empty ()
  "Empty author input → header is NOT written (no `#+TIBETAN_AUTHOR:'
line appears)."
  (let ((dir (make-temp-file "wiz-noauthor-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "")))
            (tibetan-document-prep-wizard--read-author src)
            (let ((out (with-temp-buffer (insert-file-contents src)
                                         (buffer-string))))
              (should-not (string-match-p "#\\+TIBETAN_AUTHOR" out)))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-class-mode-writes-grammar ()
  "Class-mode step picks `grammar' → `#+TIBETAN_CLASS_MODE: grammar'
is written, symbol returned."
  (let ((dir (make-temp-file "wiz-cls-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _)
                       "grammar  — segment-focused (Tibetisch III/IV)")))
            (let ((ret
                   (tibetan-document-prep-wizard--read-class-mode src)))
              (should (eq 'grammar ret))
              (let ((out (with-temp-buffer (insert-file-contents src)
                                           (buffer-string))))
                (should (string-match-p
                         "#\\+TIBETAN_CLASS_MODE: grammar" out))))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-class-mode-writes-reading ()
  "Class-mode step picks `reading' → `#+TIBETAN_CLASS_MODE: reading'."
  (let ((dir (make-temp-file "wiz-cls2-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _)
                       "reading  — sentence-focused (reading classes)")))
            (should (eq 'reading
                        (tibetan-document-prep-wizard--read-class-mode src)))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-sentence-detail-writes-detailed ()
  "Sentence-detail step picks `detailed' → `#+TIBETAN_SENTENCE_DETAIL:
detailed' is written."
  (let ((dir (make-temp-file "wiz-detail-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (&rest _)
                       "detailed   — full §5.21 segment layout per sentence")))
            (let ((ret
                   (tibetan-document-prep-wizard--read-sentence-detail
                    src)))
              (should (eq 'detailed ret))
              (let ((out (with-temp-buffer (insert-file-contents src)
                                           (buffer-string))))
                (should (string-match-p
                         "#\\+TIBETAN_SENTENCE_DETAIL: detailed" out))))))
      (delete-directory dir t))))

;; ============================================================================
;; RESOURCES SCAFFOLD
;; ============================================================================

(ert-deftest tibetan-document-prep-wizard-scaffold-resources-creates-vocab ()
  "Resources scaffold creates `Resources/vocabulary.org' next to
SOURCE-FILE with the canonical org-table template."
  (let ((dir (make-temp-file "wiz-res-" t)))
    (unwind-protect
        (let ((src (expand-file-name "source.org" dir)))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (let ((vocab
                 (tibetan-document-prep-wizard--scaffold-resources src)))
            (should (file-exists-p vocab))
            (should (string-match-p "Resources/vocabulary\\.org\\'" vocab))
            (let ((content (with-temp-buffer (insert-file-contents vocab)
                                             (buffer-string))))
              (should (string-match-p "| Term | Definition |" content)))))
      (delete-directory dir t))))

(ert-deftest tibetan-document-prep-wizard-scaffold-resources-idempotent ()
  "Existing `Resources/vocabulary.org' is left alone — scaffold
does NOT overwrite user content on a re-run."
  (let ((dir (make-temp-file "wiz-res2-" t)))
    (unwind-protect
        (let* ((src (expand-file-name "source.org" dir))
               (res-dir (expand-file-name "Resources" dir))
               (vocab (expand-file-name "vocabulary.org" res-dir))
               (custom-content "* Custom\n| my-term | meaning |\n"))
          (with-temp-file src (insert "#+TITLE: T\n"))
          (make-directory res-dir t)
          (with-temp-file vocab (insert custom-content))
          (tibetan-document-prep-wizard--scaffold-resources src)
          (let ((after (with-temp-buffer (insert-file-contents vocab)
                                         (buffer-string))))
            (should (equal custom-content after))))
      (delete-directory dir t))))

;; ============================================================================
;; SUMMARY FORMATTING
;; ============================================================================

(ert-deftest tibetan-document-prep-wizard-summary-formats-all-fields ()
  "Summary renderer mentions source file, route, target-lang, genre,
author, context count, class mode, and the apply-Claude command."
  (let* ((state (list :source-file "/tmp/foo.org"
                      :input-route 'wylie
                      :target-lang "de"
                      :genre 'mgur
                      :author "Milarepa"
                      :context '("ctx1" "ctx2")
                      :class-mode 'reading
                      :sentence-detail 'detailed
                      :vocabulary-file "/tmp/Resources/vocabulary.org"
                      :claude-fired t))
         (txt (tibetan-document-prep-wizard--format-summary state)))
    (should (string-match-p "/tmp/foo\\.org" txt))
    (should (string-match-p "Input route:.*wylie" txt))
    (should (string-match-p "Target language:.*de" txt))
    (should (string-match-p "Genre:.*mgur" txt))
    (should (string-match-p "Author:.*Milarepa" txt))
    (should (string-match-p "Context lines:.*2" txt))
    (should (string-match-p "Class mode:.*reading" txt))
    (should (string-match-p "Sentence detail:.*detailed" txt))
    (should (string-match-p "Resources/vocabulary\\.org" txt))
    (should (string-match-p
             "tibetan-document-prep-apply-claude-suggestions" txt))))

(ert-deftest tibetan-document-prep-wizard-summary-skips-detail-in-grammar ()
  "Grammar class-mode → summary OMITS the `Sentence detail' line
\(it's only meaningful in reading mode)."
  (let* ((state (list :source-file "/tmp/foo.org"
                      :input-route 'wylie
                      :target-lang "de"
                      :genre 'classical
                      :author nil
                      :context '()
                      :class-mode 'grammar
                      :sentence-detail nil
                      :claude-fired t))
         (txt (tibetan-document-prep-wizard--format-summary state)))
    (should-not (string-match-p "Sentence detail:" txt))))

;; ============================================================================
;; ROUTES TAXONOMY
;; ============================================================================

(ert-deftest tibetan-document-prep-wizard-routes-cover-four-inputs ()
  "Four input routes are registered:  wylie / unicode / existing / ocr."
  (let ((keys (mapcar #'cdr tibetan-document-prep-wizard--routes)))
    (should (= 4 (length keys)))
    (should (memq 'wylie keys))
    (should (memq 'unicode keys))
    (should (memq 'existing keys))
    (should (memq 'ocr keys))))

(provide 'tibetan-document-prep-wizard-test)
;;; tibetan-document-prep-wizard-test.el ends here
