# Evidence ledger and contributor credit

GearBuddy separates **evidence collection** from **runtime truth**. The evidence
ledger can grow quickly from Lua files, testing notes, authorized community
exports, wikis, and comparison servers without making an unreviewed value affect
gear scoring.

## Registries

- `data/equipment_candidates_source.json` stores source-specific equipment
  assertions. Item IDs may remain unknown until the client-resource export
  resolves them.
- `data/mechanics_candidates_source.json` stores source-specific action values
  and global formula claims. A matched action ID does not make its candidate
  values verified.
- `data/contributors_source.json` records approved public credit labels and
  project roles. It deliberately omits private contact information.
- `data/catalog_source.json` and `data/mechanics_source.json` remain the reviewed
  runtime boundaries.

Every evidence set has its own ID, source chain, contributor chain, review date,
confidence, status, and scope note. Multiple evidence sets may describe the same
item or action. The coverage audit compares their fields and reports conflicting
values instead of silently choosing one.

## Promotion rule

Candidate data is always inert. Promotion requires a field-by-field review:

1. Resolve the canonical item or action identity.
2. Compare all assertions for the field.
3. Record the strongest Horizon-specific evidence and any disagreement.
4. Promote only the supported fields into the reviewed catalog or mechanics
   registry.
5. Regenerate Lua data and pass the complete validation suite.

A record can therefore have a verified hit count while its WSC percentage, fTP,
cap, landing model, or duration remains disputed.

## Community and Discord evidence

Only administrator-approved exports, public posts, or user-supplied excerpts may
be ingested. Raw archives, private conversations, account identifiers, and
personal contact details do not belong in the repository. Individual credit is
opt-in; otherwise use an approved collective label or an anonymous evidence
reference. A contributor submits evidence, not a guarantee that every value is
correct.

## Current seed

The first candidate batch preserves the recovered Chat 1 BLU matrix: thirteen
spell records, three global formula claims, and seven equipment evidence sets.
All remain report-only pending Horizon-specific corroboration.
