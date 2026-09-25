# Architecture

GearBuddy separates source data, runtime state, policy, resolution, and rendering.
Reviewers can inspect every input and reproduce a decision without trusting an
opaque score.

## Data flow

1. `core/inventory_index.lua` creates an immutable inventory generation from
   accessible equip bags.
2. `core/context.lua` reads effective job level, preview job, and named buffs.
3. `core/policy.lua` loads one strict objective order, applies user reordering,
   and names the first objective as the stable priority profile.
4. `core/item_legality.lua` applies shared Ashita resource and reviewed-catalog
   legality checks to automatic candidates and explicit manual preferences.
5. `core/gear_pins.lua` maps stable item-ID preferences back to currently owned
   legal physical instances without rescanning inventory.
6. `core/resolver.lua` fixes active pins first, then filters and optimizes the
   remaining catalog candidates by verification, ownership, job, effective
   level, slot, and weapon policy.
7. `core/score.lua` compares bounded-beam states lexicographically and uses a
   stable signature for deterministic ties.
8. `core/resolved_cache.lua` caches results by inventory generation, policy,
   and pin revision.
9. `core/equip_plan.lua` converts a resolved result into a fail-closed,
   read-only plan with explicit locked, pinned, and unresolved slots.
10. `core/preview.lua` exposes renderer-independent totals, objective details,
    and set-to-set deltas for the console and future upgrade ladder.
11. `core/persistence.lua` loads and validates local preferences and stable item
    pins only; inventory snapshots, bag/index locations, buffs, and executable
    action state never enter the settings document.
12. `core/action_context.lua` resolves versioned action metadata by ID, readable
    name, or verified alias and reports category, hit count, WSC, qualitative
    stat focus, Horizon provenance, element, and affinity state.
13. `core/action_mechanics.lua` exposes independent landing, potency, duration,
    and utility evidence; qualitative or unknown rows remain numerically inert.
14. `core/upgrade.lua` evaluates virtual unowned candidates through the same
    resolver and returns explainable full-set marginal recommendations.
15. `core/self_test.lua` probes the required Ashita object surface and inspects
    cached state, registry counts, refresh history, and plan safety. It never
    enumerates a container or mutates gameplay state.
16. `ui/console.lua` and `ui/hud.lua` render existing state. They never scan bags.

Catalog schema v2 stores slot compatibility as an array. This matters for
one-handed weapons that can occupy Main or Sub while preserving the existing
generic Ear and Ring classes. At resolution time, compatibility is checked
against the actual Ashita slot bit and the candidate records the physical slot
chosen. The shared `instance_key` still prevents one owned copy from filling two
positions.

## Manual preference precedence

The resolver applies this order:

1. Ashita job, effective-level, slot, ownership, and equippable legality;
2. locked weapon policy;
3. active job/context/priority-profile pins;
4. required categorical effects;
5. strict formula objectives;
6. empty-slot fallback when no candidate is safe.

Pins are resolved before beam expansion and their trusted stats/tags seed the
initial state. This makes the optimizer solve the rest of the set around the
player's preference. Ring1/Ring2 and Ear1/Ear2 are independent physical slots;
the shared `instance_key` prevents one copy from satisfying two pins or a pin
and an automatic slot. A missing or newly illegal pin remains saved, emits a
reason, and falls back to formula selection for that resolution. A pin on a
locked weapon slot remains inactive until the weapon policy permits it.

Pins store an item ID, never a live bag/index. Augment-aware fingerprints are a
future schema change and are not guessed in this release. An explicit manual pin
may target a legal item outside the verified catalog, but `core/candidate.lua`
then supplies empty stats/tags and marks `stats_trusted = false`. This preference
does not promote the item into the automatic candidate pool.

The offline Ashita resource adapter is outside the runtime data flow. It decodes
`IItem` masks and structured weapon fields into a quarantined catalog base; raw
descriptions remain review evidence and are not interpreted as stats. The merge
stage is the only route from that base into reviewed runtime data.

