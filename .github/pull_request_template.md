## Change

Describe the behavior, data, or documentation change and its approval impact.

## Evidence

- [ ] `python tools/generate_data.py --check`
- [ ] `python tools/validate_repo.py`
- [ ] `python -m unittest discover -s tests`
- [ ] `lua5.1 tests/runtime_smoke.lua` (or `texlua` locally)
- [ ] A deterministic release ZIP builds and verifies

## Read-only boundary

- [ ] No equipment command, outgoing packet hook, packet injection, or action interception was added.
- [ ] Inventory scans remain scheduled and debounced; UI controls consume the cache.
- [ ] Unknown or unverified facts remain visible and inert.
- [ ] Data changes include provenance and regenerated Lua outputs.

## Reviewer notes

Record any in-game test requirements, expected self-test warnings, migrations, or unresolved evidence.
