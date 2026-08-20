# Third-party software

This runtime redistributes pinned third-party software. Exact versions, source URLs and SHA-256 values are recorded in `manifest/versions.env` and `manifest/sources.tsv`.

Key components and upstream licenses include:

- PostgreSQL 17.10 — PostgreSQL License.
- pgTAP 1.3.3 — PostgreSQL-style license; upstream source is identified by its pinned source hash.
- plpgsql_check 2.8.11 — permissive BSD/MIT-style license from upstream; the compiled payload is reproducible from the pinned source/toolchain described by the builder repository.
- ShellCheck 0.11.0 — GPL-3.0-only. The binary is distributed unmodified; its exact pinned corresponding source archive and GPL license are included under `licenses/`.
- Miller 6.20.2 — upstream open-source license; see the upstream release/source identified in the source manifest.
- postgres 3.4.7 npm package — Unlicense.
- `@postgres-language-server/wasm` 0.25.7 — MIT.
- fast-check 4.9.0 — MIT.
- pure-rand 8.4.2 — MIT.

Other bundled tools retain the license terms documented by their upstream projects. This file is a distribution notice, not a substitute for those license texts.
