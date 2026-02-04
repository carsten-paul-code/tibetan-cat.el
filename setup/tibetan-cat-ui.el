;;; tibetan-cat-ui.el --- Optional UI enhancements for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Optional UI module providing a polished editing environment.
;; Install with: (require 'tibetan-cat-ui) in your init.el
;;
;; Provides:
;; - Treemacs file browser (left sidebar)
;; - Doom modeline
;; - Dashboard with Tibetan CAT quick links
;; - Beacon (cursor highlight on jump)
;; - Which-key (keybinding hints)
;; - Dimmer (dim inactive windows)
;; - Winner mode (undo window layouts)
;; - Org-bullets (prettier org headings)
;; - Tibetan font configuration

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; PACKAGE INSTALLATION HELPER
;; ============================================================================

(defun tibetan-cat-ui--ensure-package (pkg)
  "Ensure PKG is installed."
  (unless (package-installed-p pkg)
    (condition-case nil
        (package-install pkg)
      (error (message "  Could not install %s" pkg)))))

(defun tibetan-cat-ui--ensure-packages ()
  "Install all UI packages."
  (require 'package)
  (unless package-archive-contents
    (package-refresh-contents))
  (dolist (pkg '(treemacs treemacs-projectile
                 doom-modeline all-the-icons
                 dashboard
                 beacon dimmer
                 which-key
                 winner
                 org-bullets
                 vertico orderless marginalia
                 company
                 projectile
                 magit))
    (tibetan-cat-ui--ensure-package pkg)))

;; ============================================================================
;; TREEMACS (File Browser)
;; ============================================================================

(defun tibetan-cat-ui--setup-treemacs ()
  "Configure treemacs file browser."
  (when (require 'treemacs nil t)
    (setq treemacs-width 30
          treemacs-show-hidden-files t
          treemacs-follow-mode nil)
    (treemacs-filewatch-mode t)
    (global-set-key (kbd "C-c w") 'treemacs)
    (global-set-key (kbd "C-c C-w") 'treemacs-select-window)
    ;; Auto-open on GUI startup
    (when (display-graphic-p)
      (add-hook 'emacs-startup-hook
                (lambda ()
                  (run-with-idle-timer 1 nil
                    (lambda ()
                      (treemacs-select-window)
                      (other-window 1))))))))

;; ============================================================================
;; DOOM MODELINE
;; ============================================================================

(defun tibetan-cat-ui--setup-modeline ()
  "Configure doom modeline."
  (when (require 'doom-modeline nil t)
    (doom-modeline-mode 1)
    (setq doom-modeline-height 28
          doom-modeline-icon t
          doom-modeline-major-mode-icon t)))

;; ============================================================================
;; DASHBOARD
;; ============================================================================

(defun tibetan-cat-ui--setup-dashboard ()
  "Configure startup dashboard."
  (when (require 'dashboard nil t)
    (dashboard-setup-startup-hook)
    (setq dashboard-banner-logo-title "Tibetan CAT - Computer-Assisted Translation"
          dashboard-startup-banner 'logo
          dashboard-center-content t
          dashboard-items '((recents . 10)
                            (bookmarks . 5))
          dashboard-set-heading-icons t
          dashboard-set-file-icons t)))

;; ============================================================================
;; VISUAL ENHANCEMENTS
;; ============================================================================

(defun tibetan-cat-ui--setup-visuals ()
  "Configure visual enhancements."
  ;; Beacon - highlight cursor on jump
  (when (require 'beacon nil t)
    (beacon-mode 1))
  ;; Dimmer - dim inactive windows
  (when (require 'dimmer nil t)
    (dimmer-configure-which-key)
    (dimmer-mode t))
  ;; Which-key - keybinding hints
  (when (require 'which-key nil t)
    (which-key-mode))
  ;; Winner - undo window layouts
  (when (require 'winner nil t)
    (winner-mode 1))
  ;; Org-bullets
  (when (require 'org-bullets nil t)
    (add-hook 'org-mode-hook (lambda () (org-bullets-mode 1)))))

;; ============================================================================
;; COMPLETION (Vertico + Orderless)
;; ============================================================================

(defun tibetan-cat-ui--setup-completion ()
  "Configure modern completion."
  (when (require 'vertico nil t)
    (vertico-mode))
  (when (require 'orderless nil t)
    (setq completion-styles '(orderless basic)))
  (when (require 'marginalia nil t)
    (marginalia-mode)))

;; ============================================================================
;; TIBETAN FONTS
;; ============================================================================

(defun tibetan-cat-ui--setup-fonts ()
  "Configure fonts for Tibetan script display."
  (when (display-graphic-p)
    ;; Tibetan fonts (in priority order)
    (cl-loop for font in '("Jomolhari" "Tibetan Machine Uni"
                            "Noto Serif Tibetan" "Noto Sans Tibetan")
             when (member font (font-family-list))
             do (set-fontset-font t 'tibetan (font-spec :family font))
             and return t)
    ;; Devanagari (Sanskrit)
    (when (member "Noto Sans Devanagari" (font-family-list))
      (set-fontset-font t 'devanagari
                        (font-spec :family "Noto Sans Devanagari")))))

;; ============================================================================
;; MASTER SETUP
;; ============================================================================

(defun tibetan-cat-ui-install ()
  "Install all UI packages and configure them."
  (interactive)
  (message "Installing Tibetan CAT UI packages...")
  (tibetan-cat-ui--ensure-packages)
  (tibetan-cat-ui-setup)
  (message "UI setup complete! Restart Emacs for full effect."))

(defun tibetan-cat-ui-setup ()
  "Activate all UI enhancements (packages must already be installed)."
  (interactive)
  (tibetan-cat-ui--setup-fonts)
  (tibetan-cat-ui--setup-treemacs)
  (tibetan-cat-ui--setup-modeline)
  (tibetan-cat-ui--setup-dashboard)
  (tibetan-cat-ui--setup-visuals)
  (tibetan-cat-ui--setup-completion)
  (message "Tibetan CAT UI configured"))

(provide 'tibetan-cat-ui)
;;; tibetan-cat-ui.el ends here
