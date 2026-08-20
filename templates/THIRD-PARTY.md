# Third-party software

This runtime redistributes pinned third-party software. Exact versions, source URLs and SHA-256 values are recorded in `manifest/versions.env` and the machine-readable `manifest/sources.tsv`.

Direct third-party license and attribution texts for the redistributed command/database/capsule components are included under `licenses/third-party/`. ShellCheck 0.11.0 is GPL-3.0-only; its GPL license and exact pinned corresponding source archive are additionally included under `licenses/shellcheck/` and `licenses/source/`. The bundled Node and CPython distributions retain their upstream license files in their own runtime trees, and installed Python packages retain their package-provided license metadata.

The prebuilt PostgreSQL server payload also carries shared libraries from its upstream portable distribution (including OpenSSL 1.1.1, ICU 60.2, libxml2, libxslt, liblzma, zlib, and OSSP uuid). The direct-license bundle below is not a legal-compliance conclusion for those nested libraries. Stable publication is blocked until their exact notices are retained and reviewed, or the server payload is replaced by a qualified source-built distribution whose license surface is controlled by this repository.

The direct inventory includes:

- uv 0.12.5 — MIT OR Apache-2.0.
- GitHub CLI 2.97.0 — MIT.
- jq 1.8.2 — MIT plus the third-party notices reproduced in upstream `COPYING`.
- yq 4.53.3 — MIT.
- ripgrep 15.2.0 — MIT OR Unlicense.
- actionlint 1.7.12 — MIT.
- gitleaks 8.30.1 — MIT.
- ShellCheck 0.11.0 — GPL-3.0-only, with corresponding source supplied.
- Miller 6.20.2 — BSD-style license.
- PostgreSQL 17.10 — PostgreSQL License.
- pgTAP 1.3.3 — PostgreSQL-style license.
- plpgsql_check 2.8.11 — MIT-style license.
- postgres 3.4.7 npm package — Unlicense.
- `@postgres-language-server/wasm` 0.25.7 — MIT.
- fast-check 4.9.0 — MIT.
- pure-rand 8.4.2 — MIT.

This file is an inventory and routing notice. The reproduced license/attribution texts remain authoritative for their respective components.
