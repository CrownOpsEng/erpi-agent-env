# J2911 reference review and Magnet design response

## Useful J2911 mechanisms retained

- Bundled CPython base runtime rather than assuming the host Python is sufficient.
- A Python launcher that discovers its current location and repairs `pyvenv.cfg` after relocation.
- Native tools exposed beside the Python environment rather than pretending every useful command is a Python package.
- Static checksum manifest with relocation-mutated metadata excluded.
- A deterministic environment-check command.

## J2911 weaknesses deliberately corrected

- The uploaded J2911 archive contains an old absolute build path in `bin/opc`; therefore successful `python` execution alone is not sufficient proof of portability.
- J2911's environment definition is not reconstructable from its repository because `.venv` is ignored and there is no committed lock describing that local environment. This builder emits exact environment metadata, a hashed Python lock, a wheelhouse, source URLs/checksums and a complete immutable checksum manifest.
- J2911 relies on several host document-rendering tools. Magnet does not currently need that document-production surface, so it is not copied into this bundle.
- Python alone does not solve Magnet's execution mismatch: the Magnet repository requires Node major 24. Node 24 is therefore a first-class bundled runtime.

## Explicit non-goals

- Cross-OS portability. Linux/macOS/Windows require separate payloads.
- Cross-architecture portability. This payload is Linux x86-64.
- Replacing Magnet repository tooling or policy.
- Bundling credentials.
- Pretending Docker is portable as a client-only binary when no daemon/socket exists.
- Using direct `psql`/Supabase shortcuts around repository safety targets.
