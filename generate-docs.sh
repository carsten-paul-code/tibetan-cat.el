#!/bin/bash
# Generate living documentation from BDD specs (fast mode - skip glossary loading)

cd "$(dirname "$0")"

emacs --batch \
  -L . -L core -L analysis -L persist -L config -L spec -L spec/suites \
  --eval "(setq tibetan-cat-data-dir \"$(pwd)\")" \
  --eval "(require 'tibetan-bdd)" \
  --eval "(require 'verb-detection-spec)" \
  --eval "(require 'particle-analysis-spec)" \
  --eval "(require 'segment-analysis-spec)" \
  --eval "(require 'cat-translation-spec)" \
  --eval "(require 'compound-analysis-spec)" \
  -l spec/generate-docs.el \
  -f tibetan-bdd-generate-docs 2>&1

echo ""
echo "Documentation generated: FEATURES.md"
