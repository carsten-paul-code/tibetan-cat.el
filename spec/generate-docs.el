;;; generate-docs.el --- Generate living documentation from BDD specs -*- lexical-binding: t -*-

;;; Commentary:
;; Generates markdown documentation from spec suites.
;; Run with: emacs --batch -l spec/run-specs.el -l spec/generate-docs.el -f tibetan-bdd-generate-docs

;;; Code:

(require 'tibetan-bdd)

(defun tibetan-bdd-generate-docs ()
  "Generate markdown documentation from all spec suites."
  (let ((output-file (expand-file-name "FEATURES.md"
                       (file-name-directory (or load-file-name buffer-file-name "..")))))
    (with-temp-file output-file
      (insert "# Tibetan CAT - Feature Documentation\n\n")
      (insert "*This documentation is auto-generated from executable specifications.*\n")
      (insert "*Last updated: " (format-time-string "%Y-%m-%d %H:%M") "*\n\n")
      (insert "---\n\n")

      ;; Generate docs for each suite
      (maphash
       (lambda (name suite)
         (insert (format "## %s\n\n" (tibetan-bdd-suite-description suite)))
         (insert (format "*Suite: `%s`*\n\n" name))

         ;; Group specs by tags if available
         (let ((specs (reverse (tibetan-bdd-suite-specs suite))))
           (dolist (spec specs)
             (let ((spec-name (tibetan-bdd-spec-name spec))
                   (example (tibetan-bdd-spec-example-source spec))
                   (given (tibetan-bdd-spec-given spec))
                   (when-form (tibetan-bdd-spec-when spec))
                   (tags (tibetan-bdd-spec-tags spec)))

               (insert (format "### %s\n\n" spec-name))

               (when example
                 (insert (format "**Example:** %s\n\n" example)))

               (when tags
                 (insert (format "**Tags:** %s\n\n"
                                (mapconcat (lambda (t) (format "`%s`" t)) tags " "))))

               ;; Show the specification structure
               (insert "```\n")
               (when given
                 (insert (format "GIVEN: %S\n" given)))
               (insert (format "WHEN:  %S\n" when-form))
               (insert "```\n\n"))))

         (insert "---\n\n"))
       tibetan-bdd-suites))

    (message "Generated documentation: %s" output-file)))

(provide 'generate-docs)
;;; generate-docs.el ends here
