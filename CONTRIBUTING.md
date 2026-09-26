# Contributing

The approval alpha accepts focused bug reports and reproducible data corrections.
Do not submit unverified stat magnitudes as zero or as inferred facts.

A gear-data change should include:

1. The Horizon item ID and exact item name.
2. The visible stat or hidden-effect field being changed.
3. A Horizon-first source URL or reproducible in-game evidence.
4. Whether the value is verified, partial, disputed, or text-only.
5. A regenerated data snapshot and passing validation tests.

An action-metadata change should include the Horizon action ID, exact name, legal
job and learned level, category/context, hit-count and WSC facts, a source ID,
verification date, confidence level, and `Verified` status. Add it to
`data/actions_source.json`; never hand-edit `data/actions.lua`.

An action-mechanics change belongs in `data/mechanics_source.json`, not the
routing registry. Landing, potency, duration, and utility must remain separate.
Qualitative evidence cannot contain a coefficient, multiplier, weight, or
formula. Unknown outcomes must have no asserted drivers. Include every source ID
needed to support the relationship and regenerate `data/mechanics.lua`.

Unverified community research belongs in the candidate evidence registries,
never directly in runtime data. Give each submission a unique evidence ID,
source chain, contributor chain, confidence level, review date, and scope note.
Conflicting claims are both retained until field-level review resolves them.
Individual public credit is opt-in; do not add private Discord identifiers,
message archives, or contact information to the repository.

Runtime changes must preserve the read-only guarantee until the project owner and
HorizonXI reviewers explicitly approve an equipment-execution phase.

Before opening a pull request, run the generated-data check, repository
validator, Python unit suite, and Lua smoke test listed in `README.md`. Runtime
reports should include `/gb selftest verbose` and `/gb report`; do not attach a
raw inventory dump.
