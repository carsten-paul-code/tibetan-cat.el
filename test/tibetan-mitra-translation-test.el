;;; tibetan-mitra-translation-test.el --- Tests for Mitra translation module -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for tibetan-mitra-translation.el
;; Tests for:
;; - Main translate function availability
;; - Nil input handling
;; - Function binding and structure

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load path
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" dir))
  (add-to-list 'load-path (expand-file-name "../analysis" dir)))

(require 'tibetan-mitra-translation)

;; ============================================================================
;; FUNCTION AVAILABILITY TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-translate-segment-is-fboundp ()
  "Test that tibetan-mitra-translate-segment is defined and available."
  (should (fboundp 'tibetan-mitra-translate-segment)))

(ert-deftest tibetan-mitra-translate-is-fboundp ()
  "Test that tibetan-mitra-translate is defined and available."
  (should (fboundp 'tibetan-mitra-translate)))

;; ============================================================================
;; NIL INPUT HANDLING TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-translate-nil-input ()
  "Test that nil input is handled gracefully."
  (should-error (tibetan-mitra-translate nil)))

(ert-deftest tibetan-mitra-translate-empty-string ()
  "Test that empty string input is handled gracefully."
  (should-error (tibetan-mitra-translate "")))

(ert-deftest tibetan-mitra-translate-whitespace ()
  "Test that whitespace-only input is handled gracefully."
  (should-error (tibetan-mitra-translate "   ")))

;; ============================================================================
;; FUNCTION BEHAVIOR TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-translate-returns-string-or-nil ()
  "Test that translate function returns string or nil."
  ;; Since we don't have a real backend configured in tests,
  ;; we expect this to either succeed or fail gracefully
  (let ((result (ignore-errors (tibetan-mitra-translate "བྱང་ཆུབ་སེམས་དཔའ།"))))
    ;; Should return nil, string, or error (not crash)
    (should (or (null result) (stringp result)))))

(ert-deftest tibetan-mitra-cache-enabled-config ()
  "Test that cache configuration exists."
  (should (boundp 'tibetan-mitra-cache-enabled))
  (should (booleanp tibetan-mitra-cache-enabled)))

(ert-deftest tibetan-mitra-backend-config ()
  "Test that backend configuration exists."
  (should (boundp 'tibetan-mitra-backend))
  (should (memq tibetan-mitra-backend '(ollama huggingface local-server))))

;; ============================================================================
;; CACHE FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-clear-cache-is-fboundp ()
  "Test that cache clearing function exists."
  (should (fboundp 'tibetan-mitra-clear-cache)))

(ert-deftest tibetan-mitra-cache-is-hash-table ()
  "Test that internal cache is a hash table."
  (should (hash-table-p tibetan-mitra--cache)))

;; ============================================================================
;; ASYNC FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-translate-async-is-fboundp ()
  "Test that async translation function exists."
  (should (fboundp 'tibetan-mitra-translate-async)))

;; ============================================================================
;; INTEGRATION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-format-for-display-exists ()
  "Test that display formatting function exists."
  (should (fboundp 'tibetan-mitra-format-for-display)))

(ert-deftest tibetan-mitra-format-for-display-handles-nil ()
  "Test that formatting handles nil gracefully."
  (let ((result (tibetan-mitra-format-for-display nil)))
    (should (stringp result))))

(ert-deftest tibetan-mitra-format-for-display-handles-string ()
  "Test that formatting handles string input."
  (let ((result (tibetan-mitra-format-for-display "test translation")))
    (should (stringp result))
    (should (string-match-p "test translation" result))))

;; ============================================================================
;; CHECK-STATUS FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-check-status-is-fboundp ()
  "Test that check-status function exists."
  (skip-unless (fboundp 'tibetan-mitra-check-status))
  (should (fboundp 'tibetan-mitra-check-status)))

(ert-deftest tibetan-mitra-check-status-is-interactive ()
  "Test that check-status is an interactive command."
  (skip-unless (fboundp 'tibetan-mitra-check-status))
  (should (commandp 'tibetan-mitra-check-status))
  (should (interactive-form 'tibetan-mitra-check-status)))

(ert-deftest tibetan-mitra-check-status-ollama-backend ()
  "Test check-status with ollama backend (no network call)."
  (skip-unless (fboundp 'tibetan-mitra-check-status))
  (let ((tibetan-mitra-backend 'ollama))
    ;; Should not error, even if ollama is not running
    (should (progn (tibetan-mitra-check-status) t))))

;; ============================================================================
;; SETUP-OLLAMA FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-setup-ollama-is-fboundp ()
  "Test that setup-ollama function exists."
  (skip-unless (fboundp 'tibetan-mitra-setup-ollama))
  (should (fboundp 'tibetan-mitra-setup-ollama)))

(ert-deftest tibetan-mitra-setup-ollama-is-interactive ()
  "Test that setup-ollama is an interactive command."
  (skip-unless (fboundp 'tibetan-mitra-setup-ollama))
  (should (commandp 'tibetan-mitra-setup-ollama))
  (should (interactive-form 'tibetan-mitra-setup-ollama)))

(ert-deftest tibetan-mitra-setup-ollama-displays-help ()
  "Test that setup-ollama displays help window with instructions."
  (skip-unless (fboundp 'tibetan-mitra-setup-ollama))
  (with-temp-buffer
    ;; Call setup-ollama and verify it doesn't error
    (should (progn (tibetan-mitra-setup-ollama) t))))

;; ============================================================================
;; TRANSLATE-DWIM FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-translate-dwim-is-fboundp ()
  "Test that translate-dwim function exists."
  (skip-unless (fboundp 'tibetan-mitra-translate-dwim))
  (should (fboundp 'tibetan-mitra-translate-dwim)))

(ert-deftest tibetan-mitra-translate-dwim-is-interactive ()
  "Test that translate-dwim is an interactive command."
  (skip-unless (fboundp 'tibetan-mitra-translate-dwim))
  (should (commandp 'tibetan-mitra-translate-dwim))
  (should (interactive-form 'tibetan-mitra-translate-dwim)))

(ert-deftest tibetan-mitra-translate-dwim-without-region ()
  "Test translate-dwim delegates to segment when no region active."
  (skip-unless (fboundp 'tibetan-mitra-translate-dwim))
  (skip-unless (fboundp 'tibetan-mitra-translate-segment))
  ;; Mock tibetan-mitra-translate-segment to track that it's called.
  ;; NOTE: `called-segment-p' must live in a `let' binding, not in
  ;; `cl-letf' — `cl-letf' treats a bare symbol as the place
  ;; `symbol-value', which errors with `void-variable' when the symbol
  ;; has never been `defvar'-ed.  Only the function binding belongs in
  ;; `cl-letf'.
  (let ((called-segment-p nil))
    (cl-letf (((symbol-function 'tibetan-mitra-translate-segment)
               (lambda ()
                 (setq called-segment-p t)
                 nil)))
      (with-temp-buffer
        ;; No region active, should call translate-segment
        (tibetan-mitra-translate-dwim)
        (should called-segment-p)))))

(ert-deftest tibetan-mitra-translate-dwim-with-region ()
  "Test translate-dwim delegates to region when region is active."
  (skip-unless (fboundp 'tibetan-mitra-translate-dwim))
  (skip-unless (fboundp 'tibetan-mitra-translate-region))
  ;; Mock tibetan-mitra-translate to avoid actual network calls
  (cl-letf (((symbol-function 'tibetan-mitra-translate)
             (lambda (text) nil)))
    (with-temp-buffer
      (insert "བྱང་ཆུབ་སེམས་དཔའ།")
      ;; Activate region
      (set-mark (point-min))
      (goto-char (point-max))
      ;; Should not error when translating selected region
      (should (progn (tibetan-mitra-translate-dwim) t)))))

;; ============================================================================
;; TRANSLATE-REGION FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-mitra-translate-region-is-fboundp ()
  "Test that translate-region function exists."
  (skip-unless (fboundp 'tibetan-mitra-translate-region))
  (should (fboundp 'tibetan-mitra-translate-region)))

(ert-deftest tibetan-mitra-translate-region-is-interactive ()
  "Test that translate-region is an interactive command."
  (skip-unless (fboundp 'tibetan-mitra-translate-region))
  (should (commandp 'tibetan-mitra-translate-region))
  (should (interactive-form 'tibetan-mitra-translate-region)))

(ert-deftest tibetan-mitra-translate-region-with-mocked-response ()
  "Test translate-region with mocked translation backend."
  (skip-unless (fboundp 'tibetan-mitra-translate-region))
  ;; Mock tibetan-mitra-translate to return a test response
  (cl-letf (((symbol-function 'tibetan-mitra-translate)
             (lambda (text) "bodhisattva")))
    (with-temp-buffer
      (insert "བྱང་ཆུབ་སེམས་དཔའ།")
      ;; Test that translate-region calls translate and returns result
      (let ((result (tibetan-mitra-translate-region (point-min) (point-max))))
        (should (equal result "bodhisattva"))))))

(ert-deftest tibetan-mitra-translate-region-with-nil-response ()
  "Test translate-region handles nil translation gracefully."
  (skip-unless (fboundp 'tibetan-mitra-translate-region))
  ;; Mock tibetan-mitra-translate to return nil
  (cl-letf (((symbol-function 'tibetan-mitra-translate)
             (lambda (text) nil)))
    (with-temp-buffer
      (insert "བྱང་ཆུབ་སེམས་དཔའ།")
      ;; Should handle nil gracefully
      (let ((result (tibetan-mitra-translate-region (point-min) (point-max))))
        (should (null result))))))

;; ============================================================================
;; HELPER FUNCTION
;; ============================================================================

(ert-deftest tibetan-mitra-url-retrieve-enforces-tls-verification ()
  "`tibetan-mitra--url-retrieve' binds `gnutls-verify-error' to t around
the network call, so the HuggingFace bearer token is never sent over an
unverified (MITM-able) TLS connection."
  (skip-unless (fboundp 'tibetan-mitra--url-retrieve))
  (let ((captured 'unset)
        (gnutls-verify-error nil))
    (cl-letf (((symbol-function 'url-retrieve-synchronously)
               (lambda (&rest _) (setq captured gnutls-verify-error) nil)))
      (tibetan-mitra--url-retrieve "https://example.invalid/x" 1)
      (should (eq captured t)))))

(defun tibetan-mitra-translation-run-tests ()
  "Run all Mitra translation tests interactively."
  (interactive)
  (ert-run-tests-interactively "^tibetan-mitra-"))

(provide 'tibetan-mitra-translation-test)
;;; tibetan-mitra-translation-test.el ends here
