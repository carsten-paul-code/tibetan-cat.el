;;; tibetan-bundled-glossary-test.el --- Tests for the bundled glossary loader -*- lexical-binding: t -*-

;;; Commentary:
;; Exercises `data/tibetan-bundled-glossary.el' using a temporary
;; glossaries directory.  Shares the `tibetan-comprehensive-vocabulary'
;; hash with `tibetan-glossary-loader.el' — the fixture saves and
;; restores its contents so neither test suite clobbers the other.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tibetan-bundled-glossary)

(defmacro tibetan-bundled-test--with-temp-dir (dirvar &rest body)
  "Bind DIRVAR to a fresh temp directory; cleanup after BODY."
  (declare (indent 1))
  `(let ((,dirvar (make-temp-file "tibetan-bundled-" t)))
     (unwind-protect
         (progn ,@body)
       (when (file-exists-p ,dirvar)
         (delete-directory ,dirvar t)))))

(defmacro tibetan-bundled-test--with-fresh-vocab (&rest body)
  "Save/restore the shared vocabulary hash + the loaded flag."
  `(let ((saved-vocab (copy-hash-table tibetan-comprehensive-vocabulary))
         (saved-flag  tibetan-glossaries-loaded))
     (unwind-protect
         (progn
           (clrhash tibetan-comprehensive-vocabulary)
           (setq tibetan-glossaries-loaded nil)
           ,@body)
       (clrhash tibetan-comprehensive-vocabulary)
       (maphash (lambda (k v) (puthash k v tibetan-comprehensive-vocabulary))
                saved-vocab)
       (setq tibetan-glossaries-loaded saved-flag))))

(defun tibetan-bundled-test--write (path content)
  "Create PATH containing CONTENT."
  (let ((dir (file-name-directory path)))
    (unless (file-directory-p dir) (make-directory dir t)))
  (with-temp-file path (insert content)))

;; ---------------------------------------------------------------------------
;; tibetan-bundled-load-tsv-file
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-bundled-load-tsv-populates-hash ()
  "Two-column rows populate the hash; count matches added entries."
  (tibetan-bundled-test--with-fresh-vocab
   (tibetan-bundled-test--with-temp-dir dir
     (let ((tibetan-bundled-glossary-dir dir))
       (tibetan-bundled-test--write
        (expand-file-name "sample.txt" dir)
        (concat "# header comment\n"
                "\n"
                "ཀ\thead\n"
                "བ\tcow\n"))
       (should (= 2 (tibetan-bundled-load-tsv-file "sample.txt")))
       (should (equal (gethash "ཀ" tibetan-comprehensive-vocabulary) "head"))
       (should (equal (gethash "བ" tibetan-comprehensive-vocabulary) "cow"))))))

(ert-deftest tibetan-bundled-load-tsv-skips-comments-and-empties ()
  (tibetan-bundled-test--with-fresh-vocab
   (tibetan-bundled-test--with-temp-dir dir
     (let ((tibetan-bundled-glossary-dir dir))
       (tibetan-bundled-test--write
        (expand-file-name "s.txt" dir)
        "# A\n\n# B\nཀ\thead\n\n")
       (should (= 1 (tibetan-bundled-load-tsv-file "s.txt")))))))

(ert-deftest tibetan-bundled-load-tsv-missing-file-returns-nil ()
  "A missing file returns nil without error (the `when' guard short-
circuits before the counter is returned)."
  (tibetan-bundled-test--with-fresh-vocab
   (tibetan-bundled-test--with-temp-dir dir
     (let ((tibetan-bundled-glossary-dir dir))
       (should (null (tibetan-bundled-load-tsv-file "nonexistent.txt")))))))

(ert-deftest tibetan-bundled-load-tsv-ignores-empty-fields ()
  (tibetan-bundled-test--with-fresh-vocab
   (tibetan-bundled-test--with-temp-dir dir
     (let ((tibetan-bundled-glossary-dir dir))
       (tibetan-bundled-test--write
        (expand-file-name "s.txt" dir)
        "\t\n ཀ\thead\n")
       (should (>= (tibetan-bundled-load-tsv-file "s.txt") 1))))))

