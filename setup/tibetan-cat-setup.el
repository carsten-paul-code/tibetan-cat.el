;;; tibetan-cat-setup.el --- First-time setup for Tibetan CAT -*- lexical-binding: t -*-

;;; Commentary:
;; Handles first-time setup and integration with the user's Emacs config.
;;
;; Usage:
;;   M-x tibetan-cat-install
;;
;; This will:
;; 1. Check prerequisites (Emacs version, fonts)
;; 2. Install required Emacs packages
;; 3. Optionally add load line to init.el
;; 4. Load the system
;;
;; For unattended install (e.g. from shell script):
;;   (tibetan-cat-install t)

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; CONSTANTS
;; ============================================================================

(defvar tibetan-cat-setup-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing setup files.")

(defvar tibetan-cat-base-dir
  (file-name-directory (directory-file-name tibetan-cat-setup-dir))
  "Base directory of tibetan-cat.el installation.")

;; ============================================================================
;; PREREQUISITE CHECKS
;; ============================================================================

(defun tibetan-cat-setup--check-emacs-version ()
  "Check that Emacs version is sufficient."
  (if (version< emacs-version "27.1")
      (progn (message "  [FAIL] Emacs %s found, need 27.1+" emacs-version) nil)
    (message "  [OK] Emacs %s" emacs-version)
    t))

(defun tibetan-cat-setup--check-org ()
  "Check that org-mode is available."
  (condition-case nil
      (progn
        (require 'org)
        (message "  [OK] Org-mode %s" (org-version))
        t)
    (error
     (message "  [FAIL] Org-mode not found")
     nil)))

(defun tibetan-cat-setup--check-fonts ()
  "Check for Tibetan fonts."
  (if (not (display-graphic-p))
      (progn (message "  [SKIP] Font check (terminal mode)") t)
    (let ((found nil))
      (dolist (font '("Jomolhari" "Tibetan Machine Uni" "Noto Serif Tibetan" "Noto Sans Tibetan"))
        (when (member font (font-family-list))
          (setq found font)))
      (if found
          (progn (message "  [OK] Tibetan font: %s" found) t)
        (message "  [WARN] No Tibetan font found!")
        (message "         Install Jomolhari: brew install font-jomolhari")
        (message "         Or Noto:           brew install font-noto-serif-tibetan")
        ;; Not fatal - system works without, just no Tibetan display
        t))))

(defun tibetan-cat-setup--check-glossaries ()
  "Check that glossary data files exist."
  (let ((glossary-dir (expand-file-name "data/glossaries/" tibetan-cat-base-dir))
        (required '("rangjung-yeshe-tibetan.txt" "hopkins-sample.txt"
                     "unified-tibetan.txt" "tibetan-english.tsv")))
    (let ((missing '()))
      (dolist (f required)
        (unless (file-exists-p (expand-file-name f glossary-dir))
          (push f missing)))
      (if missing
          (progn
            (message "  [WARN] Missing glossaries: %s" (string-join missing ", "))
            nil)
        (message "  [OK] All glossary files present")
        t))))

;; ============================================================================
;; PACKAGE INSTALLATION
;; ============================================================================

(defvar package-archive-contents)

(defun tibetan-cat-setup--ensure-packages ()
  "Install required Emacs packages."
  (require 'package)
  (unless package-archive-contents
    (package-refresh-contents))
  (let ((required '(cl-lib))
        (optional '(company popup which-key))
        (installed 0))
    ;; Required packages
    (dolist (pkg required)
      (unless (package-installed-p pkg)
        (condition-case nil
            (progn (package-install pkg)
                   (setq installed (1+ installed)))
          (error (message "  [WARN] Could not install %s" pkg)))))
    ;; Optional packages (don't fail if missing)
    (dolist (pkg optional)
      (unless (package-installed-p pkg)
        (condition-case nil
            (progn (package-install pkg)
                   (setq installed (1+ installed)))
          (error nil))))
    (if (> installed 0)
        (message "  [OK] Installed %d packages" installed)
      (message "  [OK] All packages already present"))
    t))

;; ============================================================================
;; FONT INSTALLATION (macOS)
;; ============================================================================

(defun tibetan-cat-setup--install-fonts-macos ()
  "Install Tibetan fonts on macOS using Homebrew."
  (interactive)
  (if (not (eq system-type 'darwin))
      (message "Font auto-install only supported on macOS")
    (if (not (executable-find "brew"))
        (message "Homebrew not found. Install fonts manually.")
      (message "Installing Tibetan fonts via Homebrew...")
      (shell-command "brew install --cask font-jomolhari 2>/dev/null || brew install font-jomolhari 2>/dev/null")
      (shell-command "brew install --cask font-noto-serif-tibetan 2>/dev/null || brew install font-noto-serif-tibetan 2>/dev/null")
      (message "  Fonts installed. Restart Emacs to use them."))))

;; ============================================================================
;; INIT.EL INTEGRATION
;; ============================================================================

(defun tibetan-cat-setup--init-line ()
  "Generate the line to add to init.el."
  (format "(load \"%stibetan-cat.el\")" tibetan-cat-base-dir))

(defun tibetan-cat-setup--already-in-init-p ()
  "Check if tibetan-cat is already configured in init.el."
  (let ((init-file (expand-file-name "init.el" user-emacs-directory)))
    (when (file-exists-p init-file)
      (with-temp-buffer
        (insert-file-contents init-file)
        (or (search-forward "tibetan-cat" nil t)
            (search-forward "tibetan-cat.el" nil t))))))

(defun tibetan-cat-setup--add-to-init ()
  "Add tibetan-cat load line to init.el."
  (let ((init-file (expand-file-name "init.el" user-emacs-directory)))
    (if (tibetan-cat-setup--already-in-init-p)
        (progn (message "  [OK] Already configured in init.el") t)
      (with-temp-buffer
        (when (file-exists-p init-file)
          (insert-file-contents init-file))
        (goto-char (point-max))
        ;; Find position before custom-set-variables if present
        (goto-char (point-min))
        (let ((insert-pos (if (search-forward "(custom-set-variables" nil t)
                              (line-beginning-position)
                            (point-max))))
          (goto-char insert-pos)
          (insert "\n;; ============================================================================\n")
          (insert ";; TIBETAN CAT (Computer-Assisted Translation)\n")
          (insert ";; ============================================================================\n")
          (insert (format "(load \"%stibetan-cat.el\")\n\n"
                          tibetan-cat-base-dir))
          (write-region (point-min) (point-max) init-file)))
      (message "  [OK] Added to %s" init-file)
      t)))

;; ============================================================================
;; FONT SETUP (for init.el)
;; ============================================================================

(declare-function set-fontset-font "fontset" (fontset script font &optional frame add))

(defun tibetan-cat-setup--configure-fonts ()
  "Configure Tibetan font display."
  (when (display-graphic-p)
    (dolist (font '("Jomolhari" "Tibetan Machine Uni" "Noto Serif Tibetan" "Noto Sans Tibetan"))
      (when (member font (font-family-list))
        (set-fontset-font t 'tibetan (font-spec :family font))
        (message "  [OK] Tibetan font configured: %s" font)
        (cl-return)))))

;; ============================================================================
;; MAIN INSTALL COMMAND
;; ============================================================================

;;;###autoload
(defun tibetan-cat-install (&optional non-interactive)
  "Install and configure Tibetan CAT system.
If NON-INTERACTIVE is non-nil, skip prompts and use defaults."
  (interactive)
  (let ((buf (get-buffer-create "*Tibetan CAT Setup*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "================================================================\n")
      (insert "  Tibetan CAT - Installation & Setup\n")
      (insert "================================================================\n\n")
      (insert (format "Install directory: %s\n\n" tibetan-cat-base-dir)))
    (display-buffer buf)

    (with-current-buffer buf
      ;; Step 1: Prerequisites
      (insert "--- Checking prerequisites ---\n")
      (let ((ok t))
        (unless (tibetan-cat-setup--check-emacs-version) (setq ok nil))
        (unless (tibetan-cat-setup--check-org) (setq ok nil))
        (tibetan-cat-setup--check-fonts)
        (tibetan-cat-setup--check-glossaries)
        (insert "\n")

        (unless ok
          (insert "\n[ABORT] Prerequisites not met.\n")
          (goto-char (point-min))
          (read-only-mode 1)
          (error "Prerequisites not met"))

        ;; Step 2: Packages
        (insert "--- Installing packages ---\n")
        (tibetan-cat-setup--ensure-packages)
        (insert "\n")

        ;; Step 3: Fonts
        (when (and (eq system-type 'darwin)
                   (executable-find "brew")
                   (not (tibetan-cat-setup--check-fonts)))
          (when (or non-interactive
                    (y-or-n-p "Install Tibetan fonts via Homebrew? "))
            (insert "--- Installing fonts ---\n")
            (tibetan-cat-setup--install-fonts-macos)
            (insert "\n")))

        ;; Step 4: Configure init.el
        (insert "--- Configuring Emacs ---\n")
        (if (tibetan-cat-setup--already-in-init-p)
            (message "  [OK] Already configured in init.el")
          (when (or non-interactive
                    (y-or-n-p "Add Tibetan CAT to your init.el? "))
            (tibetan-cat-setup--add-to-init)))
        (insert "\n")

        ;; Step 5: Load the system
        (insert "--- Loading Tibetan CAT ---\n")
        (condition-case err
            (progn
              (load (expand-file-name "tibetan-cat.el" tibetan-cat-base-dir))
              (message "  [OK] Tibetan CAT loaded successfully")
              (insert "\n"))
          (error
           (message "  [WARN] Load error: %s" (error-message-string err))
           (insert "\n")))

        ;; Done
        (insert "================================================================\n")
        (insert "  Installation complete!\n")
        (insert "================================================================\n\n")
        (insert "Quick start:\n")
        (insert "  1. Open a .org file with Tibetan text\n")
        (insert "  2. Place cursor on a Tibetan segment\n")
        (insert "  3. Press C-c u A to open segment analysis\n")
        (insert "  4. Press C-c u B to batch-analyze all segments\n\n")
        (insert "  M-x tibetan-cat-setup  for keybinding reference\n")
        (insert "  See Tibetan menu in the menu bar\n")

        (goto-char (point-min))
        (read-only-mode 1)))))

;; ============================================================================
;; STATUS / HEALTH CHECK
;; ============================================================================

;;;###autoload
(defun tibetan-cat-status ()
  "Show Tibetan CAT system status and health check."
  (interactive)
  (message "--- Tibetan CAT Status ---")
  (message "Base dir: %s" tibetan-cat-base-dir)
  (message "Comprehensive vocabulary: %s entries"
           (if (and (boundp 'tibetan-comprehensive-vocabulary)
                    tibetan-comprehensive-vocabulary)
               (hash-table-count tibetan-comprehensive-vocabulary)
             "NOT LOADED"))
  (message "Rangjung Yeshe: %s entries"
           (if (and (boundp 'tibetan-rangjung-yeshe-vocabulary)
                    tibetan-rangjung-yeshe-vocabulary)
               (hash-table-count tibetan-rangjung-yeshe-vocabulary)
             "not yet loaded (lazy)"))
  (message "DharmaMitra: %s"
           (if (fboundp 'tibetan-get-dharmamitra-translation)
               "available" "not loaded"))
  (message "Verb classifier: %s"
           (if (fboundp 'tibetan-classify-verb)
               "available" "not loaded"))
  (message "Bialek grammar: %s"
           (if (fboundp 'tibetan-analyze-grammar-bialek)
               "available" "not loaded")))

(provide 'tibetan-cat-setup)
;;; tibetan-cat-setup.el ends here
