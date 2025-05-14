project = "Blog"
language = "en"
author = "Jakub Pieńkowski"
master_doc = "index"
source_suffix = ".rst"
exclude_patterns = ["docs", "venv", "jakski_github_io.egg-info", "README.md"]
today_fmt = "%Y-%m-%d"
extensions = [
    "sphinx.ext.graphviz",
    "sphinx.ext.todo",
    "sphinxcontrib.plantuml",
    "myst_parser",
]
source_suffix = {
    ".rst": "restructuredtext",
    ".txt": "markdown",
    ".md": "markdown",
}
html_title = "OK, noted"
html_theme = "classic"
todo_include_todos = True
latex_domain_indices = False
latex_elements = {
    "extraclassoptions": "openany,oneside",
}
