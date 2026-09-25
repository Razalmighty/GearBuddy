# GearBuddy

GearBuddy is an event-driven equipment planning addon for HorizonXI and Ashita v4.
This `0.1.0-alpha.8` build is deliberately **read-only**: it indexes accessible
inventory, applies verified job/level/slot constraints, resolves a deterministic
preview set, and explains the result. It does not equip gear, intercept actions,
inject packets, or modify LuAshitacast.

## Approval-alpha scope

- BLU proof of concept: engaged, physical magic, magical magic, debuff, drain,
  healing, breath, general buff, skill buff, learning, evasion, idle, PDT, and
  MDT contexts.
- BLM proof of concept: adjustable magic-accuracy versus damage priority for
  nukes, plus fast cast, idle, resting, PDT, and MDT contexts.
- Event-driven inventory refresh on load, zone change, job/level-sync change,
  observed inventory packets, or `/gb refresh`.
- Debounced scans and a generation-keyed resolved-set cache. No bag scan runs in
  the render loop unless a scheduled refresh is due.
- A built-in compatibility self-test checks the Ashita API surface, event hook,
  settings backend, cached item/resource shape, player context, data registries,
  and the non-executable plan boundary without enumerating bags. A bounded scan
  history and `/gb report` make event-driven behavior auditable in game.
- Weapon slots are locked by default. Unlocking them changes previews only.
- Visible BLU indicators for Learn, Chain Affinity, Burst Affinity, and Evasion.
- Validated local persistence for policy/UI preferences and stable item-ID gear
  pins; inventory snapshots, bag/index locations, and executable action state
  are never saved.
- A Force Swap editor lets the player pin an owned, job/level/slot-legal item to
  each physical slot for a stable job/context/priority profile. `Auto` clears a
  pin. Weapon locks remain higher priority, paired slots require separate
  physical copies, invalid pins fall back visibly, and the optimizer recalculates
  every unpinned slot around the active manual choices.
- Manual selection may use legal owned gear whose catalog stats are not verified.
  Such gear is labeled `stats unverified`, contributes no invented numeric
  value, and never becomes an automatic candidate merely because it was pinned.
- Versioned source metadata includes all 113 Horizon-tracker BLU spells from
  level 1 through 75 across physical, magical, debuff/control, drain, dispel,
  healing, breath, and buff paths. The 106 fully verified rows enter the runtime;
  seven WotG-era rows excluded from Horizon's canonical level-51–75 list remain
  quarantined, and unknown actions are never
  guessed into generic categories.
- Action metadata is source-backed and schema-validated; IDs, legality,
  provenance, confidence, and verification are required before a row can enter
  the runtime registry.
- Read-only upgrade recommendations evaluate verified unowned candidates through
  the same full-set resolver and show replacements plus objective deltas.
- Seven fully verified seed items and three explicit hidden/conditional effect
  records from the project workbook. Partial catalog rows cannot win by default.
- A deterministic offline Ashita `IItem` adapter now decodes job and slot masks,
  preserves the source-export SHA-256 and description evidence, and promotes only
  structured damage/delay fields. Imported rows remain identity-only until a
  reviewed Horizon override promotes them.
- Catalog schema v2 supports true multi-slot compatibility such as Main/Sub
  weapons while retaining duplicate-instance protection for paired ear and ring
  positions.
- BLU breath, general-buff, and skill-buff preview policies preserve the current
  HP-sensitive and Blue-Magic-skill-sensitive routing boundaries.
- Six Horizon level changes are explicit override records rather than silent
  edits, and every action row links to its relevant Horizon evidence page.
- Plasma Charge uses the current Horizon values: lightning element, five set
  points, and a 60-second duration. The stale/client disagreements remain in
  structured, resolved conflict records.
- Tracker priority, best use, era notes, and granted job trait are preserved on
  every spell. Verified qualitative stat focus changes the read-only policy
  order for the selected action without inventing numeric WSC coefficients.
