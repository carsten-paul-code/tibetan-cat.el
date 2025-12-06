;;; test-wylie-fix.el --- Test the fixed Wylie converter

(load-file "/Users/cp/.emacs.d/tibetan-wylie-converter-fixed.el")

(defun test-wylie-conversion ()
  "Test Wylie conversion for known problematic cases."
  (interactive)
  (let ((test-cases '(
        ("བྱའི" "bya'i")
        ("གསལ" "gsal")
        ("བའི" "ba'i")
        ("མའི་ལྟ་བ" "ma'i lta ba")
        ("ཙམ" "tsam")
        ("ཤེས་བྱའི་གནས་ལུགས་གསལ་བའི་ཕྱིར" "shes bya'i gnas lugs gsal ba'i phyir")
        )))
    (with-output-to-temp-buffer "*Wylie Test Results*"
      (princ "=== WYLIE CONVERSION TEST ===\n\n")
      (dolist (test test-cases)
        (let* ((tibetan (car test))
               (expected (cadr test))
               (actual (tibetan-to-wylie-fixed tibetan))
               (status (if (string= actual expected) "✓ PASS" "✗ FAIL")))
          (princ (format "%s\n" status))
          (princ (format "  Tibetan:  %s\n" tibetan))
          (princ (format "  Expected: %s\n" expected))
          (princ (format "  Actual:   %s\n\n" actual)))))))

(test-wylie-conversion)
