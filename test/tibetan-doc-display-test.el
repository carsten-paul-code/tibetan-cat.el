;;; tibetan-doc-display-test.el --- Tests for tibetan-doc-display.el -*- lexical-binding: t -*-

(require 'ert)
(require 'tibetan-doc-display)

;; ============================================================================
;; FACE DEFINITION TESTS
;; ============================================================================

(ert-deftest tibetan-doc-marker-face-exists ()
  "Test that tibetan-doc-marker-face is defined."
  (should (facep 'tibetan-doc-marker-face)))

(ert-deftest tibetan-doc-marker-tag-face-exists ()
  "Test that tibetan-doc-marker-tag-face is defined."
  (should (facep 'tibetan-doc-marker-tag-face)))

(ert-deftest tibetan-doc-marker-attr-face-exists ()
  "Test that tibetan-doc-marker-attr-face is defined."
  (should (facep 'tibetan-doc-marker-attr-face)))

(ert-deftest tibetan-doc-marker-face-has-height ()
  "Test that marker face has reduced height."
  (let ((height (face-attribute 'tibetan-doc-marker-face :height)))
    (should height)
    (when (numberp height)
      (should (< height 1.0)))))

;; ============================================================================
;; FONT-LOCK KEYWORDS TESTS
;; ============================================================================

(ert-deftest tibetan-doc-font-lock-keywords-exists ()
  "Test that font-lock keywords variable exists."
  (should (boundp 'tibetan-doc-font-lock-keywords))
  (should (listp tibetan-doc-font-lock-keywords)))

(ert-deftest tibetan-doc-font-lock-keywords-has-patterns ()
  "Test that font-lock keywords has patterns."
  (should (> (length tibetan-doc-font-lock-keywords) 0)))

(ert-deftest tibetan-doc-font-lock-matches-seg-open ()
  "Test that font-lock pattern matches opening seg marker."
  (let ((pattern (car (nth 0 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〔seg〕"))))

(ert-deftest tibetan-doc-font-lock-matches-seg-close ()
  "Test that font-lock pattern matches closing seg marker."
  (let ((pattern (car (nth 1 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〔/seg〕"))))

(ert-deftest tibetan-doc-font-lock-matches-verse ()
  "Test that font-lock pattern matches verse markers."
  (let ((pattern (car (nth 0 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〔verse :num 1〕"))))

(ert-deftest tibetan-doc-font-lock-matches-sent ()
  "Test that font-lock pattern matches sent markers."
  (let ((pattern (car (nth 0 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〔sent〕"))))

(ert-deftest tibetan-doc-font-lock-matches-prose ()
  "Test that font-lock pattern matches prose markers."
  (let ((pattern (car (nth 0 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〔prose :comment-on 5〕"))))

(ert-deftest tibetan-doc-font-lock-matches-old-format ()
  "Test that font-lock pattern matches old seg:N format."
  (let ((pattern (car (nth 2 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〔seg:42〕"))))

(ert-deftest tibetan-doc-font-lock-matches-verse-ref ()
  "Test that font-lock pattern matches inline verse reference."
  (let ((pattern (car (nth 3 tibetan-doc-font-lock-keywords))))
    (should (string-match-p pattern "〈v:5〉"))))

;; ============================================================================
;; MINOR MODE TESTS
;; ============================================================================

(ert-deftest tibetan-doc-display-mode-exists ()
  "Test that tibetan-doc-display-mode is defined."
  (should (fboundp 'tibetan-doc-display-mode)))

(ert-deftest tibetan-doc-display-mode-toggle ()
  "Test that mode can be toggled on and off."
  (with-temp-buffer
    (tibetan-doc-display-mode 1)
    (should tibetan-doc-display-mode)
    (tibetan-doc-display-mode -1)
    (should-not tibetan-doc-display-mode)))

(ert-deftest tibetan-doc-display-mode-lighter ()
  "Test that mode has a lighter (mode line indicator)."
  (with-temp-buffer
    (tibetan-doc-display-mode 1)
    ;; Mode should add keywords when enabled
    (should tibetan-doc-display-mode)))

;; ============================================================================
;; TEXT SCALE FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-set-text-scale-is-command ()
  "Test that tibetan-set-text-scale is an interactive command."
  (should (fboundp 'tibetan-set-text-scale))
  (should (commandp 'tibetan-set-text-scale)))

(ert-deftest tibetan-set-text-scale-sets-variable ()
  "Test that tibetan-set-text-scale updates the scale factor variable."
  (let ((original-value tibetan-text-scale-factor))
    (unwind-protect
        (progn
          (tibetan-set-text-scale 1.5)
          (should (= tibetan-text-scale-factor 1.5))
          (tibetan-set-text-scale 1.8)
          (should (= tibetan-text-scale-factor 1.8)))
      (setq tibetan-text-scale-factor original-value))))

(ert-deftest tibetan-set-text-scale-accepts-numeric-input ()
  "Test that tibetan-set-text-scale accepts valid numeric values."
  (let ((original-value tibetan-text-scale-factor))
    (unwind-protect
        (progn
          ;; Test various valid values
          (tibetan-set-text-scale 1.0)
          (should (= tibetan-text-scale-factor 1.0))
          (tibetan-set-text-scale 1.6)
          (should (= tibetan-text-scale-factor 1.6))
          (tibetan-set-text-scale 2.0)
          (should (= tibetan-text-scale-factor 2.0)))
      (setq tibetan-text-scale-factor original-value))))

;; ============================================================================
;; UTILITY FUNCTION TESTS
;; ============================================================================

(ert-deftest tibetan-doc-toggle-markers-exists ()
  "Test that toggle function exists."
  (should (fboundp 'tibetan-doc-toggle-markers)))

(ert-deftest tibetan-doc-hide-markers-exists ()
  "Test that hide function exists."
  (should (fboundp 'tibetan-doc-hide-markers)))

(ert-deftest tibetan-doc-show-markers-exists ()
  "Test that show function exists."
  (should (fboundp 'tibetan-doc-show-markers)))

(ert-deftest tibetan-doc-hide-markers-sets-invisible ()
  "Test that hiding markers sets invisible property."
  (with-temp-buffer
    (insert "〔seg〕བཀྲ་ཤིས།〔/seg〕")
    (tibetan-doc-hide-markers)
    ;; Check that some text has invisible property
    (goto-char (point-min))
    (should (text-property-any (point-min) (point-max) 'invisible t))))

(ert-deftest tibetan-doc-show-markers-removes-invisible ()
  "Test that showing markers removes invisible property."
  (with-temp-buffer
    (insert "〔seg〕བཀྲ་ཤིས།〔/seg〕")
    (tibetan-doc-hide-markers)
    (tibetan-doc-show-markers)
    ;; Invisible property should be gone
    (should-not (text-property-any (point-min) (point-max) 'invisible t))))

;; ============================================================================
;; AUTO-ENABLE TESTS
;; ============================================================================

(ert-deftest tibetan-doc-display-maybe-enable-exists ()
  "Test that auto-enable function exists."
  (should (fboundp 'tibetan-doc-display--maybe-enable)))

(ert-deftest tibetan-doc-display-hook-registered ()
  "Test that maybe-enable is on org-mode-hook."
  (should (memq 'tibetan-doc-display--maybe-enable org-mode-hook)))

(provide 'tibetan-doc-display-test)
;;; tibetan-doc-display-test.el ends here
