;;; tibetan-steinert.el --- SQLite-backed Steinert dictionary lookup -*- lexical-binding: t -*-

;;; Commentary:
;; Provides lookup against Christian Steinert's aggregated Tibetan dictionary
;; sources (dictionary.christian-steinert.de — 800k+ entries across 60+
;; glossaries), stored locally as a SQLite database built by
;; `scripts/build-steinert-db.py'.
;;
;; Two public entry points:
;;
;;   (tibetan-steinert-lookup WORD)
;;       Return a list of plists, one per matching glossary entry:
;;           (:source :wylie :gloss :sanskrit)
;;       WORD may be Tibetan script or Wylie; both are tried.
;;
;;   (tibetan-steinert-sanskrit-for WORD)
;;       Return a deduplicated "; "-joined Sanskrit string built from the
;;       Sanskrit-indexed sources (Mahāvyutpatti, Hopkins-Skt, 84000-Skt,
;;       Lokesh Chandra, Negi, Yogācārabhūmi), or nil if none found.
;;
;; The connection is opened on first use and kept open for the session.
;; If the DB is missing, lookup silently returns nil (so the rest of the
;; tool continues to work without Steinert data). Run
;; `make build-steinert' (or the Python script directly) to build it.
;;
;; License note: code is part of tibetan-cat.el (GPL). The dictionary data
;; is copyright of the respective compilers — see NOTICE-steinert.md.

;;; Code:

