;;; tibetan-steinert-test.el --- Tests for tibetan-steinert.el -*- lexical-binding: t -*-

;;; Commentary:
;; Integration tests for the Steinert SQLite dictionary layer.
;; Skipped gracefully when the DB has not been built (CI without data).

;;; Code:

(require 'ert)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir)))

(require 'tibetan-wylie)
(require 'tibetan-steinert nil t)

(defun tibetan-steinert-test--ready-p ()
  "Skip marker: t when DB is present and module loaded."
  (and (featurep 'tibetan-steinert)
       (fboundp 'tibetan-steinert-available-p)
       (tibetan-steinert-available-p)))

;; ============================================================================
;; Basic lookup — Tibetan and Wylie keys both work
;; ============================================================================

(ert-deftest tibetan-steinert-wylie-key-sangs-rgyas ()
  "A Wylie key returns multiple entries across sources."
  (skip-unless (tibetan-steinert-test--ready-p))
  (let ((hits (tibetan-steinert-lookup "sangs rgyas" 20)))
    (should hits)
    (should (> (length hits) 3))
    ;; At least one row should come from Mahavyutpatti (Sanskrit-indexed).
    (should (cl-some (lambda (h)
                       (equal (plist-get h :source) "21-Mahavyutpatti-Skt"))
                     hits))))

(ert-deftest tibetan-steinert-tibetan-key-sangs-rgyas ()
  "A Tibetan-script key returns the same sort of entries."
  (skip-unless (tibetan-steinert-test--ready-p))
  (let ((hits (tibetan-steinert-lookup "སངས་རྒྱས" 20)))
    (should hits)
    (should (cl-some (lambda (h)
                       (let ((gl (plist-get h :gloss)))
                         (and gl (string-match-p "buddha" gl))))
                     hits))))

;; ============================================================================
;; Sanskrit surfacing — the main point of the integration
;; ============================================================================

(ert-deftest tibetan-steinert-sanskrit-for-sangs-rgyas ()
  "sangs rgyas → buddha (or buddhaḥ) must appear in the combined Sanskrit."
  (skip-unless (tibetan-steinert-test--ready-p))
  (let ((skt (tibetan-steinert-sanskrit-for "sangs rgyas")))
    (should skt)
    (should (string-match-p "buddha" skt))))

(ert-deftest tibetan-steinert-sanskrit-for-bodhisattva ()
  "byang chub sems dpa' → bodhisattva."
  (skip-unless (tibetan-steinert-test--ready-p))
  (let ((skt (tibetan-steinert-sanskrit-for "byang chub sems dpa'")))
    (should skt)
    (should (string-match-p "bodhisattva" skt))))

(ert-deftest tibetan-steinert-sanskrit-for-bltams ()
  "Milarepa seg-007 biographical verb: bltams → niṣkramaṇa."
  (skip-unless (tibetan-steinert-test--ready-p))
  (let ((skt (tibetan-steinert-sanskrit-for "bltams")))
    (should skt)
    (should (string-match-p "niṣkramaṇa\\|niSkramaNa" skt))))

(ert-deftest tibetan-steinert-sanskrit-for-absent-returns-nil ()
  "Nonsense key returns nil, not an error or an empty string."
  (skip-unless (tibetan-steinert-test--ready-p))
  (should (null (tibetan-steinert-sanskrit-for "xxxzzznoway"))))

;; ============================================================================
;; Limit honoured — max-hits defends against runaway rows
;; ============================================================================

(ert-deftest tibetan-steinert-honours-limit ()
  "The explicit limit caps returned rows."
  (skip-unless (tibetan-steinert-test--ready-p))
  (let ((hits (tibetan-steinert-lookup "sangs rgyas" 3)))
    (should (<= (length hits) 3))))

;; ============================================================================
;; Integration with vocabulary-detailed — :sanskrit should surface
;; ============================================================================

(ert-deftest tibetan-steinert-enriches-vocab-lookup ()
  "Detailed lookup for sangs rgyas should carry :sanskrit after Steinert
enrichment (even if the primary gloss source had no Sanskrit field)."
  (skip-unless (tibetan-steinert-test--ready-p))
  (skip-unless (fboundp 'tibetan-vocab-lookup-detailed))
  (require 'tibetan-vocabulary-detailed)
  ;; Clear cache so previous test runs don't hide regressions.
  (when (fboundp 'tibetan-vocab-clear-cache)
    (tibetan-vocab-clear-cache))
  (let ((entry (tibetan-vocab-lookup-detailed "སངས་རྒྱས")))
    (should entry)
    (let ((skt (plist-get entry :sanskrit)))
      (should skt)
      (should (string-match-p "buddha" skt)))))

(provide 'tibetan-steinert-test)
;;; tibetan-steinert-test.el ends here
