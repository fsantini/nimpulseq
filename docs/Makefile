# Minimal makefile for NimPulseq Sphinx documentation.
# Run from the repository root: make -C docs html

SPHINXBUILD  = sphinx-build
SPHINXOPTS   =
SOURCEDIR    = docs
BUILDDIR     = docs/_build
NIM         ?= nim

.PHONY: help api html clean livehtml

help:
	@echo "Available targets (run from repo root):"
	@echo ""
	@echo "  make -C docs api    – generate RST from nim jsondoc (requires Nim)"
	@echo "  make -C docs html   – build HTML with Sphinx (runs api first)"
	@echo "  make -C docs clean  – remove build artefacts"
	@echo ""
	@echo "Override the nim executable:"
	@echo "  make -C docs html NIM=/path/to/nim"

api:
	@echo "==> Generating RST API docs (nim jsondoc)..."
	NIM=$(NIM) python $(SOURCEDIR)/generate_rst.py

html: api
	@echo "==> Building HTML with Sphinx..."
	$(SPHINXBUILD) -M html $(SOURCEDIR) $(BUILDDIR) $(SPHINXOPTS)
	@echo ""
	@echo "HTML output: $(BUILDDIR)/html/index.html"

livehtml: api
	sphinx-autobuild $(SOURCEDIR) $(BUILDDIR)/html $(SPHINXOPTS)

clean:
	rm -rf $(BUILDDIR) $(SOURCEDIR)/_nim_json $(SOURCEDIR)/api
	@echo "Cleaned build artefacts."
