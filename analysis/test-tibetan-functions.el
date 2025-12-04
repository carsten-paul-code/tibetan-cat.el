;;; Test file to isolate the error

(defun test-tibetan-analyze-arguments (verb multiword-units words)
  "Test version to isolate the error"
  (list "test"))

(defun test-main ()
  "Test main function"
  (let* ((verb '((lemma . "test")))
         (multiword-units '())
         (words '())
         ;; This is the problematic line
         (arg-analysis (test-tibetan-analyze-arguments verb multiword-units words)))
    (message "Result: %s" arg-analysis)))

;; Try it
(test-main)