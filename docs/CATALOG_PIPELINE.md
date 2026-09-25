# Equipment catalog ingestion

The runtime catalog is reviewed Horizon data, not a raw client resource dump.
The pipeline has three explicit layers:

1. An English Ashita v4 `IItem` export supplies client identity and legality
   fields.
2. `tools/normalize_ashita_items.py` decodes slot and job masks into a
   deterministic schema-v2 base while retaining the input SHA-256 and raw item
   description as review evidence.
3. A Horizon override file makes an explicit `verify`, `partial`, or `exclude`
   decision. `tools/merge_catalog_sources.py` combines the base and overrides.

Every untouched base row enters the merged catalog as `ID Verified` and cannot
win an optimization. A verified override must cite a Horizon source and explain
every value that differs from the base. Hidden and conditional effects remain
separate records.

## Why descriptions are not parsed automatically

Ashita exposes structured item ID, flags, level, slot mask, job mask, damage,
delay, and related resource metadata. Most armor attributes and descriptive
effects are text in `Description`, not distinct numeric fields. The normalizer
therefore promotes only the unambiguous structured `Damage` and `Delay` fields
into candidate stats. It retains `Description` under `resource_evidence` but
never converts text such as `STR+`, haste, latent effects, set bonuses, or
Horizon-specific behavior into optimizer values.

This is intentional: description parsing can help a reviewer later, but it
cannot establish Horizon availability, exact hidden behavior, or server
overrides by itself.

## Ashita export contract

The adapter consumes a JSON object whose item rows preserve the Ashita `IItem`
field names. `Name` and `Description` must already be the English strings chosen
by the exporter; the adapter does not guess a language-array index.

```json
{
  "schema_version": 1,
  "resource_schema": "Ashita v4 IItem",
  "resource_version": "client-resource-build-or-note",
  "language": "English",
  "source_id": "S017",
  "extracted_on": "2026-09-25",
  "items": [
    {
      "Id": 17663,
      "Flags": 2048,
      "Level": 73,
      "Slots": 3,
      "Jobs": 65536,
      "Name": "Example Blade",
      "Description": "DMG:32 Delay:229",
      "Damage": 32,
      "Delay": 229,
      "Type": 4,
      "ResourceId": 17663,
      "ItemLevel": 0,
      "SuperiorLevel": 0,
      "DPS": 1397,
      "Skill": 3
    }
  ]
}
```

Required row fields are `Id`, `Flags`, `Level`, `Slots`, `Jobs`, `Name`,
`Description`, `Damage`, and `Delay`. The remaining numeric evidence fields are
optional. The adapter rejects duplicate IDs, invalid types, unknown slot bits,
non-English metadata, and malformed dates. Rows without Ashita's equippable flag
`0x800` or without an equipment slot are counted and omitted.

Run the adapter offline; it is not loaded by GearBuddy and does not scan inside
the render loop:

```text
python tools/normalize_ashita_items.py \
  --input work/ashita_items_export.json \
  --base-out work/items_base.json \
  --report-out work/ashita_normalization_report.json
```

The base output records the exact input SHA-256. Main/Sub compatibility remains
`["Main", "Sub"]`; the two ear bits collapse to `["Ear"]`, and the two ring
bits collapse to `["Ring"]`. The runtime expands the generic ear/ring classes
back to their two physical positions and prevents one owned instance from being
selected twice.

## Normalized base format

```json
{
  "schema_version": 2,
  "source_id": "S017",
  "source_type": "Ashita v4 IItem",
  "extracted_on": "2026-09-25",
  "language": "English",
  "input_sha256": "64-lowercase-hex-characters",
  "items": [
    {
      "id": 17663,
      "name": "Example Blade",
      "slots": ["Main", "Sub"],
      "required_level": 73,
      "jobs": ["BLU"],
      "stats": {"damage": 32, "delay": 229},
      "resource_evidence": {
        "flags": 2048,
        "slots_mask": 3,
        "jobs_mask": 65536,
        "raw_description": "DMG:32 Delay:229"
      }
    }
  ]
}
```

`resource_evidence` stays in the review base and is deliberately omitted from
the merged runtime catalog.

## Horizon override format

```json
{
  "schema_version": 1,
  "data_version": 2,
  "server_scope": "HorizonXI",
  "items": [
    {
      "id": 14939,
      "decision": "verify",
      "source_id": "S009",
      "last_verified": "2026-09-25",
      "set": {"stats": {"magic_accuracy": 3}},
      "resolutions": {
        "stats.magic_accuracy": "Current Horizon equipment page documents Magic Accuracy +3."
      },
      "effects": [],
      "notes": "Reviewed Horizon row."
    }
  ]
}
```

## Merge command

```text
python tools/merge_catalog_sources.py \
  --base work/items_base.json \
  --overrides work/horizon_overrides.json \
  --catalog-out work/catalog_candidate.json \
  --effects-out work/effects_candidate.json \
  --report-out work/catalog_report.json
```

The merge refuses duplicate IDs, unknown override targets, unsupported or
repeated slots/jobs, nonnumeric stats, silent verified changes, and duplicate
effect IDs. It still accepts the alpha.5 single-`slot` base format as a migration
input, but always emits schema-v2 `slots` arrays.

Candidate outputs do not replace `data/catalog_source.json` automatically. They
must pass review and repository validation before promotion. This prevents a
large client resource import from silently treating out-of-era, unobtainable, or
Horizon-modified equipment as optimizer-eligible.
