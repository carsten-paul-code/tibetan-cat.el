;;; tibetan-reading-test.el --- Tests for the Reading-view Wylie builder -*- lexical-binding: t -*-

;;; Commentary:
;; R3 (2026-08-12): decorated per-shad-unit Wylie lines, built
;; token-wise (curated-first streams), POS-marked =case= ~converb~
;; !verb! *main-verb* ★curated.  Pure tests: controlled vocab hashes,
;; stubbed verb DB, inert disk loaders.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((base-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "../core" base-dir))
  (add-to-list 'load-path (expand-file-name "../analysis" base-dir)))

(require 'tibetan-vocabulary)
(require 'tibetan-vocabulary-detailed)
(require 'tibetan-wylie)
(require 'tibetan-interlinear)
(require 'tibetan-reading)

(defvar tibetan-comprehensive-vocabulary nil)
(defvar tibetan-rangjung-yeshe-vocabulary nil)
(defvar tibetan-current-resources-vocab nil)
(defvar tibetan-current-custom-vocab nil)

(defmacro tibetan-reading-test--with-env (resources &rest body)
  "Controlled environment: RESOURCES alist into the Resources hash,
all other dictionary sources empty/inert; verb DB stubbed to the
fixture set སྒྲིགས ཡོད བྱུང བཞུགས."
  (declare (indent 1))
  `(let ((tibetan-current-resources-vocab (make-hash-table :test 'equal))
         (tibetan-current-custom-vocab nil)
         (tibetan-comprehensive-vocabulary (make-hash-table :test 'equal))
         (tibetan-rangjung-yeshe-vocabulary nil))
     (dolist (e ,resources)
       (puthash (car e) (cdr e) tibetan-current-resources-vocab))
     (cl-letf (((symbol-function 'tibetan-load-resources-vocab)
                (lambda () nil))
               ((symbol-function 'tibetan-load-custom-vocab)
                (lambda () nil))
               ((symbol-function 'tibetan-rangjung-yeshe-load)
                (lambda () nil))
               ((symbol-function 'tibetan-load-rangjung-yeshe)
                (lambda (&rest _) nil))
               ((symbol-function 'tibetan-steinert-available-p)
                (lambda () nil))
               ((symbol-function 'tibetan-thesaurus-lookup)
                (lambda (_) nil))
               ((symbol-function 'tibetan-verb-lookup)
                (lambda (w)
                  (when (member (string-trim (or w ""))
                                '("སྒྲིགས" "ཡོད" "བྱུང" "བཞུགས"))
                    '((lemma . stub))))))
       ,@body)))

(ert-deftest tibetan-reading-case-converb-verb-decoration ()
  "Case particle after a noun (=la=), converb reading of ནས after a
verb (~nas~), every verb !x!, trailing shad → ` /'."
  (tibetan-reading-test--with-env '()
    (should (equal "lus =la= !sgrigs! ~nas~ !yod! /"
                   (tibetan-reading-decorated-unit-line
                    "ལུས་ལ་སྒྲིགས་ནས་ཡོད།")))))

(ert-deftest tibetan-reading-na-after-noun-is-case ()
  "ན after a NON-verb decorates as case (=na=), and the unit's verbs
still wear !x! when the unit is not the last."
  (tibetan-reading-test--with-env '()
    (should (equal "khyer =na= !bzhugs! /"
                   (tibetan-reading-decorated-unit-line
                    "ཁྱེར་ན་བཞུགས།")))))

(ert-deftest tibetan-reading-main-verb-in-last-unit-only ()
  "The LAST unit's final verb is *x*; earlier units keep !x!."
  (tibetan-reading-test--with-env '()
    (let ((lines (tibetan-reading-decorated-lines
                  '("ཁྱེར་ན་བཞུགས།" "ཆོས་བྱུང།"))))
      (should (equal "khyer =na= !bzhugs! /" (nth 0 lines)))
      (should (equal "chos *byung* /" (nth 1 lines))))))

(ert-deftest tibetan-reading-curated-star-and-mwu ()
  "A curated wordlist MWU groups (W1) and wears ★ after its Wylie."
  (tibetan-reading-test--with-env
      '(("snang ba" . "Erscheinungen // appearances"))
    (should (equal "snang ba★ !byung! /"
                   (tibetan-reading-decorated-unit-line
                    "སྣང་བ་བྱུང།")))))

(ert-deftest tibetan-reading-merged-clitic-decorates-inline ()
  "A merged genitive clitic renders embedded: tri='i='."
  (tibetan-reading-test--with-env '()
    (should (equal "tri='i= chos"
                   (tibetan-reading-decorated-unit-line
                    "ཏྲིའི་ཆོས")))))

(ert-deftest tibetan-reading-ambiguous-r-never-splits ()
  "Bare ར is graphically ambiguous (དེར clitic vs ཁྱེར root-final):
without tag confirmation the builder must never split it — a missed
=r= beats a torn syllable."
  (tibetan-reading-test--with-env '()
    (should (equal "der chos"
                   (tibetan-reading-decorated-unit-line "དེར་ཆོས")))))

(ert-deftest tibetan-reading-line-initial-main-verb-is-org-safe ()
  "A line that BEGINS with the *x* marker must never form an org
headline or list item (the C1 line-leading-star lesson)."
  (tibetan-reading-test--with-env '()
    (let ((line (tibetan-reading-decorated-unit-line "བྱུང།" t)))
      (should (equal "*byung* /" line))
      (should-not (string-match-p "^\\*+ " line)))))

(provide 'tibetan-reading-test)
;;; tibetan-reading-test.el ends here
