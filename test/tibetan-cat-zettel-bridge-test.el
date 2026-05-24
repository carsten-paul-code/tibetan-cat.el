;;; tibetan-cat-zettel-bridge-test.el --- Tests for the CAT→Zettel bridge  -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for `tibetan-cat-open-zettel-for-word-at-point' — the
;; bridge that lets the user, while reading/translating in the CAT
;; tool, jump straight to the zettelkasten entry for the Tibetan
;; word under the cursor.
;;
;; Three routing modes:
;;   1. Research-Emacs server running, no prefix arg → emacsclient
;;   2. Research-Emacs server running, prefix arg     → local find-file
;;   3. Research-Emacs server NOT running             → local find-file

;;; Code:

(require 'ert)
(require 'tibetan-cat)
(require 'tibetan-zettel)
(require 'cl-lib)
(require 'server)

;; ============================================================================
;; --server-socket-path
;; ============================================================================

(ert-deftest tibetan-cat-bridge-server-socket-path-nil-when-missing ()
  "Return nil when no socket file exists for the named server."
  (let ((tibetan-cat-zettel-target-server "does-not-exist-xyz"))
    (should (null (tibetan-cat--server-socket-path
                   tibetan-cat-zettel-target-server)))))

(ert-deftest tibetan-cat-bridge-server-socket-path-found ()
  "Return the socket path when the file exists in server-socket-dir."
  (require 'server)
  (let ((tmp-dir (make-temp-file "cat-bridge-sockdir-" t)))
    (unwind-protect
        (cl-letf (((symbol-value 'server-socket-dir) tmp-dir))
          (let ((sock (expand-file-name "fake-research" tmp-dir)))
            (with-temp-file sock (insert ""))
            (should (equal (tibetan-cat--server-socket-path "fake-research")
                           sock))))
      (delete-directory tmp-dir t))))

;; ============================================================================
;; routing logic
;; ============================================================================

(ert-deftest tibetan-cat-bridge-uses-emacsclient-when-server-present-no-prefix ()
  "Route via emacsclient when research server present and no prefix arg."
  (let* ((tibetan-cat-zettel-target-server "fake-research")
         (sock-dir (make-temp-file "cat-bridge-sock-" t))
         (sock (expand-file-name "fake-research" sock-dir))
         (zettel-path (expand-file-name "fake-zettel.org" sock-dir))
         (find-file-called nil)
         (emacsclient-called nil)
         (emacsclient-args nil))
    (with-temp-file sock (insert ""))
    (with-temp-file zettel-path (insert "fake"))
    (unwind-protect
        (cl-letf (((symbol-value 'server-socket-dir) sock-dir)
                  ((symbol-function 'tibetan-thesaurus--wylie-at-point)
                   (lambda () "mthu"))
                  ((symbol-function 'tibetan-zettel-lookup)
                   (lambda (_w) (list :path zettel-path :title "mthu")))
                  ((symbol-function 'find-file)
                   (lambda (&rest _) (setq find-file-called t)))
                  ((symbol-function 'call-process)
                   (lambda (program &rest args)
                     (when (string= program "emacsclient")
                       (setq emacsclient-called t
                             emacsclient-args args)))))
          (tibetan-cat-open-zettel-for-word-at-point nil))
      (delete-directory sock-dir t))
    (should emacsclient-called)
    (should (not find-file-called))
    (should (member zettel-path emacsclient-args))
    (should (member "fake-research" emacsclient-args))))

(ert-deftest tibetan-cat-bridge-uses-find-file-with-prefix-arg ()
  "Prefix arg forces local find-file even when research server is up."
  (let* ((tibetan-cat-zettel-target-server "fake-research")
         (sock-dir (make-temp-file "cat-bridge-sock-" t))
         (sock (expand-file-name "fake-research" sock-dir))
         (zettel-path (expand-file-name "fake-zettel.org" sock-dir))
         (find-file-args nil)
         (emacsclient-called nil))
    (with-temp-file sock (insert ""))
    (with-temp-file zettel-path (insert "fake"))
    (unwind-protect
        (cl-letf (((symbol-value 'server-socket-dir) sock-dir)
                  ((symbol-function 'tibetan-thesaurus--wylie-at-point)
                   (lambda () "mthu"))
                  ((symbol-function 'tibetan-zettel-lookup)
                   (lambda (_w) (list :path zettel-path :title "mthu")))
                  ((symbol-function 'find-file)
                   (lambda (path &rest _) (setq find-file-args path)))
                  ((symbol-function 'call-process)
                   (lambda (program &rest _)
                     (when (string= program "emacsclient")
                       (setq emacsclient-called t)))))
          (tibetan-cat-open-zettel-for-word-at-point '(4))) ; prefix arg = C-u
      (delete-directory sock-dir t))
    (should (equal find-file-args zettel-path))
    (should (not emacsclient-called))))

(ert-deftest tibetan-cat-bridge-falls-back-to-find-file-when-no-server ()
  "No research server present → local find-file."
  (let* ((tibetan-cat-zettel-target-server "does-not-exist-xyz")
         (zettel-path (make-temp-file "fake-zettel-" nil ".org"))
         (find-file-args nil)
         (emacsclient-called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'tibetan-thesaurus--wylie-at-point)
                   (lambda () "mthu"))
                  ((symbol-function 'tibetan-zettel-lookup)
                   (lambda (_w) (list :path zettel-path :title "mthu")))
                  ((symbol-function 'find-file)
                   (lambda (path &rest _) (setq find-file-args path)))
                  ((symbol-function 'call-process)
                   (lambda (program &rest _)
                     (when (string= program "emacsclient")
                       (setq emacsclient-called t)))))
          (tibetan-cat-open-zettel-for-word-at-point nil))
      (delete-file zettel-path))
    (should (equal find-file-args zettel-path))
    (should (not emacsclient-called))))

(provide 'tibetan-cat-zettel-bridge-test)

;;; tibetan-cat-zettel-bridge-test.el ends here
