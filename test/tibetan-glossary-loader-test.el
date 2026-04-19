;;; tibetan-glossary-loader-test.el --- Tests for the bundled glossary loader -*- lexical-binding: t -*-

;;; Commentary:
;; Exercises `data/tibetan-glossary-loader.el' using a temporary
;; data directory so the production glossaries stay intact.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tibetan-glossary-loader)

;; ---------------------------------------------------------------------------
;; Shared fixture helpers
;; ---------------------------------------------------------------------------

(defmacro tibetan-glossary-loader-test--with-temp-dir (dirvar &rest body)
  "Bind DIRVAR to a fresh temp directory; cleanup after BODY."
  (declare (indent 1))
  `(let ((,dirvar (make-temp-file "tibetan-glossary-loader-" t)))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p ,dirvar)
         (delete-directory ,dirvar t)))))

(defmacro tibetan-glossary-loader-test--with-fresh-vocab (&rest body)
  "Save/restore `tibetan-comprehensive-vocabulary' and the loaded flag."
  `(let ((saved-vocab (copy-hash-table tibetan-comprehensive-vocabulary))
         (saved-flag  tibetan-glossaries-loaded)
         (saved-ry    tibetan-rangjung-yeshe-vocabulary))
     (unwind-protect
         (progn
           (clrhash tibetan-comprehensive-vocabulary)
           (setq tibetan-glossaries-loaded nil
                 tibetan-rangjung-yeshe-vocabulary nil)
           ,@body)
       (clrhash tibetan-comprehensive-vocabulary)
       (maphash (lambda (k v) (puthash k v tibetan-comprehensive-vocabulary))
                saved-vocab)
       (setq tibetan-glossaries-loaded saved-flag
             tibetan-rangjung-yeshe-vocabulary saved-ry))))

(defun tibetan-glossary-loader-test--write (path content)
  "Create PATH containing CONTENT (string)."
  (let ((dir (file-name-directory path)))
    (unless (file-directory-p dir) (make-directory dir t)))
  (with-temp-file path (insert content)))

;; ---------------------------------------------------------------------------
;; --load-tsv  (parser)
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-glossary-loader-tsv-parses-two-column-rows ()
  "Two-column `tib<TAB>eng' rows populate the hash; comments are skipped."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (let ((file (expand-file-name "sample.tsv" dir)))
       (tibetan-glossary-loader-test--write
        file
        (concat "# a comment\n"
                "\n"
                "ཀ\thead\n"
                "བ\tcow\n"))
       (let ((count (tibetan-glossary--load-tsv file)))
         (should (= count 2))
         (should (equal (gethash "ཀ" tibetan-comprehensive-vocabulary) "head"))
         (should (equal (gethash "བ" tibetan-comprehensive-vocabulary) "cow")))))))

(ert-deftest tibetan-glossary-loader-tsv-appends-three-column-notes ()
  "A third TAB-delimited column is appended in [brackets]."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (let ((file (expand-file-name "sample.tsv" dir)))
       (tibetan-glossary-loader-test--write
        file
        "དགེ་འདུན\tsangha\tBuddhist monastic community\n")
       (tibetan-glossary--load-tsv file)
       (should (equal (gethash "དགེ་འདུན" tibetan-comprehensive-vocabulary)
                      "sangha [Buddhist monastic community]"))))))

(ert-deftest tibetan-glossary-loader-tsv-skip-existing-respected ()
  "When SKIP-EXISTING is non-nil, pre-existing keys are preserved."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (puthash "ཀ" "original" tibetan-comprehensive-vocabulary)
     (let ((file (expand-file-name "sample.tsv" dir)))
       (tibetan-glossary-loader-test--write file "ཀ\toverridden\n")
       (tibetan-glossary--load-tsv file t)
       (should (equal (gethash "ཀ" tibetan-comprehensive-vocabulary)
                      "original"))))))

(ert-deftest tibetan-glossary-loader-tsv-without-skip-overwrites ()
  "Without SKIP-EXISTING the later value wins."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (puthash "ཀ" "original" tibetan-comprehensive-vocabulary)
     (let ((file (expand-file-name "sample.tsv" dir)))
       (tibetan-glossary-loader-test--write file "ཀ\tnew\n")
       (tibetan-glossary--load-tsv file)
       (should (equal (gethash "ཀ" tibetan-comprehensive-vocabulary) "new"))))))

(ert-deftest tibetan-glossary-loader-tsv-missing-file-noop ()
  "A missing file yields nil without touching the hash."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (should-not (tibetan-glossary--load-tsv "/nonexistent/path.tsv"))
   (should (= 0 (hash-table-count tibetan-comprehensive-vocabulary)))))

(ert-deftest tibetan-glossary-loader-tsv-ignores-one-column-rows ()
  "Rows with fewer than two columns are ignored."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (let ((file (expand-file-name "sample.tsv" dir)))
       (tibetan-glossary-loader-test--write file "onlyone\nཀ\thead\n")
       (should (= 1 (tibetan-glossary--load-tsv file)))))))

