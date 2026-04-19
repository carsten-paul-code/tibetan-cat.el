;;; tibetan-glossary-loader.el --- Load all bundled glossaries -*- lexical-binding: t -*-

;;; Commentary:
;; Self-contained glossary loader for Tibetan CAT.
;; All glossary files are bundled in data/glossaries/ within the repo.
;; No external paths required.
;;
;; Provides:
;; - tibetan-comprehensive-vocabulary (hash table, ~18K entries)
;; - tibetan-rangjung-yeshe-vocabulary (hash table, ~162K entries, lazy-loaded)
;; - load-all-glossaries (interactive reload function)

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; DATA DIRECTORY
;; ============================================================================

(defvar tibetan-glossary-data-dir
  (expand-file-name "glossaries/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory containing glossary data files.")

;; ============================================================================
;; VOCABULARY HASH TABLES
;; ============================================================================

(defvar tibetan-comprehensive-vocabulary (make-hash-table :test 'equal :size 20000)
  "Hash table containing all Tibetan vocabulary from multiple sources.")

(defvar tibetan-rangjung-yeshe-vocabulary nil
  "Hash table for Rangjung Yeshe dictionary (162K entries).
Loaded on first use to avoid slow startup.")

;; ============================================================================
;; GENERIC TSV LOADER
;; ============================================================================

(defun tibetan-glossary--load-tsv (filepath &optional skip-existing)
  "Load a tab-separated glossary from FILEPATH into comprehensive vocabulary.
If SKIP-EXISTING is non-nil, don't overwrite existing entries.
Format: Tibetan<TAB>English[<TAB>Notes]
Lines starting with # are comments."
  (when (file-exists-p filepath)
    (let ((count 0))
      (with-temp-buffer
        (insert-file-contents filepath)
        (goto-char (point-min))
        (while (not (eobp))
          (unless (looking-at "^[#\n]")  ; Skip comments and empty lines
            (let ((line (split-string (buffer-substring-no-properties
                                       (line-beginning-position)
                                       (line-end-position))
                                      "\t" t)))
              (when (>= (length line) 2)
                (let ((tibetan (string-trim (nth 0 line)))
                      (english (string-trim (nth 1 line)))
                      (notes (when (nth 2 line) (string-trim (nth 2 line)))))
                  (unless (and skip-existing
                               (gethash tibetan tibetan-comprehensive-vocabulary))
                    (puthash tibetan
                             (if (and notes (not (string-empty-p notes)))
                                 (format "%s [%s]" english notes)
                               english)
                             tibetan-comprehensive-vocabulary)
                    (setq count (1+ count)))))))
          (forward-line 1)))
      count)))

;; ============================================================================
;; INDIVIDUAL GLOSSARY LOADERS
;; ============================================================================

;;;###autoload
(defun load-hopkins-glossary ()
  "Load Hopkins glossary from bundled data."
  (interactive)
  (let ((file (expand-file-name "hopkins-sample.txt" tibetan-glossary-data-dir)))
    (let ((n (tibetan-glossary--load-tsv file)))
      (when n (message "  Loaded Hopkins glossary: %d entries" n)))))

;;;###autoload
(defun load-unified-glossary ()
  "Load unified Tibetan glossary from bundled data."
  (interactive)
  (let ((file (expand-file-name "unified-tibetan.txt" tibetan-glossary-data-dir)))
    (let ((n (tibetan-glossary--load-tsv file t)))
      (when n (message "  Loaded unified glossary: %d new entries" n)))))

;;;###autoload
(defun load-madhyamaka-glossary ()
  "Load specialized Madhyamaka glossary from bundled data."
  (interactive)
  (let ((file (expand-file-name "madhyamaka-specialized.txt" tibetan-glossary-data-dir)))
    (let ((n (tibetan-glossary--load-tsv file t)))
      (when n (message "  Loaded Madhyamaka glossary: %d new entries" n)))))

;;;###autoload
(defun load-common-vocabulary ()
  "Load common vocabulary from bundled data."
  (interactive)
  (let ((file (expand-file-name "common-vocabulary.txt" tibetan-glossary-data-dir)))
    (let ((n (tibetan-glossary--load-tsv file t)))
      (when n (message "  Loaded common vocabulary: %d new entries" n)))))

;;;###autoload
(defun load-tibetan-english-glossary ()
  "Load the large tibetan-english glossary (TSV format)."
  (interactive)
  (let ((file (expand-file-name "tibetan-english.tsv" tibetan-glossary-data-dir)))
    (let ((n (tibetan-glossary--load-tsv file t)))
      (when n (message "  Loaded tibetan-english glossary: %d new entries" n)))))

;; ============================================================================
;; RANGJUNG YESHE (LAZY LOAD)
;; ============================================================================

;;;###autoload
(defun tibetan-load-rangjung-yeshe ()
  "Load Rangjung Yeshe dictionary (~162K entries).
Called automatically on first vocabulary lookup."
  (interactive)
  (unless (and tibetan-rangjung-yeshe-vocabulary
               (> (hash-table-count tibetan-rangjung-yeshe-vocabulary) 0))
    (let ((ry-file (expand-file-name "rangjung-yeshe-tibetan.txt"
                                      tibetan-glossary-data-dir)))
      (if (not (file-exists-p ry-file))
          (message "  Rangjung Yeshe dictionary not found at %s" ry-file)
        (message "Loading Rangjung Yeshe dictionary (162k entries)...")
        (setq tibetan-rangjung-yeshe-vocabulary
              (make-hash-table :test 'equal :size 350000))
        (with-temp-buffer
          (insert-file-contents ry-file)
          (goto-char (point-min))
          (while (not (eobp))
            (let* ((line (buffer-substring-no-properties
                          (line-beginning-position)
                          (line-end-position)))
                   (parts (split-string line "\t")))
              (when (>= (length parts) 2)
                (let ((tibetan (string-trim (nth 0 parts)))
                      (english (string-trim (nth 1 parts))))
                  (unless (string-empty-p tibetan)
                    (puthash tibetan english tibetan-rangjung-yeshe-vocabulary)))))
            (forward-line 1)))
        (message "  Loaded Rangjung Yeshe dictionary: %d entries"
                 (hash-table-count tibetan-rangjung-yeshe-vocabulary))))))

;; ============================================================================
;; MASTER LOADER
;; ============================================================================

(defvar tibetan-glossaries-loaded nil
  "Non-nil after `load-all-glossaries' has populated
`tibetan-comprehensive-vocabulary'.  Guards against repeated reloads
when callers (e.g. `tibetan-analysis--ensure-vocabulary' invoked on
every reanalysis) trigger the function defensively.  Set to nil and
call `load-all-glossaries' again to force a fresh load.")

;;;###autoload
(defun load-all-glossaries (&optional force)
  "Load all available glossaries into the comprehensive vocabulary.
Rangjung Yeshe is loaded separately on first use.

Idempotent: returns immediately if `tibetan-glossaries-loaded' is
already non-nil.  Pass FORCE non-nil (interactively, with a prefix
argument) to discard the existing hash and reload everything."
  (interactive "P")
  (when force (setq tibetan-glossaries-loaded nil))
  (unless tibetan-glossaries-loaded
    (clrhash tibetan-comprehensive-vocabulary)
    (message "Loading glossaries...")
    (load-hopkins-glossary)
    (load-tibetan-english-glossary)
    (load-unified-glossary)
    (load-madhyamaka-glossary)
    (load-common-vocabulary)
    ;; Also load user's custom vocabulary if it exists
    (when (fboundp 'tibetan-load-custom-vocabularies)
      (tibetan-load-custom-vocabularies))
    (setq tibetan-glossaries-loaded t)
    (message "Loaded %d total vocabulary entries from all glossaries"
             (hash-table-count tibetan-comprehensive-vocabulary))))

;; ============================================================================
;; LOOKUP FUNCTIONS
;; ============================================================================

(defun lookup-tibetan-comprehensive (word)
  "Look up WORD in the comprehensive vocabulary."
  (or (gethash word tibetan-comprehensive-vocabulary)
      (format "[Not found: %s]" word)))

;;;###autoload
(defun add-to-tibetan-vocabulary (tibetan english)
  "Add TIBETAN term with ENGLISH translation to vocabulary."
  (interactive "sTibetan term: \nsEnglish translation: ")
  (puthash tibetan english tibetan-comprehensive-vocabulary)
  (message "Added: %s = %s" tibetan english))

;; ============================================================================
;; AUTO-LOAD ON REQUIRE
;; ============================================================================
;;
;; Respect the test-harness opt-out `tibetan-skip-external-glossaries'
;; so that test files which only need a few public helpers don't pay
;; the cost of parsing 17 000 TSV entries at require-time.  Production
;; callers (tibetan-cat.el, sentence-structure, etc.) never bind this
;; flag, so their load path is unchanged.

(unless (bound-and-true-p tibetan-skip-external-glossaries)
  (load-all-glossaries))

(provide 'tibetan-glossary-loader)
;;; tibetan-glossary-loader.el ends here
