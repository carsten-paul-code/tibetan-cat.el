;;; tibetan-bundled-glossary.el --- Load bundled Tibetan glossaries -*- lexical-binding: t -*-

;; Author: Carsten Paul <post@carstenpaul.de>
;; URL: https://github.com/carsten-paul-code/tibetan-cat.el
;; Version: 2.1.0

;; This file is part of tibetan-cat.el

;;; Commentary:
;; Loads the bundled Tibetan-English glossaries included with tibetan-cat.el.
;; Includes Rangjung Yeshe (162K entries), Hopkins, Madhyamaka specialized terms.

;;; Code:

(require 'cl-lib)

(defvar tibetan-bundled-glossary-dir
  (expand-file-name "glossaries" (file-name-directory (or load-file-name buffer-file-name)))
  "Directory containing bundled glossary files.")

(defvar tibetan-comprehensive-vocabulary (make-hash-table :test 'equal :size 170000)
  "Hash table containing all Tibetan vocabulary from bundled sources.")

(defvar tibetan-glossaries-loaded nil
  "Flag indicating whether bundled glossaries have been loaded.")

(defun tibetan-bundled-load-tsv-file (filename)
  "Load a TSV glossary file from the bundled glossaries directory.
FILENAME is relative to the glossaries directory."
  (let ((filepath (expand-file-name filename tibetan-bundled-glossary-dir))
        (count 0))
    (when (file-exists-p filepath)
      (with-temp-buffer
        (insert-file-contents filepath)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position)
                       (line-end-position))))
            (unless (or (string-match-p "^#" line) (string= "" line))
              (let* ((parts (split-string line "\t"))
                     (tibetan (car parts))
                     (english (cadr parts)))
                (when (and tibetan english
                           (not (string-empty-p tibetan))
                           (not (string-empty-p english)))
                  (puthash tibetan english tibetan-comprehensive-vocabulary)
                  (setq count (1+ count))))))
          (forward-line 1)))
      count)))

(defun tibetan-bundled-load-rangjung-yeshe ()
  "Load the Rangjung Yeshe dictionary (162K entries)."
  (let ((count (tibetan-bundled-load-tsv-file "rangjung-yeshe-tibetan.txt")))
    (when count
      (message "Loaded Rangjung Yeshe: %d entries" count))
    count))

(defun tibetan-bundled-load-hopkins ()
  "Load the Hopkins glossary."
  (let ((count (tibetan-bundled-load-tsv-file "hopkins-sample.txt")))
    (when count
      (message "Loaded Hopkins glossary: %d entries" count))
    count))

(defun tibetan-bundled-load-madhyamaka ()
  "Load the Madhyamaka specialized glossary."
  (let ((count (tibetan-bundled-load-tsv-file "madhyamaka-specialized.txt")))
    (when count
      (message "Loaded Madhyamaka glossary: %d entries" count))
    count))

(defun tibetan-bundled-load-unified ()
  "Load the unified Tibetan glossary."
  (let ((count (tibetan-bundled-load-tsv-file "unified-tibetan.txt")))
    (when count
      (message "Loaded unified glossary: %d entries" count))
    count))

;;;###autoload
(defun tibetan-bundled-load-all-glossaries ()
  "Load all bundled glossaries into the comprehensive vocabulary.
This is the main entry point for loading vocabulary data."
  (interactive)
  (unless tibetan-glossaries-loaded
    (message "Loading bundled Tibetan glossaries...")
    (clrhash tibetan-comprehensive-vocabulary)

    ;; Load in order of priority (later entries don't override earlier ones)
    ;; Specialized glossaries first (higher priority)
    (tibetan-bundled-load-madhyamaka)
    (tibetan-bundled-load-hopkins)
    (tibetan-bundled-load-unified)
    ;; Rangjung Yeshe last (comprehensive fallback)
    (tibetan-bundled-load-rangjung-yeshe)

    (setq tibetan-glossaries-loaded t)
    (message "Tibetan glossaries loaded: %d total entries"
             (hash-table-count tibetan-comprehensive-vocabulary))))

;;;###autoload
(defun tibetan-bundled-reload-glossaries ()
  "Force reload all bundled glossaries."
  (interactive)
  (setq tibetan-glossaries-loaded nil)
  (tibetan-bundled-load-all-glossaries))

(defun tibetan-bundled-lookup (word)
  "Look up WORD in the bundled vocabulary.
Returns the translation or nil if not found."
  (unless tibetan-glossaries-loaded
    (tibetan-bundled-load-all-glossaries))
  (gethash word tibetan-comprehensive-vocabulary))

;; Compatibility alias for existing code
(defalias 'lookup-tibetan-comprehensive 'tibetan-bundled-lookup)
(defalias 'load-all-glossaries 'tibetan-bundled-load-all-glossaries)

(provide 'tibetan-bundled-glossary)
;;; tibetan-bundled-glossary.el ends here