;; ---------------------------------------------------------------------------
;; load-all-glossaries idempotence
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-glossary-loader-load-all-is-idempotent ()
  "Second call is a no-op when the flag is set."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (setq tibetan-glossaries-loaded t)
   (cl-letf* ((calls 0)
              ((symbol-function 'load-hopkins-glossary)
               (lambda () (cl-incf calls))))
     (load-all-glossaries)
     (should (= calls 0)))))

(ert-deftest tibetan-glossary-loader-load-all-force-bypasses-flag ()
  "FORCE resets the flag and triggers a fresh load."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (setq tibetan-glossaries-loaded t)
   (cl-letf* ((calls 0)
              ((symbol-function 'load-hopkins-glossary)
               (lambda () (cl-incf calls)))
              ((symbol-function 'load-tibetan-english-glossary)
               (lambda () (cl-incf calls)))
              ((symbol-function 'load-unified-glossary)
               (lambda () (cl-incf calls)))
              ((symbol-function 'load-madhyamaka-glossary)
               (lambda () (cl-incf calls)))
              ((symbol-function 'load-common-vocabulary)
               (lambda () (cl-incf calls))))
     (load-all-glossaries t)
     (should (= calls 5))
     (should tibetan-glossaries-loaded))))

;; ---------------------------------------------------------------------------
;; Individual loaders are thin wrappers over --load-tsv.
;; One integration test confirms the wrapper shape.
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-glossary-loader-named-loader-honours-data-dir ()
  "A named loader (`load-hopkins-glossary') reads from the configured data dir."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (let ((tibetan-glossary-data-dir (file-name-as-directory dir)))
       (tibetan-glossary-loader-test--write
        (expand-file-name "hopkins-sample.txt" dir)
        "ཤེས་རབ\tprajñā\twisdom\n")
       (load-hopkins-glossary)
       (should (equal (gethash "ཤེས་རབ" tibetan-comprehensive-vocabulary)
                      "prajñā [wisdom]"))))))

;; ---------------------------------------------------------------------------
;; lookup-tibetan-comprehensive & add-to-tibetan-vocabulary
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-glossary-loader-lookup-returns-value-or-sentinel ()
  "`lookup-tibetan-comprehensive' returns the stored value for known keys
and a `[Not found: …]' sentinel otherwise."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (setq tibetan-glossaries-loaded t)
   (puthash "ཤེས་རབ" "wisdom" tibetan-comprehensive-vocabulary)
   (should (equal (lookup-tibetan-comprehensive "ཤེས་རབ") "wisdom"))
   (should (equal (lookup-tibetan-comprehensive "nonexistent")
                  "[Not found: nonexistent]"))))

(ert-deftest tibetan-glossary-loader-add-mutates-hash ()
  "`add-to-tibetan-vocabulary' puts the pair into the comprehensive hash."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (add-to-tibetan-vocabulary "བྱང་ཆུབ" "awakening")
   (should (equal (gethash "བྱང་ཆུབ" tibetan-comprehensive-vocabulary)
                  "awakening"))))

;; ---------------------------------------------------------------------------
;; Rangjung Yeshe lazy load
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-glossary-loader-ry-lazy-loads-when-file-present ()
  "When the RY data file is present the hash is populated on first call."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (let ((tibetan-glossary-data-dir (file-name-as-directory dir)))
       (tibetan-glossary-loader-test--write
        (expand-file-name "rangjung-yeshe-tibetan.txt" dir)
        "སེམས\tmind\nཆོས\tdharma\n")
       (tibetan-load-rangjung-yeshe)
       (should (hash-table-p tibetan-rangjung-yeshe-vocabulary))
       (should (equal (gethash "སེམས" tibetan-rangjung-yeshe-vocabulary)
                      "mind"))
       (should (equal (gethash "ཆོས" tibetan-rangjung-yeshe-vocabulary)
                      "dharma"))))))

(ert-deftest tibetan-glossary-loader-ry-missing-file-gracefully ()
  "Missing RY file leaves `tibetan-rangjung-yeshe-vocabulary' nil."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (tibetan-glossary-loader-test--with-temp-dir dir
     (let ((tibetan-glossary-data-dir (file-name-as-directory dir)))
       (tibetan-load-rangjung-yeshe)
       (should (null tibetan-rangjung-yeshe-vocabulary))))))

(ert-deftest tibetan-glossary-loader-ry-second-call-is-noop ()
  "When RY is already populated the function returns immediately."
  (tibetan-glossary-loader-test--with-fresh-vocab
   (setq tibetan-rangjung-yeshe-vocabulary (make-hash-table :test 'equal))
   (puthash "sentinel" "value" tibetan-rangjung-yeshe-vocabulary)
   (cl-letf (((symbol-function 'insert-file-contents)
              (lambda (&rest _) (error "RY loader re-read data file"))))
     (tibetan-load-rangjung-yeshe)
     (should (equal (gethash "sentinel" tibetan-rangjung-yeshe-vocabulary)
                    "value")))))

(provide 'tibetan-glossary-loader-test)
;;; tibetan-glossary-loader-test.el ends here
