;;; tibetan-portfolio-test.el --- freeze-draft tests -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'tibetan-portfolio)

(defmacro tibetan-portfolio-test--fixture (&rest body)
  "Temp dir with a Portfolio-shaped source: Sentence 1 has drafts on two
segments (joined on freeze), Sentence 2 has an empty draft (excluded),
Sentence 3 has one draft.  Binds dir, source-file for BODY."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "tibetan-portfolio-" t))
          (source-file (expand-file-name "deb-ther.org" dir)))
     (unwind-protect
         (progn
           (with-temp-buffer
             (insert "#+TITLE: Deb ther Portfolio\n#+TIBETAN_DEFER_MT: t\n\n"
                     "* Tibetan Text\n"
                     "*** Sentence 1\n"
                     "**** Segment 1\nབཀྲ་ཤིས།\n"
                     "**** Working Translation\nDE: Glück.\nEN: Fortune.\n"
                     "**** Segment 2\nབདེ་ལེགས།\n"
                     "**** Working Translation\nDE: Wohlergehen.\nEN: Wellbeing.\n"
                     "*** Sentence 2\n"
                     "**** Segment 3\nཨོཾ།\n"
                     "**** Working Translation\n\n"
                     "*** Sentence 3\n"
                     "**** Segment 4\nསྭསྟི།\n"
                     "**** Working Translation\nDE: Heil.\nEN: Svasti.\n")
             (write-region (point-min) (point-max) source-file nil 'silent))
           ,@body)
       (delete-directory dir t))))

(ert-deftest tibetan-portfolio-collects-per-sentence-drafts ()
  "Drafts are collected per sentence; multiple segment drafts of one
sentence are joined; sentences with only empty drafts are excluded."
  (tibetan-portfolio-test--fixture
    (let ((drafts (tibetan-portfolio--collect-working-translations
                   source-file)))
      (should (= (length drafts) 2))
      (should (= (plist-get (nth 0 drafts) :sent-num) 1))
      (should (string-match-p "Glück" (plist-get (nth 0 drafts) :body)))
      (should (string-match-p "Wohlergehen" (plist-get (nth 0 drafts) :body)))
      (should (= (plist-get (nth 1 drafts) :sent-num) 3))
      (should (string-match-p "Svasti" (plist-get (nth 1 drafts) :body))))))

(ert-deftest tibetan-portfolio-freeze-creates-protocol-and-refuses-refreeze ()
  "First freeze writes timestamped per-sentence blocks into the protocol
and reports :frozen 2; a second freeze skips both (once-only) and does
not duplicate blocks."
  (tibetan-portfolio-test--fixture
    (let* ((r1 (tibetan-portfolio-freeze-draft source-file))
           (protocol (plist-get r1 :protocol)))
      (should (= (plist-get r1 :frozen) 2))
      (should (= (plist-get r1 :skipped) 0))
      (should (file-exists-p protocol))
      (let ((r2 (tibetan-portfolio-freeze-draft source-file)))
        (should (= (plist-get r2 :frozen) 0))
        (should (= (plist-get r2 :skipped) 2)))
      (with-temp-buffer
        (insert-file-contents protocol)
        (let ((text (buffer-string)))
          ;; one frozen block per sentence, not duplicated
          (should (= 1 (let ((count 0) (start 0))
                         (while (string-match
                                 (regexp-quote "(Sentence 1)") text start)
                           (setq count (1+ count) start (match-end 0)))
                         count)))
          (should (string-match-p "\\*\\* Own draft (frozen .*+) (Sentence 1)" text))
          (should (string-match-p "DE: Glück\\." text))
          (should (string-match-p "\\*\\* MT versions" text))
          (should (string-match-p "\\*\\* Adopted changes" text)))))))

(ert-deftest tibetan-portfolio-freeze-errors-without-drafts ()
  "Freezing a source without any non-empty draft signals a user-error."
  (let* ((dir (make-temp-file "tibetan-portfolio-empty-" t))
         (source-file (expand-file-name "empty.org" dir)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert "#+TITLE: Empty\n\n* Tibetan Text\n*** Sentence 1\n"
                    "**** Segment 1\nབཀྲ་ཤིས།\n"
                    "**** Working Translation\n\n")
            (write-region (point-min) (point-max) source-file nil 'silent))
          (should-error (tibetan-portfolio-freeze-draft source-file)
                        :type 'user-error))
      (delete-directory dir t))))

(provide 'tibetan-portfolio-test)
;;; tibetan-portfolio-test.el ends here