(require 'cl-lib)
(require 'sqlite nil t) ;; built-in since Emacs 29
(require 'url-util)     ;; for url-hexify-string in URL generation

;; Byte-compile-time declarations for the SQLite C-builtins (Emacs
;; 29+).  All call sites are runtime-gated by
;; `tibetan-steinert-available-p' (which checks `featurep 'sqlite'),
;; so older Emacs simply never invokes them — but the byte-compiler
;; on Emacs 28 doesn't know that and emits "function not known"
;; warnings that lint flags as fatal.  These declarations keep the
;; lint clean across all supported versions without changing
;; runtime behaviour.
(declare-function sqlite-open "sqlite" (file &optional readonly))
(declare-function sqlite-close "sqlite" (db))
(declare-function sqlite-select "sqlite" (db query &optional values return-type))

(defcustom tibetan-steinert-db-path
  (let* ((here (or load-file-name buffer-file-name))
         (base (and here (file-name-directory here))))
    (and base (expand-file-name "../data/dictionaries/steinert.db" base)))
  "Path to the Steinert SQLite database.
Nil or a missing file disables Steinert lookup."
  :type '(choice (const :tag "Disabled" nil) file)
  :group 'tibetan)

(defcustom tibetan-steinert-max-hits 25
  "Cap on glossary rows returned by `tibetan-steinert-lookup'.
Keeps the Detailed Dictionary section from exploding on very common words."
  :type 'integer
  :group 'tibetan)

(defconst tibetan-steinert--sanskrit-sources
  '("21-Mahavyutpatti-Skt"
    "22-Yoghacharabhumi-glossary"
    "46-84000Skt"
    "49-LokeshChandraSkt"
    "50-NegiSkt"
    "15-Hopkins-Skt1992"
    "15-Hopkins-Skt2015")
  "Sources whose gloss column holds the Sanskrit equivalent (or contains it
reliably enough to surface as a Sanskrit field).")

;; ---------------------------------------------------------------------------
;; Connection management
;; ---------------------------------------------------------------------------

(defvar tibetan-steinert--db nil
  "Cached open SQLite handle. Opened lazily on first lookup.")

(defvar tibetan-steinert--warned-missing nil)

(defun tibetan-steinert-available-p ()
  "Return non-nil if Steinert lookup is usable in this Emacs session."
  (and (featurep 'sqlite)
       tibetan-steinert-db-path
       (file-readable-p tibetan-steinert-db-path)))

(defun tibetan-steinert--db ()
  "Return the open SQLite handle, opening it on first call.
Returns nil (and warns once) if the DB is unavailable."
  (cond
   ((tibetan-steinert-available-p)
    (unless tibetan-steinert--db
      (setq tibetan-steinert--db (sqlite-open tibetan-steinert-db-path)))
    tibetan-steinert--db)
   (t
    (unless tibetan-steinert--warned-missing
      (setq tibetan-steinert--warned-missing t)
      (message "Steinert dictionary DB not found (%s) — lookup disabled"
               (or tibetan-steinert-db-path "no path")))
    nil)))

;;;###autoload
(defun tibetan-steinert-close ()
  "Close the Steinert DB connection if open (does not delete the file)."
  (interactive)
  (when tibetan-steinert--db
    (ignore-errors (sqlite-close tibetan-steinert--db))
    (setq tibetan-steinert--db nil)))

;; ---------------------------------------------------------------------------
;; Key normalisation
;; ---------------------------------------------------------------------------

(defun tibetan-steinert--to-wylie-key (word)
  "Return the Wylie lookup key for WORD (Tibetan script OR already-Wylie).
Returns nil if conversion isn't possible."
  (when (and word (stringp word) (not (string-empty-p word)))
    (let ((w (string-trim word)))
      (cond
       ;; already wylie-ish (ASCII)
       ((string-match-p "^[a-zA-Z]" w)
        (downcase w))
       ;; Tibetan script -> Wylie
       ((fboundp 'tibetan-to-wylie-fixed)
        (condition-case nil
            (downcase (string-trim (tibetan-to-wylie-fixed w)))
          (error nil)))
       ((fboundp 'tibetan-to-wylie)
        (condition-case nil
            (downcase (string-trim (tibetan-to-wylie w)))
          (error nil)))
       (t nil)))))

;; ---------------------------------------------------------------------------
;; Core lookup
;; ---------------------------------------------------------------------------

(defun tibetan-steinert-lookup (word &optional limit)
  "Look WORD up in the Steinert DB.
Return a list of plists (:source :wylie :gloss :sanskrit), or nil.
LIMIT defaults to `tibetan-steinert-max-hits'."
  (let ((db (tibetan-steinert--db))
        (key (tibetan-steinert--to-wylie-key word)))
    (when (and db key (not (string-empty-p key)))
      (let* ((lim (or limit tibetan-steinert-max-hits))
             (rows (condition-case err
                       (sqlite-select
                        db
                        (concat "SELECT source, wylie, gloss, sanskrit "
                                "FROM entries WHERE wylie_norm = ? "
                                "LIMIT ?")
                        (list key lim))
                     (error
                      (message "Steinert lookup error for %S: %s"
                               word (error-message-string err))
                      nil))))
        (mapcar (lambda (row)
                  (list :source   (nth 0 row)
                        :wylie    (nth 1 row)
                        :gloss    (nth 2 row)
                        :sanskrit (nth 3 row)))
                rows)))))

(defun tibetan-steinert-sanskrit-for (word)
  "Return a combined Sanskrit string for WORD, or nil.
Queries only the Sanskrit-indexed sources for cleanliness."
  (let ((db (tibetan-steinert--db))
        (key (tibetan-steinert--to-wylie-key word)))
    (when (and db key (not (string-empty-p key)))
      (let* ((placeholders
              (mapconcat (lambda (_) "?")
                         tibetan-steinert--sanskrit-sources ","))
             (sql (concat
                   "SELECT source, sanskrit FROM entries "
                   "WHERE wylie_norm = ? AND sanskrit IS NOT NULL "
                   "AND source IN (" placeholders ") "
                   "LIMIT 20"))
             (args (cons key tibetan-steinert--sanskrit-sources))
             (rows (condition-case err
                       (sqlite-select db sql args)
                     (error
                      (message "Steinert Sanskrit lookup error for %S: %s"
                               word (error-message-string err))
                      nil)))
             (seen (make-hash-table :test 'equal))
             (out nil))
        (dolist (row rows)
          (let ((skt (string-trim (or (nth 1 row) ""))))
            (unless (or (string-empty-p skt) (gethash skt seen))
              (puthash skt t seen)
              (push skt out))))
        (when out
          (mapconcat #'identity (nreverse out) "; "))))))

;; ---------------------------------------------------------------------------
;; Convenience formatter (used by Detailed Dictionary renderer)
;; ---------------------------------------------------------------------------

(defun tibetan-steinert-format-matches (word &optional max-rows)
  "Return a human-readable multi-line string of Steinert matches for WORD,
or nil if none. MAX-ROWS caps the displayed rows (default 8)."
  (let* ((hits (tibetan-steinert-lookup word (or max-rows 8))))
    (when hits
      (mapconcat
       (lambda (h)
         (let ((src (plist-get h :source))
               (gl  (plist-get h :gloss)))
           (format "    [%s] %s"
                   (or src "?")
                   (if (and gl (> (length gl) 220))
                       (concat (substring gl 0 217) "...")
                     (or gl "")))))
       hits "\n"))))

;; ---------------------------------------------------------------------------
;; Web URL generation
;; ---------------------------------------------------------------------------

(defun tibetan-steinert-url (wylie-term)
  "Return a Steinert web-dictionary URL for WYLIE-TERM, or nil.
The URL encodes a JSON hash fragment that the single-page app at
`https://dictionary.christian-steinert.de/' routes to a search result.
WYLIE-TERM should be a lowercased Wylie string (e.g. \"mnyam med\").
Strips trailing particles like \\='s, \\='i suffixes for cleaner lookups."
  (when (and wylie-term (stringp wylie-term)
             (not (string-empty-p (string-trim wylie-term))))
    (let* ((term (string-trim (downcase wylie-term)))
           ;; Build the JSON hash the Steinert SPA expects.
           (json-str (format "{\"activeTerm\":\"%s\",\"lang\":\"tib\",\"inputLang\":\"tib\",\"currentListTerm\":\"%s\",\"forceLeftSideVisible\":false,\"offset\":0}"
                             term term))
           (encoded (url-hexify-string json-str)))
      (concat "https://dictionary.christian-steinert.de/#" encoded))))

(defun tibetan-steinert-url-org (wylie-term)
  "Return an org-mode link to the Steinert web dictionary for WYLIE-TERM.
Format: [[url][Steinert]].  Returns nil if WYLIE-TERM is empty."
  (let ((url (tibetan-steinert-url wylie-term)))
    (when url
      (format "[[%s][Steinert]]" url))))

(provide 'tibetan-steinert)
;;; tibetan-steinert.el ends here
