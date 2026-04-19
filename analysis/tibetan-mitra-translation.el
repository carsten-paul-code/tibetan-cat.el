;;; tibetan-mitra-translation.el --- Gemma-2-Mitra-E integration for Tibetan translation -*- lexical-binding: t -*-

;;; Commentary:
;; Integration with Gemma-2-Mitra-E, a fine-tuned model for Tibetan-English translation.
;; Supports multiple backends:
;; - Ollama (local, recommended for privacy)
;; - Hugging Face Inference API
;; - Local Python server (for direct transformers usage)
;;
;; Model: billingsmoore/gemma-2-2b-mitra-e (Hugging Face)
;;
;; Usage:
;;   (tibetan-mitra-translate "བྱང་ཆུབ་སེམས་དཔའ།")
;;   => "bodhisattva"

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'url)

;; ============================================================================
;; CONFIGURATION
;; ============================================================================

(defgroup tibetan-mitra nil
  "Gemma-2-Mitra-E translation integration."
  :group 'tibetan-cat
  :prefix "tibetan-mitra-")

(defcustom tibetan-mitra-backend 'ollama
  "Backend to use for Mitra translation.
Options: `ollama', `huggingface', `local-server'."
  :type '(choice (const :tag "Ollama (local)" ollama)
                 (const :tag "Hugging Face API" huggingface)
                 (const :tag "Local Python server" local-server))
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-ollama-url "http://localhost:11434"
  "URL for Ollama API."
  :type 'string
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-ollama-model "gemma2-mitra"
  "Model name in Ollama for Mitra.