;; ---------------------------------------------------------------------------
;; Named wrappers
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-bundled-named-loaders-read-expected-filenames ()
  "Each named loader delegates to the matching bundled filename."
  (tibetan-bundled-test--with-fresh-vocab
   (tibetan-bundled-test--with-temp-dir dir
     (let ((tibetan-bundled-glossary-dir dir))
       (dolist (pair '(("rangjung-yeshe-tibetan.txt" tibetan-bundled-load-rangjung-yeshe "ry-key" "ry-val")
                       ("hopkins-sample.txt"         tibetan-bundled-load-hopkins         "h-key"  "h-val")
                       ("madhyamaka-specialized.txt" tibetan-bundled-load-madhyamaka      "m-key"  "m-val")
                       ("unified-tibetan.txt"        tibetan-bundled-load-unified         "u-key"  "u-val")))
         (let ((file (nth 0 pair))
               (fn   (nth 1 pair))
               (key  (nth 2 pair))
               (val  (nth 3 pair)))
           (clrhash tibetan-comprehensive-vocabulary)
           (tibetan-bundled-test--write
            (expand-file-name file dir)
            (format "%s\t%s\n" key val))
           (funcall fn)
           (should (equal (gethash key tibetan-comprehensive-vocabulary)
                          val))))))))

;; ---------------------------------------------------------------------------
;; load-all-glossaries: idempotence and sequence
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-bundled-load-all-sets-flag ()
  "First call sets `tibetan-glossaries-loaded' to non-nil."
  (tibetan-bundled-test--with-fresh-vocab
   (tibetan-bundled-test--with-temp-dir dir
     (let ((tibetan-bundled-glossary-dir dir))
       (should (null tibetan-glossaries-loaded))
       (tibetan-bundled-load-all-glossaries)
       (should tibetan-glossaries-loaded)))))

(ert-deftest tibetan-bundled-load-all-is-idempotent ()
  "Second call short-circuits when the flag is already set."
  (tibetan-bundled-test--with-fresh-vocab
   (setq tibetan-glossaries-loaded t)
   (cl-letf* ((called 0)
              ((symbol-function 'tibetan-bundled-load-madhyamaka)
               (lambda () (cl-incf called))))
     (tibetan-bundled-load-all-glossaries)
     (should (= called 0)))))

(ert-deftest tibetan-bundled-reload-clears-and-reloads ()
  "`tibetan-bundled-reload-glossaries' clears the flag and reloads."
  (tibetan-bundled-test--with-fresh-vocab
   (setq tibetan-glossaries-loaded t)
   (cl-letf* ((called 0)
              ((symbol-function 'tibetan-bundled-load-madhyamaka)
               (lambda () (cl-incf called)))
              ((symbol-function 'tibetan-bundled-load-hopkins)
               (lambda () (cl-incf called)))
              ((symbol-function 'tibetan-bundled-load-unified)
               (lambda () (cl-incf called)))
              ((symbol-function 'tibetan-bundled-load-rangjung-yeshe)
               (lambda () (cl-incf called))))
     (tibetan-bundled-reload-glossaries)
     (should (= called 4))
     (should tibetan-glossaries-loaded))))

;; ---------------------------------------------------------------------------
;; Lookup
;; ---------------------------------------------------------------------------

(ert-deftest tibetan-bundled-lookup-hits-and-misses ()
  "`tibetan-bundled-lookup' returns stored value or nil, not a sentinel."
  (tibetan-bundled-test--with-fresh-vocab
   (setq tibetan-glossaries-loaded t) ; prevent auto-reload
   (puthash "ཆོས" "dharma" tibetan-comprehensive-vocabulary)
   (should (equal (tibetan-bundled-lookup "ཆོས") "dharma"))
   (should-not (tibetan-bundled-lookup "nonexistent"))))

(ert-deftest tibetan-bundled-lookup-auto-loads-when-unset ()
  "A lookup while the flag is nil triggers `load-all-glossaries' lazily."
  (tibetan-bundled-test--with-fresh-vocab
   (cl-letf* ((invoked 0)
              ((symbol-function 'tibetan-bundled-load-all-glossaries)
               (lambda () (cl-incf invoked) (setq tibetan-glossaries-loaded t))))
     (tibetan-bundled-lookup "anything")
     (should (= invoked 1)))))

(provide 'tibetan-bundled-glossary-test)
;;; tibetan-bundled-glossary-test.el ends here
