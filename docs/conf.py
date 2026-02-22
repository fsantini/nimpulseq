project = "NimPulseq"
copyright = "2026, NimPulseq Contributors"
author = "NimPulseq Contributors"
release = "0.1.0"

extensions = [
    "sphinx.ext.viewcode",
    "sphinx.ext.intersphinx",
]

templates_path = ["_templates"]
exclude_patterns = [
    "_build",
    ".venv",
    "Thumbs.db",
    ".DS_Store",
    "_nim_json",
    "requirements.txt",
    "generate_rst.py",
    "Makefile",
]

html_theme = "sphinx_rtd_theme"
html_static_path = []  # created on demand; avoids warning when absent
html_theme_options = {
    "navigation_depth": 4,
    "collapse_navigation": False,
    "titles_only": False,
    "logo_only": False,
}

master_doc = "index"
