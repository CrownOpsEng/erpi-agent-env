# Third-party components

The Magnet Agent Environment redistributes or downloads the following upstream components. Exact versions, artifact URLs and SHA-256 values used for the build are recorded in `manifest/sources.tsv` and `manifest/versions.env`.

- uv — https://github.com/astral-sh/uv
- CPython distribution managed by uv — https://github.com/astral-sh/python-build-standalone and https://www.python.org/
- Node.js — https://nodejs.org/
- GitHub CLI — https://github.com/cli/cli
- jq — https://github.com/jqlang/jq
- yq — https://github.com/mikefarah/yq
- ripgrep — https://github.com/BurntSushi/ripgrep
- actionlint — https://github.com/rhysd/actionlint
- gitleaks — https://github.com/gitleaks/gitleaks

The Python analysis layer is installed from the source-frozen exact hash-locked `manifest/requirements.lock`; installed package metadata and bundled wheel metadata carry package-specific licensing information.

This notice is informational and does not replace the license files or terms supplied by each upstream project.
