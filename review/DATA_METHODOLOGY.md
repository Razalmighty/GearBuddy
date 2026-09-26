# Data methodology

GearBuddy separates runtime facts from unreviewed evidence. JSON files under
`data/` are the source of truth; generated Lua snapshots are committed and
checked for drift.

## Runtime eligibility

- Automatic equipment selection accepts only `Verified` catalog rows.
- Missing values remain unknown; they are never converted to zero.
- Hidden and conditional effects are separate, source-linked records.
- Action routing accepts only reviewed, verified action rows.
- Numeric action formulas are report-only unless a later reviewed runtime
  explicitly enables them. Alpha.8 enables none.

## Quarantine and promotion

Bulk client exports, external implementation values, community research, and
other comparison material enter candidate registries first. Candidate rows do
not generate runtime Lua and cannot alter optimization. Promotion is a manual,
field-by-field decision requiring Horizon-specific corroboration, provenance,
and validation.

The current candidate registries preserve seven gear evidence sets, thirteen
BLU action evidence sets, and three global mechanics claims. These counts are
research coverage, not verified HorizonXI facts.

Contributor credit uses approved public labels only. Private contact details,
Discord identifiers, and message archives are not stored in the repository.

See [Data policy](../docs/DATA_POLICY.md),
[Evidence ledger](../docs/EVIDENCE_LEDGER.md), and
[Contributing](../CONTRIBUTING.md) for schemas and correction requirements.
