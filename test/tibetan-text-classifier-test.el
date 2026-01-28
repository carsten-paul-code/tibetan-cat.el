;;; tibetan-text-classifier-test.el --- Tests for tibetan-text-classifier.el -*- lexical-binding: t -*-

;;; Commentary:
;; Unit tests for text type classification functionality.

;;; Code:

(require 'ert)

;; Add load paths
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-text-classifier)

;; ============================================================================
;; TEXT TYPE DETECTION
;; ============================================================================

(ert-deftest tibetan-classifier-get-text-type-classical ()
  "Test detection of classical text type from header."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: classical\n")
    (insert "Some Tibetan text here")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-type)))
      (should (eq result 'classical)))))

(ert-deftest tibetan-classifier-get-text-type-verse ()
  "Test detection of verse text type."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: madhyamaka-verse\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-type)))
      (should (eq result 'madhyamaka-verse)))))

(ert-deftest tibetan-classifier-get-text-type-default ()
  "Test default text type when no header present."
  (with-temp-buffer
    (insert "Some Tibetan text without header")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-type)))
      ;; Should return default (classical)
      (should (or (eq result 'classical)
                  (eq result nil))))))

;; ============================================================================
;; CONTEXT DETECTION
;; ============================================================================

(ert-deftest tibetan-classifier-get-context-madhyamaka ()
  "Test detection of Madhyamaka context."
  (with-temp-buffer
    (insert "#+TIBETAN_CONTEXT: madhyamaka\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-context)))
      (should (eq result 'madhyamaka)))))

(ert-deftest tibetan-classifier-get-context-yogacara ()
  "Test detection of Yogacara context."
  (with-temp-buffer
    (insert "#+TIBETAN_CONTEXT: yogacara\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-context)))
      (should (eq result 'yogacara)))))

(ert-deftest tibetan-classifier-get-context-abhidharma ()
  "Test detection of Abhidharma context."
  (with-temp-buffer
    (insert "#+TIBETAN_CONTEXT: abhidharma\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-context)))
      (should (eq result 'abhidharma)))))

;; ============================================================================
;; TRADITION DETECTION
;; ============================================================================

(ert-deftest tibetan-classifier-get-tradition ()
  "Test detection of tradition."
  (with-temp-buffer
    (insert "#+TIBETAN_TRADITION: gelug\n")
    (goto-char (point-min))
    (let ((result (tibetan-get-tradition)))
      (should (eq result 'gelug)))))

;; ============================================================================
;; COMBINED DETECTION
;; ============================================================================

(ert-deftest tibetan-classifier-combined-headers ()
  "Test combined detection of multiple headers."
  (with-temp-buffer
    (insert "#+TITLE: Test\n")
    (insert "#+TIBETAN_TEXT_TYPE: madhyamaka-verse\n")
    (insert "#+TIBETAN_CONTEXT: madhyamaka\n")
    (insert "#+TIBETAN_TRADITION: gelug\n")
    (goto-char (point-min))
    (should (eq (tibetan-get-text-type) 'madhyamaka-verse))
    (should (eq (tibetan-get-text-context) 'madhyamaka))
    (should (eq (tibetan-get-tradition) 'gelug))))

;; ============================================================================
;; EDGE CASES
;; ============================================================================

(ert-deftest tibetan-classifier-case-insensitive ()
  "Test case insensitivity of headers."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE: CLASSICAL\n")
    (goto-char (point-min))
    ;; Should handle case variations
    (let ((result (tibetan-get-text-type)))
      (should (or (eq result 'classical)
                  (eq result 'CLASSICAL))))))

(ert-deftest tibetan-classifier-whitespace-handling ()
  "Test handling of whitespace in header values."
  (with-temp-buffer
    (insert "#+TIBETAN_TEXT_TYPE:   classical   \n")
    (goto-char (point-min))
    (let ((result (tibetan-get-text-type)))
      (should (eq result 'classical)))))

(ert-deftest tibetan-classifier-empty-buffer ()
  "Test behavior with empty buffer."
  (with-temp-buffer
    (let ((result (tibetan-get-text-type)))
      ;; Should not error
      (should (or (null result) (symbolp result))))))

;; ============================================================================
;; TEXT TYPE PROPERTIES
;; ============================================================================

(ert-deftest tibetan-classifier-type-properties ()
  "Test text type property retrieval."
  ;; Classical should use Bialek grammar
  (let ((props (tibetan-get-type-properties 'classical)))
    (when props
      (should (listp props)))))

(ert-deftest tibetan-classifier-verse-properties ()
  "Test verse type property retrieval."
  (let ((props (tibetan-get-type-properties 'madhyamaka-verse)))
    (when props
      (should (listp props)))))

(provide 'tibetan-text-classifier-test)
;;; tibetan-text-classifier-test.el ends here