- A separately versioned action-mechanics registry represents landing, potency,
  duration, and utility as independent outcomes. Alpha.8 includes four
  qualitative boundary rows and displays unverified relationships as unknown;
  the registry does not yet alter numeric gear scoring.

This is not yet the full-game optimizer. Its purpose is to prove the runtime,
data, validation, UI, performance, and reviewer-observability architecture before
equipment execution is considered.

## Install

1. Copy the `GearBuddy` folder into `Ashita/addons/`.
2. In game, run `/addon load GearBuddy`.
3. Run `/gb` to open the console.
4. After the first inventory generation appears, run `/gb selftest verbose`.
5. Run `/gb refresh` after moving items if the automatic inventory packet hint is
   not emitted by the server build under test.

## Commands

| Command | Result |
| --- | --- |
| `/gb` | Toggle the main console |
| `/gb show`, `/gb hide` | Show or hide the console |
| `/gb refresh` | Schedule a debounced inventory rebuild |
| `/gb status` | Print cache, player, and preview status |
| `/gb selftest [verbose]` | Run read-only Ashita compatibility and safety probes |
| `/gb report` | Print a compact approval report plus non-passing self-test checks |
| `/gb job auto\|blu\|blm` | Use the live job or preview BLU/BLM |
| `/gb context <name>` | Select a context; use `/gb contexts` to list choices |
| `/gb actions` | List verified actions legal for the preview job and level |
| `/gb action <id\|name\|clear>` | Select or clear a manual read-only action preview |
| `/gb pin <slot> <item-id\|auto>` | Set or clear a pin for the active priority profile |
| `/gb pin <context> <profile> <slot> <item-id\|auto>` | Edit another stable profile by command |
| `/gb pins [context] [profile]` | Print saved pins for a profile |
| `/gb weapons lock\|unlock` | Include or exclude weapon slots in previews |
| `/gb learn\|evasion\|chain\|burst on\|off\|toggle` | Set manual BLU modes |
| `/gb hud on\|off\|toggle` | Control the compact indicator window |
| `/gb diag` | Print recent internal events for reviewer testing |

Context names accept aliases such as `engaged`, `physical`, `magical`,
`debuff`, `drain`, `learning`, `evasion`, `nuke`, and `fastcast`.

## Reading the preview

The preview reports gear-derived values only. It does not yet reconstruct base
character attributes, traits, food, buffs, songs, rolls, target defense, or spell
formula damage. A displayed `Accuracy +4` is a verified equipment contribution,
not the character's final combat stat.

Priorities are strict and unique. Moving one objective up or down shifts the
others. Haste uses a 25% equipment preview cap. BLM's nuke balance control changes
whether magic accuracy or damage stats lead the strict order.

The first objective names the active priority profile. For example, moving
Accuracy to rank 1 activates the `Accuracy` profile and its own saved pins;
moving Haste back to rank 1 activates the separate `Haste` profile. The Force
Swap editor can edit any context/profile and offers only cached, currently owned
items that Ashita reports legal for the preview job, effective level, and slot.
Opening a dropdown does not rescan bags.

## Reviewer documents

- [Runtime behavior](docs/BEHAVIOR.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Data and hidden-effect policy](docs/DATA_POLICY.md)
- [Equipment catalog ingestion](docs/CATALOG_PIPELINE.md)
- [Horizon approval test plan](docs/APPROVAL_TEST_PLAN.md)
- [Publication checklist](docs/PUBLISHING.md)
- [Roadmap](docs/ROADMAP.md)

## Build and validation

```text
python tools/generate_data.py --check
python tools/validate_repo.py
python -m unittest discover -s tests
texlua tests/runtime_smoke.lua
python tools/build_release.py
python tools/verify_release.py dist/GearBuddy-v0.1.0-alpha.8-read-only.zip
```

The release ZIP contains the complete source and a SHA-256 manifest. No code is
obfuscated. GitHub Actions repeats the generated-data, static, Python, Lua,
release-build, and archive-verification checks on every push and pull request.

## License

GearBuddy is released under the MIT License. See `LICENSE`.
