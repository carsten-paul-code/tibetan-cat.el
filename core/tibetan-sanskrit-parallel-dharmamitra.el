;;; tibetan-sanskrit-parallel-dharmamitra.el --- DharmaMitra realign orchestrator -*- lexical-binding: t -*-

;; Copyright (C) 2026
;; Author: Carsten Paul

;;; Commentary:
;;
;; Phase 2 of the dharmamitra-realign workflow (2026-04-27).
;;
;; Drives the per-segment Sanskrit alignment lookup: given a Tibetan
;; segment text and the parent source file, returns a ranked list of
;; candidate Sanskrit parallels from DharmaMitra's corpus.  The
;; downstream realign command (Phase 4) takes this list, asks Claude
;; to disambiguate (Phase 3), and writes the chosen Sanskrit into
;; the segment's `**** Sanskrit' sibling on `C-u' apply.
;;
;; The orchestration is two API calls:
;;   1. chat-translate Tibetan → English (DM autodetects encoding).
;;   2. semantic search the DM corpus with the English translation,
;;      filtered to `#+DM_SANSKRIT_SOURCE:' from the source-file
;;      headers, with `filter_source_language: sa' so we only get
;;      Sanskrit hits.
;;
;; Both API calls are cached by `tibetan-dharmamitra-api', so re-
;; running the same query is free after the first round.
;;
;; This module returns nil for every failure mode (missing header,
;; empty Tibetan, translate failure, search failure) — callers do
;; not need to distinguish between them.  The realign command can
;; report aggregate counts (`X of N segments failed') without
;; needing per-failure breakdown.

;;; Code:

(require 'cl-lib)
(require 'tibetan-dharmamitra-api)

;; The metadata reader lives in `persist/'; soft-required so this
;; module can stand alone for unit testing if needed.  Falls back
;; to nil-everywhere when the persist module isn't loaded.
(declare-function tibetan-analysis--read-source-metadata
                  "tibetan-analysis-claude" (source-file))

(defun tibetan-sanskrit-parallel-dm--shape-result (alist rank)
  "Convert a DharmaMitra search-result ALIST to a candidate plist.
RANK is the 1-based position in the search response.

Pure function — no I/O.  Robust to missing alist keys: each
slot defaults to nil / empty string so downstream callers always
receive a fully-populated plist."
  (list :id        (alist-get 'id alist)
        :text      (or (alist-get 'text alist) "")
        :segmentnr (alist-get 'segmentnr alist)
        :title     (alist-get 'title alist)
        :rank      rank))

;;;###autoload
(cl-defun tibetan-sanskrit-parallel-dm-candidates-for-tibetan
    (tibetan-text source-file &key (max-candidates 5))
  "Find Sanskrit alignment candidates for TIBETAN-TEXT in DM corpus.

Workflow:
  1. Read `#+DM_SANSKRIT_SOURCE:' from SOURCE-FILE.  Returns nil
     when missing — without a target work, searching the whole
     DM corpus would surface unrelated hits (e.g. high-rank
     prajñāpāramitā passages instead of Bodhisattvabhūmi).
  2. Translate TIBETAN-TEXT → English via
     `tibetan-dharmamitra-api-chat-translate'.  Returns nil if
     translation fails (HTTP error / empty response).
  3. Search the DM primary corpus with the English translation,
     filtered to the configured Sanskrit work, with
     `:source-lang sa' so only Sanskrit hits are returned.  Returns
     nil if search fails or yields no hits.
  4. Take the top MAX-CANDIDATES (default 5) hits, shape each as a
     plist `(:id ID :text STR :segmentnr STR :title STR :rank N)'.

Returns the candidate list, or nil for any failure mode (missing
header, empty Tibetan input, translate failure, search failure,
zero hits, missing/unreadable SOURCE-FILE).

Both underlying API calls are cached by request body hash, so
repeated invocations with the same inputs cost nothing after the
first."
  (when (and (stringp tibetan-text)
             (not (string-empty-p (string-trim tibetan-text)))
             source-file
             (stringp source-file)
             (file-exists-p source-file)
             (fboundp 'tibetan-analysis--read-source-metadata))
    (let* ((meta (tibetan-analysis--read-source-metadata source-file))
           (sa-source (plist-get meta :dm-sanskrit-source)))
      (when (and sa-source (stringp sa-source)
                 (not (string-empty-p sa-source)))
        (let ((english (tibetan-dharmamitra-api-chat-translate
                        tibetan-text)))
          (when (and english (not (string-empty-p english)))
            (let ((hits (tibetan-dharmamitra-api-search
                         english
                         :source-lang "sa"
                         :include-files (list sa-source)
                         :max-depth (max max-candidates 10))))
              (when hits
                (let ((out '()))
                  (cl-loop for hit in hits
                           for i from 1 to max-candidates
                           do (push (tibetan-sanskrit-parallel-dm--shape-result
                                     hit i)
                                    out))
                  (nreverse out))))))))))

(provide 'tibetan-sanskrit-parallel-dharmamitra)
;;; tibetan-sanskrit-parallel-dharmamitra.el ends here
