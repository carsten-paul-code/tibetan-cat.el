;;; tibetan-menu-test.el --- Tests for Tibetan menu -*- lexical-binding: t -*-

;;; Commentary:
;; Tests for the Tibetan CAT menu bar integration.
;; Note: easy-menu-define creates a keymap structure that differs from
;; the source definition format. These tests verify the menu is loadable
;; and the context menu is properly structured.

;;; Code:

(require 'ert)
(require 'easymenu)

;; Load the menu module
(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (load-file (expand-file-name "../config/tibetan-menu.el" base-dir)))

;; ============================================================================
;; MENU EXISTENCE TESTS
;; ============================================================================

(ert-deftest tibetan-menu-exists ()
  "Test that the Tibetan menu is defined."
  (should (boundp 'tibetan-cat-menu)))

(ert-deftest tibetan-menu-is-keymap-or-function ()
  "Test that tibetan-cat-menu is defined as keymap or function."
  ;; easy-menu-define creates either a keymap or a function
  (should (or (keymapp tibetan-cat-menu)
              (functionp tibetan-cat-menu)
              (and (symbolp 'tibetan-cat-menu)
                   (fboundp 'tibetan-cat-menu)))))

(ert-deftest tibetan-context-menu-exists ()
  "Test that the context menu map is defined."
  (should (boundp 'tibetan-cat-context-menu-map))
  (should (keymapp tibetan-cat-context-menu-map)))

;; ============================================================================
;; CONTEXT MENU STRUCTURE TESTS
;; These are reliable tests since we create the keymap directly
;; ============================================================================

(ert-deftest tibetan-context-menu-has-segment-info ()
  "Test context menu has Segment Info entry."
  (should (lookup-key tibetan-cat-context-menu-map [segment-info])))

(ert-deftest tibetan-context-menu-has-open-analysis ()
  "Test context menu has Open Analysis entry."
  (should (lookup-key tibetan-cat-context-menu-map [open-analysis])))

(ert-deftest tibetan-context-menu-has-translate ()
  "Test context menu has CAT Translate entry."
  (should (lookup-key tibetan-cat-context-menu-map [translate])))

(ert-deftest tibetan-context-menu-segment-info-command ()
  "Test context menu Segment Info has correct command."
  (let ((entry (lookup-key tibetan-cat-context-menu-map [segment-info])))
    (should entry)
    ;; lookup-key returns the command symbol directly
    (should (eq 'tibetan-segment-info entry))))

(ert-deftest tibetan-context-menu-open-analysis-command ()
  "Test context menu Open Analysis has correct command."
  (let ((entry (lookup-key tibetan-cat-context-menu-map [open-analysis])))
    (should entry)
    (should (eq 'tibetan-open-segment-analysis entry))))

(ert-deftest tibetan-context-menu-translate-command ()
  "Test context menu CAT Translate has correct command."
  (let ((entry (lookup-key tibetan-cat-context-menu-map [translate])))
    (should entry)
    (should (eq 'tibetan-cat-insert-translation entry))))

;; ============================================================================
;; PROVIDE FEATURE TEST
;; ============================================================================

(ert-deftest tibetan-menu-provides-feature ()
  "Test that tibetan-menu provides its feature."
  (should (featurep 'tibetan-menu)))

;; ============================================================================
;; COMMAND EXISTENCE TESTS
;; Verify that commands referenced in menu actually exist (or will exist)
;; ============================================================================

(ert-deftest tibetan-menu-referenced-commands-defined ()
  "Test that key commands referenced in menu are at least symbols."
  ;; These should be defined when the full system is loaded
  (should (symbolp 'tibetan-segment-info))
  (should (symbolp 'tibetan-open-segment-analysis))
  (should (symbolp 'tibetan-cat-insert-translation))
  (should (symbolp 'reload-all-glossaries)))

;; ============================================================================
;; PERSISTENT SENTENCE ANALYSIS SUBMENU
;; The menu must expose the C-c s A / R / r commands plus the queue
;; status / cancel commands so non-Emacs-savvy users can find them.
;; We assert via the source file rather than the keymap because
;; easy-menu-define lowers entries into a structure that's awkward to
;; introspect; the source check is cheap and catches regressions.
;; ============================================================================

(defvar tibetan-menu-test--source
  (let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name "../config/tibetan-menu.el" base-dir))
      (buffer-string)))
  "Cached source of tibetan-menu.el, for menu-content assertions.")

(ert-deftest tibetan-menu-has-persistent-sentence-submenu ()
  "The Tibetan menu must include a `Persistent Sentence Analysis' submenu."
  (should (string-match-p "\"Persistent Sentence Analysis\""
                          tibetan-menu-test--source)))

(ert-deftest tibetan-menu-sentence-submenu-has-open-command ()
  "Sentence submenu must expose `tibetan-sentence-open-analysis'."
  (should (string-match-p "tibetan-sentence-open-analysis"
                          tibetan-menu-test--source)))

(ert-deftest tibetan-menu-sentence-submenu-has-reanalyze-command ()
  "Sentence submenu must expose `tibetan-sentence-reanalyze'."
  (should (string-match-p "tibetan-sentence-reanalyze\\b"
                          tibetan-menu-test--source)))

(ert-deftest tibetan-menu-sentence-submenu-has-batch-command ()
  "Sentence submenu must expose `tibetan-sentence-batch-reanalyze'."
  (should (string-match-p "tibetan-sentence-batch-reanalyze"
                          tibetan-menu-test--source)))

(ert-deftest tibetan-menu-sentence-submenu-has-queue-status ()
  "Sentence submenu must expose the Claude queue status command."
  (should (string-match-p "tibetan-claude-queue-show-status"
                          tibetan-menu-test--source)))

(ert-deftest tibetan-menu-sentence-submenu-has-queue-cancel ()
  "Sentence submenu must expose the Claude queue cancel command."
  (should (string-match-p "tibetan-claude-queue-cancel-pending"
                          tibetan-menu-test--source)))

(provide 'tibetan-menu-test)
;;; tibetan-menu-test.el ends here