## Why a bounded beam

A slot-by-slot greedy choice cannot enforce duplicate-instance constraints across
two ring or ear slots. Exhaustive enumeration becomes impractical with a complete
catalog. The alpha keeps the best 64 partial states after each slot. This is
deterministic and sufficient for the verified seed, but it is not a proof of
global optimality for the eventual full catalog. The production solver will add
dominance pruning and exact fallback for small candidate spaces.

## Future execution boundary

The resolver returns an item plan containing item ID, bag, and index. A future
executor can consume that resolved plan without repeating a bag scan. That
executor does not exist in this release.

`core/equip_plan.lua` is the boundary for that future executor. Alpha plans are
always marked `read_only = true` and `executable = false`; locked Main/Sub/Range
slots are represented as policy decisions rather than omitted silently. This
lets the approval build prove the shape of an execution plan without sending
equipment packets.

`core/preview.lua` intentionally has no Ashita dependency. It keeps the UI and
future upgrade ladder from recomputing stats or scanning inventory: the console
can render prepared totals, strict objective values, missing required effects,
and deterministic stat/slot deltas from cached results.

`core/persistence.lua` is a narrow preference boundary. It round-trips selected
job/context, unique priority orders, focused controls, weapon-lock state, BLU
planning toggles, HUD/console visibility, and stable item-ID pins. Schema, type,
range, context, profile, slot, and item-ID validation are applied on load;
malformed values fall back to safe defaults. Schema-v1 preferences migrate with
an empty pin map.

`core/action_context.lua` is intentionally separate from the resolver. Action
rows are keyed by verified action ID with readable-name aliases and can include
category, context, skill, element, hit count, WSC coefficients, qualitative stat
focus, and TP/CA/BA behavior. Unknown actions return no context rather than being
guessed into a generic physical or magical bucket. Active Chain Affinity/Burst Affinity comes
only from the named buff state; manual planning toggles are reported separately.
The production registry is loaded with a verified-only runtime gate, so a stale
or hand-edited pending row is quarantined even if static validation was skipped.
Tracker priority, best use, era notes, and granted job trait remain attached to
each row. For a verified manual action preview, qualitative stat focus reorders
only objectives already exposed by the policy; the user's manual priority order
is applied afterward and remains authoritative.

`core/action_mechanics.lua` is a second boundary rather than an extension of the
action-routing row. Each registered action must explicitly represent landing,
potency, duration, and utility. A relationship can be `verified_numeric`,
`qualitative`, or `unknown`; only reviewed numeric records may ever carry a
formula. Alpha.8 uses this registry for explanation and cache versioning only.
It deliberately does not translate qualitative drivers into stat weights.

`core/upgrade.lua` does not maintain a second scoring model. It injects one
verified, legal, unowned catalog row at a time as a virtual inventory instance,
runs the normal resolver, and keeps only candidates that improve the strict
policy. Recommendations include the replaced item, raw and capped objective
deltas, source ID, and verification state. Protected weapon slots are skipped
when the weapon policy is locked, and active pinned slots are never proposed as
replacements. Compatible unpinned paired slots remain eligible.

The resolved cache is bounded and least-recently-used. Its key includes the
inventory generation, effective job and level, selected context, action/buff
signature, priority and pin revisions, manual/weapon-policy versions, and
gear/effect/action/mechanics data versions. A render callback can therefore
reuse a prepared result without
scanning or optimizing; a relevant event changes the key or schedules an
inventory generation rebuild.

`core/self_test.lua` is intentionally outside the resolution path. It asks
Ashita only for manager/player/party/inventory objects, then inspects the latest
cached inventory entry. It does not call `GetContainerCountMax` or
`GetContainerItem`. Its report is held in memory, is not part of cache identity,
and is not persisted. The approval report exposes counts and reasons rather than
item names or a complete inventory list.