You need to create this model first - see `tibetan-mitra-setup-ollama'."
  :type 'string
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-huggingface-model "billingsmoore/gemma-2-2b-mitra-e"
  "Hugging Face model identifier."
  :type 'string
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-huggingface-token nil
  "Hugging Face API token. Set via M-x customize or in init.el.
Get your token at: https://huggingface.co/settings/tokens"
  :type '(choice (const :tag "Not set" nil)
                 (string :tag "API Token"))
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-local-server-url "http://localhost:5000"
  "URL for local Python translation server."
  :type 'string
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-timeout 30
  "Timeout in seconds for translation requests."
  :type 'integer
  :group 'tibetan-mitra)

(defcustom tibetan-mitra-cache-enabled t
  "Whether to cache translation results."
  :type 'boolean
  :group 'tibetan-mitra)

;; ============================================================================
;; TRANSLATION CACHE
;; ============================================================================

(defvar tibetan-mitra--cache (make-hash-table :test 'equal)
  "Cache for Mitra translations.")

;;;###autoload
(defun tibetan-mitra-clear-cache ()
  "Clear the translation cache."
  (interactive)
  (clrhash tibetan-mitra--cache)
  (message "Mitra translation cache cleared."))

;; ============================================================================
;; OLLAMA BACKEND
;; ============================================================================

(defun tibetan-mitra--ollama-translate (tibetan-text)
  "Translate TIBETAN-TEXT using Ollama backend."
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          '(("Content-Type" . "application/json")))
         (prompt (format "Translate the following Tibetan text to English:\n\n%s" tibetan-text))
         (url-request-data
          (encode-coding-string
           (json-encode
            `((model . ,tibetan-mitra-ollama-model)
              (prompt . ,prompt)
              (stream . :json-false)
              (options . ((temperature . 0.1)
                          (num_predict . 256)))))
           'utf-8))
         (url (format "%s/api/generate" tibetan-mitra-ollama-url)))
    (with-current-buffer
        (url-retrieve-synchronously url nil nil tibetan-mitra-timeout)
      (goto-char (point-min))
      (re-search-forward "^$")
      (let* ((json-object-type 'alist)
             (json-array-type 'list)
             (response (json-read)))
        (string-trim (alist-get 'response response))))))

(defun tibetan-mitra--ollama-available-p ()
  "Check if Ollama is available and the model is loaded."
  (condition-case nil
      (let* ((url-request-method "GET")
             (url (format "%s/api/tags" tibetan-mitra-ollama-url)))
        (with-current-buffer
            (url-retrieve-synchronously url nil nil 5)
          (goto-char (point-min))
          (re-search-forward "^$")
          (let* ((json-object-type 'alist)
                 (json-array-type 'list)
                 (response (json-read))
                 (models (alist-get 'models response)))
            (cl-some (lambda (m)
                       (string-match-p tibetan-mitra-ollama-model
                                       (alist-get 'name m)))
                     models))))
    (error nil)))

;; ============================================================================
;; HUGGING FACE BACKEND
;; ============================================================================

(defun tibetan-mitra--huggingface-translate (tibetan-text)
  "Translate TIBETAN-TEXT using Hugging Face Inference API."
  (unless tibetan-mitra-huggingface-token
    (error "Hugging Face token not set. Use M-x customize-variable tibetan-mitra-huggingface-token"))
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          `(("Content-Type" . "application/json")
            ("Authorization" . ,(format "Bearer %s" tibetan-mitra-huggingface-token))))
         (prompt (format "Translate Tibetan to English: %s" tibetan-text))
         (url-request-data
          (encode-coding-string
           (json-encode
            `((inputs . ,prompt)
              (parameters . ((max_new_tokens . 256)
                             (temperature . 0.1)
                             (return_full_text . :json-false)))))
           'utf-8))
         (url (format "https://api-inference.huggingface.co/models/%s"
                      tibetan-mitra-huggingface-model)))
    (with-current-buffer
        (url-retrieve-synchronously url nil nil tibetan-mitra-timeout)
      (goto-char (point-min))
      (re-search-forward "^$")
      (let* ((json-object-type 'alist)
             (json-array-type 'list)
             (response (json-read)))
        ;; HF returns array of results
        (if (arrayp response)
            (string-trim (alist-get 'generated_text (aref response 0)))
          (string-trim (alist-get 'generated_text response)))))))

;; ============================================================================
;; LOCAL SERVER BACKEND
;; ============================================================================

(defun tibetan-mitra--local-server-translate (tibetan-text)
  "Translate TIBETAN-TEXT using local Python server."
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          '(("Content-Type" . "application/json")))
         (url-request-data
          (encode-coding-string
           (json-encode `((text . ,tibetan-text)))
           'utf-8))
         (url (format "%s/translate" tibetan-mitra-local-server-url)))
    (with-current-buffer
        (url-retrieve-synchronously url nil nil tibetan-mitra-timeout)
      (goto-char (point-min))
      (re-search-forward "^$")
      (let* ((json-object-type 'alist)
             (response (json-read)))
        (string-trim (alist-get 'translation response))))))

;; ============================================================================
;; MAIN TRANSLATION FUNCTION
;; ============================================================================

(defun tibetan-mitra-translate (tibetan-text)
  "Translate TIBETAN-TEXT using Gemma-2-Mitra-E.
Uses the backend specified in `tibetan-mitra-backend'."
  (when (or (null tibetan-text) (string-empty-p (string-trim tibetan-text)))
    (error "No Tibetan text provided"))

  (let ((text (string-trim tibetan-text)))
    ;; Check cache first
    (if (and tibetan-mitra-cache-enabled
             (gethash text tibetan-mitra--cache))
        (gethash text tibetan-mitra--cache)
      ;; Call appropriate backend
      (let ((result
             (condition-case err
                 (pcase tibetan-mitra-backend
                   ('ollama (tibetan-mitra--ollama-translate text))
                   ('huggingface (tibetan-mitra--huggingface-translate text))
                   ('local-server (tibetan-mitra--local-server-translate text))
                   (_ (error "Unknown backend: %s" tibetan-mitra-backend)))
               (error
                (message "Mitra translation error: %s" (error-message-string err))
                nil))))
        ;; Cache result
        (when (and result tibetan-mitra-cache-enabled)
          (puthash text result tibetan-mitra--cache))
        result))))

(defun tibetan-mitra-translate-async (tibetan-text callback)
  "Translate TIBETAN-TEXT asynchronously, calling CALLBACK with result."
  (let ((text (string-trim tibetan-text)))
    ;; Check cache first
    (if (and tibetan-mitra-cache-enabled
             (gethash text tibetan-mitra--cache))
        (funcall callback (gethash text tibetan-mitra--cache))
      ;; Async request (simplified - uses make-process for real async)
      (run-with-timer
       0.1 nil
       (lambda ()
         (let ((result (tibetan-mitra-translate text)))
           (funcall callback result)))))))

;; ============================================================================
;; INTERACTIVE COMMANDS
;; ============================================================================

;;;###autoload
(defun tibetan-mitra-translate-region (start end)
  "Translate Tibetan text in region from START to END using Mitra."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (translation (tibetan-mitra-translate text)))
    (if translation
        (progn
          (message "Mitra: %s" translation)
          translation)
      (message "Mitra translation failed")
      nil)))

;;;###autoload
(defun tibetan-mitra-translate-segment ()
  "Translate current Tibetan segment using Mitra."
  (interactive)
  (let ((segment-text nil))
    ;; Try to get segment from current context
    (save-excursion
      (beginning-of-line)
      (when (looking-at "^\\([ༀ-࿿]+[^[:ascii:]]*\\)")
        (setq segment-text (match-string 1))))
    (if segment-text
        (let ((translation (tibetan-mitra-translate segment-text)))
          (message "Mitra: %s" translation)
          translation)
      (message "No Tibetan segment found at point"))))

;;;###autoload
(defun tibetan-mitra-translate-dwim ()
  "Translate Tibetan text: region if active, else current segment."
  (interactive)
  (if (use-region-p)
      (tibetan-mitra-translate-region (region-beginning) (region-end))
    (tibetan-mitra-translate-segment)))

;; ============================================================================
;; SETUP HELPERS
;; ============================================================================

;;;###autoload
(defun tibetan-mitra-setup-ollama ()
  "Display instructions for setting up Mitra in Ollama."
  (interactive)
  (with-help-window "*Mitra Ollama Setup*"
    (princ "Setting up Gemma-2-Mitra-E in Ollama\n")
    (princ "====================================\n\n")
    (princ "1. Install Ollama: https://ollama.ai\n\n")
    (princ "2. Create a Modelfile with the following content:\n\n")
    (princ "   FROM gemma2:2b\n")
    (princ "   ADAPTER /path/to/mitra-lora-adapter\n")
    (princ "   PARAMETER temperature 0.1\n")
    (princ "   SYSTEM \"You are a Tibetan to English translator.\"\n\n")
    (princ "3. Or pull a pre-made model (if available):\n")
    (princ "   ollama pull billingsmoore/gemma-2-mitra-e\n\n")
    (princ "4. Test with:\n")
    (princ "   ollama run gemma2-mitra \"Translate: བྱང་ཆུབ་སེམས་དཔའ།\"\n\n")
    (princ "Alternative: Use Hugging Face backend\n")
    (princ "-------------------------------------\n")
    (princ "Set tibetan-mitra-backend to 'huggingface and provide your API token.\n")))


;;;###autoload
(defun tibetan-mitra-check-status ()
  "Check status of Mitra translation backend."
  (interactive)
  (message "Checking Mitra backend: %s..." tibetan-mitra-backend)
  (pcase tibetan-mitra-backend
    ('ollama
     (if (tibetan-mitra--ollama-available-p)
         (message "Ollama backend: OK (model %s available)" tibetan-mitra-ollama-model)
       (message "Ollama backend: Model %s not found. Run M-x tibetan-mitra-setup-ollama"
                tibetan-mitra-ollama-model)))
    ('huggingface
     (if tibetan-mitra-huggingface-token
         (message "Hugging Face backend: Token configured")
       (message "Hugging Face backend: Token not set")))
    ('local-server
     (condition-case nil
         (progn
           (url-retrieve-synchronously
            (format "%s/health" tibetan-mitra-local-server-url) nil nil 3)
           (message "Local server backend: OK"))
       (error
        (message "Local server backend: Not responding at %s"
                 tibetan-mitra-local-server-url))))))

;; ============================================================================
;; INTEGRATION WITH TIBETAN-CAT ANALYSIS
;; ============================================================================


(defun tibetan-mitra-format-for-display (translation)
  "Format Mitra TRANSLATION for display in analysis buffer."
  (if translation
      (format "🤖 Mitra (AI): %s" translation)
    "🤖 Mitra: [translation not available]"))

(provide 'tibetan-mitra-translation)
;;; tibetan-mitra-translation.el ends here
