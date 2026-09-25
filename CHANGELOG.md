# Changelog

## Unreleased

- Added a deterministic catalog/action-mechanics coverage audit with explicit
  review queues; reporting never promotes data or changes runtime eligibility.
- Upgraded the action-mechanics boundary to a typed, non-executable formula
  contract with explicit units, output, rounding, caps, bounded operators, and
  report-only execution policy.
- Added a LandSandBoat BLU comparison extractor that fingerprints source files,
  captures only static parameters, rejects dynamic expressions, and marks all
  output as non-Horizon candidate evidence requiring per-outcome review.

## 0.1.0-alpha.8

- Added an in-game, read-only compatibility self-test for the required Ashita
  managers, event surface, settings backend, cached item/resource shape, player
  context, verified registries, and non-executable equipment-plan contract.
- Added `/gb selftest [verbose]`, `/gb report`, and matching console controls so
  reviewers can capture an actionable compatibility result without triggering
  an inventory scan.
- Added bounded inventory-refresh history with generation, reason, and monotonic
  timestamp metadata, plus scan counts in status, UI, and approval output.
- Proved in the Lua harness that self-test manager probes do not enumerate bags,
  unsafe plan flags fail the test, and refresh history remains bounded.
- Hardened GitHub validation with least-privilege permissions, concurrency,
  Lua 5.1 syntax/runtime checks, deterministic release verification, and a
  short-lived review artifact.
- Added pull-request and issue guidance for compatibility, Force Swap,
  mechanics, persistence, performance, and read-only safety findings.

## 0.1.0-alpha.7

- Added persisted, stable-item-ID Force Swap pins scoped by job, context, and
  first-ranked priority profile, including an owned-gear dropdown for every
  physical equipment slot.
- Made manual preference precedence explicit: legality and weapon locks remain
  authoritative, pins constrain the shared optimizer, required effects and
  formula objectives optimize the remaining slots, and invalid pins visibly
  fall back to automatic selection.
- Preserved physical-instance uniqueness across paired slots and excluded active
  pinned slots from upgrade replacement recommendations.
- Allowed explicit manual selection of owned legal gear with unverified catalog
  stats while keeping those stats unknown and inert; automatic selection remains
  verified-only.
- Added Manual-versus-Formula attribution, pin warnings, and trust metadata to
  previews and the non-executable equipment-plan contract.
- Migrated settings to schema v2 with safe schema-v1 loading and validated pin
  persistence; bag/index locations and inventory snapshots remain unsaved.
- Added a versioned, fail-closed action-mechanics registry that separates
  landing, potency, duration, and utility evidence without inventing numeric
  coefficients. Four representative BLU rows establish the boundary.
- Expanded host and Lua regression coverage for pin precedence, missing and
  over-level fallback, duplicate instances, weapon locks, unverified stats,
  protected upgrades, profile identity, persistence migration, and mechanics
  validation.

## 0.1.0-alpha.6

- Added a deterministic offline adapter for English Ashita v4 `IItem` exports,
  including strict field validation, job/slot-mask decoding, input SHA-256
  provenance, evidence retention, and an audit report.
- Kept bulk client rows fail-closed: description text is never promoted into
  trusted stats, and untouched normalized rows remain `ID Verified` after merge.
- Migrated the runtime equipment catalog to schema-v2 slot arrays so Main/Sub
  compatibility is modeled without duplicating catalog rows.
- Updated the resolver and upgrade planner to use actual compatible slots while
  preserving physical-instance uniqueness and weapon-lock behavior.
- Added adapter, migration, conflict, multi-slot resolver, and partial-lock
  upgrade coverage.

## 0.1.0-alpha.5

- Reconciled the eight quarantined BLU candidates against Horizon's current
  canonical Blue Magic list and the deletion-marked legacy duplicate list.
- Promoted Plasma Charge with the Horizon-confirmed lightning element,
  five-point set cost, and 60-second duration; retained both resolved source
  conflicts for reviewer audit.
- Reclassified the seven WotG-era candidates omitted from Horizon's current
  level-51–75 list as explicit era exclusions instead of unresolved rows.
- Expanded the verified runtime registry to 106 actions while preserving the
  fail-closed boundary for all seven exclusions.
- Added a deterministic bulk-catalog merge tool and review contract: raw client
  rows remain identity-only, Horizon overrides require explicit decisions, and
  verified differences require written conflict resolutions.

## 0.1.0-alpha.4

- Reissued the level-75 registry package without the one-time data-conversion
  helper used during development.

## 0.1.0-alpha.3

- Completed the Horizon BLU source registry through level 75: 113 tracker rows,
  105 verified runtime actions, and eight unresolved rows quarantined by the
  verified-only gate.
- Preserved tracker priority, best use, era notes, and granted job trait for
  every spell.
- Added explicit source-conflict records for Triumphant Roar MP and Plasma
  Charge set points instead of selecting an unsupported value silently.
- Added action-focused policy ordering so qualitative stat focus participates in
  read-only optimization; Cannonball now includes Defense in its focused order.
- Corrected 1000 Needles to tracker-authoritative magical routing and recorded
  the old profile-fallback discrepancy.

## 0.1.0-alpha.2

- Expanded the verified Horizon BLU registry from seven actions to all 63 spells
  through level 56.
- Recorded six Horizon level changes as explicit retail-to-Horizon overrides.
- Added Drain routing, client-name aliases, qualitative stat focus, direct
  Horizon spell-page provenance, and stricter registry validation.
- Made the Lua runtime smoke test a mandatory release-build check.

## 0.1.0-alpha.1

- Added a standalone, read-only Ashita v4 addon entrypoint.
- Added event-driven inventory indexing and debounced refresh scheduling.
- Added effective-level, job, slot, ownership, and weapon-lock constraints.
- Added deterministic bounded-beam preview resolution and explanations.
- Added BLU and BLM proof-of-concept policies.
- Added BLU Learn, Chain Affinity, Burst Affinity, and Evasion indicators.
- Added generated, provenance-bearing seed catalog and hidden-effect data.
- Added a fail-closed read-only equip-plan contract and renderer-independent
  preview/delta helpers for the future executor and upgrade ladder.
- Preserved explicit BLM nuke priority-rack order when the focused balance
  slider changes.
- Added validated local preference persistence for policy and UI choices without
  persisting inventory or executable action state.
- Added the versioned action-context boundary for verified action metadata,
  multi-hit/WSC facts, and separate live-affinity versus manual-plan state.
- Added conservative full-set upgrade recommendations from verified unowned
  candidates, with replacements and objective deltas.
- Added bounded LRU resolved caching with inventory, action/buff, policy, weapon,
  and data-version key dimensions.
- Moved action metadata to a generated, Horizon-scoped source registry with
  verified-only schema validation and required provenance/confidence fields.
- Added the first seven source-backed BLU action rows plus distinct Breath,
  General Buff, and Skill Buff policies, including current-HP-sensitive breath
  behavior and verified-only runtime quarantine behavior.
- Added a level-legal manual action selector and `/gb action` preview command so
  reviewers can exercise verified routing without action interception.
- Added repository validation, reference-model tests, release packaging, and a
  Horizon-focused approval test plan.
- Adopted the MIT License for public review and community development.
