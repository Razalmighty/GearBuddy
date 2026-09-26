# Data and hidden-effect policy

The source of truth is the normalized JSON under `data/`. Generated Lua snapshots
are committed so the addon requires no JSON parser at runtime.

Bulk Ashita `IItem` exports are evidence inputs, not source-of-truth runtime
rows. Their slot and job masks, level, damage, and delay are normalized offline;
their description text is retained for review but never parsed into trusted
stats. Every untouched bulk row remains `ID Verified` until an explicit Horizon
decision promotes, partially records, or excludes it.

## Verification states

| State | Default optimizer behavior |
| --- | --- |
| `Verified` | May participate and contribute numeric stats |
| `Partial` | Visible to reviewers; cannot win |
| `ID Verified` | Identity only; cannot win |
| `Pending` | Cannot win |

Blank means unknown. It never means zero.

Automatic optimization remains `Verified`-only. An explicit player pin is a
preference exception, not a data promotion: an owned item with `Partial`,
`ID Verified`, `Pending`, or absent catalog data may be pinned only when Ashita's
resource metadata proves job, effective-level, equippable, and physical-slot
legality. Its catalog stats and effects remain empty in scoring and the preview
labels them unverified.

## Hidden and conditional effects

Each effect is a separate record with item ID, applicability, condition, value,
unit, Horizon-specific flag, verification state, source, and notes. A verified
text effect with unknown magnitude may satisfy a categorical requirement, such as
Magus Bazubands in a Learn set, but contributes no invented numeric score.

Numeric conditional effects contribute only when the effect's verification is
exactly `Verified` and its condition is active for the selected context.

## Provenance

Every fully verified item and effect points to a source ID. `tools/validate_repo.py`
rejects duplicate item IDs, orphan effects, missing sources, missing confidence or
verification fields, numeric zero used in place of an explicitly unknown effect
value, and stale generated Lua snapshots.

## Action metadata

Action metadata follows the same rule. Rows are keyed by a verified action ID
and retain a readable name, legal job/level, category, context, skill, element,
hit count, WSC coefficients, qualitative stat focus, confidence, provenance,
and any TP/Chain Affinity/Burst Affinity behavior. The source is
`data/actions_source.json` and
`tools/generate_data.py` produces the runtime snapshot. The validator rejects
duplicate IDs/names, missing provenance, incomplete legality, unsupported
categories, missing policy contexts, malformed aliases, missing Horizon
evidence pages, inconsistent Horizon overrides, and any action row that is not
`Verified`. The reviewed source contains all 113 candidate BLU spells through
level 75 from the Horizon tracker. Client identity/timing metadata is
cross-checked against Windower Resources and routing against the current BLU
profile. The six spells whose Horizon levels differ from the client resource
retain both values in an explicit override record. Seven WotG-era candidates
omitted from Horizon's current canonical level-51–75 list remain `Pending` with
an explicit `Era excluded` state and are rejected by the verified-only runtime
gate. Plasma Charge is verified from the canonical list; its 5-point set cost
and 60-second Horizon duration resolve the legacy/client conflicts explicitly.
Known source disagreements are stored as structured conflicts. Unknown WSC coefficients
remain empty and contribute nothing rather than being inferred; qualitative stat
focus is stored separately and never presented as a numeric coefficient.

## Action mechanics

`data/mechanics_source.json` is intentionally separate from routing metadata.
Each registered action contains explicit landing, potency, duration, and utility
outcomes with independent status, drivers, notes, confidence, and provenance.
An outcome may be:

| Status | Runtime meaning |
| --- | --- |
| `verified_numeric` | A reviewed formula may be represented; none are active yet |
| `qualitative` | Directional evidence may be shown but cannot become a number |
| `unknown` | No driver or formula may be asserted |
| `not_applicable` | The action has no such outcome; no driver or formula may be asserted |

Numeric formulas use a bounded typed expression tree with explicit inputs,
constants, operators, units, output, rounding, and optional caps. Free-form Lua,
text expressions, and unknown operators are rejected. Formula records remain
report-only until a later reviewed runtime explicitly enables them; their
presence cannot silently alter optimizer scores.

The validator rejects unknown outcomes with drivers, qualitative drivers hiding
numeric weights, incomplete outcome sets, duplicate action rows, missing source
chains, and formulas on nonnumeric evidence. The four representative BLU rows
establish this contract but do not affect optimizer scores.

Upgrade candidates use the same confidence rule. Only `Verified` catalog rows
with legal job, effective-level, compatible slot array, and weapon-policy state
can appear in the
recommendation list. Items already present in the ownership index are excluded;
unknown or partial rows remain visible to reviewers but cannot win. Active
manual pins are fixed and cannot appear as proposed replacement slots.

## Coverage audit

`tools/audit_data_coverage.py` produces a deterministic snapshot of catalog,
effect, action, and per-outcome mechanics coverage. Its review queues identify
unverified items and verified actions that still lack mechanics records. The
report is descriptive only: running it never promotes a row or changes runtime
eligibility.

`tools/extract_lsb_blue_candidates.py` may extract static BLU parameters from a
local LandSandBoat checkout into a separate comparison file. The output is
explicitly scoped as non-Horizon evidence and is deliberately incompatible with
the runtime registry. Every value requires manual, per-outcome Horizon review;
dynamic expressions are listed as ignored rather than evaluated.

## Candidate evidence and contributors

Unreviewed gear stats and formula candidates live in separate quarantined
registries. They never generate runtime Lua and never enter the resolver.
`data/equipment_candidates_source.json` and
`data/mechanics_candidates_source.json` retain source-specific values so later
Horizon documentation, controlled testing, or authorized community exports can
corroborate or conflict with individual fields. `data/contributors_source.json`
tracks approved credit labels without storing private contact information.

The coverage audit reports candidate counts, unresolved action identities, and
field conflicts. See [Evidence ledger and contributor credit](EVIDENCE_LEDGER.md).
