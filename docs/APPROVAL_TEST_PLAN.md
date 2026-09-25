# HorizonXI approval test plan

## Test build

Use the tagged read-only ZIP without adding LuAshitacast files. Record the Ashita
version, server zone, job, level, level-sync state, and enabled inventory bags.

## Functional checks

1. Load the addon and confirm `READ ONLY` appears in the console and HUD.
2. Wait for the first scheduled inventory generation, then run
   `/gb selftest verbose`. Confirm there are no `FAIL` rows. Record and explain
   any `WARN` rows; an empty cache may warn but must not fabricate a pass.
3. Run `/gb report`; confirm its version, read-only mode, self-test status,
   generation/refresh counts, last reason, resolver counts, cache counts, and
   scheduler state agree with the console.
4. Run `/gb refresh`; confirm the generation and refresh count each increment
   once after the debounce and the bounded history gains one reasoned record.
5. Move one verified seed item between accessible bags; confirm one later refresh
   and no repeated scan while idle.
6. Change job or level sync; confirm effective level changes and over-level items
   disappear from the preview.
7. On BLU, enable Learn and select Learning. Magus Bazubands should be preferred
   when owned and legal even though its effect magnitude is unknown.
8. Activate Chain Affinity and Burst Affinity in game; confirm their indicators
   follow named buff state. Test the manual planning toggles separately.
9. On BLM preview, move the nuke balance slider. Confirm objective order and the
   cached preview revision change.
10. Lock and unlock weapons. Confirm only the preview changes and TP is untouched.
11. With a sparse owned set, review the upgrade list. Confirm only verified,
   unowned, legal items appear and each recommendation shows its replacement and
   objective delta; protected weapon slots must not appear while locked.
12. Run `/gb diag`; confirm event reasons are understandable and bounded.
13. Unload and reload the addon. Confirm selected context, priority order,
    weapon lock, BLU toggles, BLM slider, and HUD visibility persist.
14. Confirm malformed or out-of-range preference values fall back safely and do
    not create inventory candidates or equipment actions.
15. Select the BLU Breath, General Buff, and Skill Buff contexts. Confirm each
    reports its distinct priority order and remains read-only.
16. Run `/gb actions`, then preview a legal row by name and ID with `/gb action`.
    Confirm the policy changes without casting or equipping; clear it afterward.
17. At BLU 75, confirm `/gb actions` exposes 106 verified rows. Preview
    `Queasyshroom`, `Blood Drain`, `Quad. Continuum`, `Winds of Promy.`,
    `Cannonball`, and `Magic Hammer`;
    confirm physical, drain, four-hit physical, and utility-buff routing,
    plus Cannonball's Defense focus and Magic Hammer's Drain routing. Confirm
    the alias displays the full Winds of Promyvion name.
18. Confirm Vanity Dive (28), Empty Thrash (32), Occultation (38), Auroral Drape
    (42), Quad. Continuum (54), and Winds of Promyvion (54) are level-legal at
    their recorded Horizon levels and remain unavailable below them.
19. Confirm Spiral Spin, Seedspray, Corrosive Ooze, Regurgitation, Asuran Claws,
    Triumphant Roar, and Sub-Zero Smash do not enter the verified action list.
    Confirm Plasma Charge does enter with lightning element, five set points,
    and a 60-second duration.
20. Open Force Swap. Select BLU Engaged and the Accuracy priority profile. Confirm
    each slot offers Auto plus only cached, owned, level/job/slot-legal items.
    Confirm opening dropdowns does not increment inventory generation.
21. Pin a lower-scoring owned ring to Ring1. Confirm Ring1 reads Manual, Ring2
    remains Formula, and the reported full-set totals include the trusted pinned
    stats while the remaining slots are re-optimized around it.
22. Pin the same item ID to Ring1 and Ring2 while owning one copy. Confirm one
    slot reports a physical-instance conflict and safely falls back. Repeat with
    two copies and confirm each slot resolves a distinct bag/index instance.
23. Pin a weapon, then enable weapon lock. Confirm the saved pin reports inactive
    because weapon policy has priority. Pin an item, level-sync below it, and
    confirm the saved preference falls back without being deleted.
24. Pin an owned legal item whose catalog stats are not verified. Confirm it is
    labeled Manual with unknown stats, contributes no invented score, and does
    not become eligible for automatic selection elsewhere. Confirm upgrades do
    not replace active pinned slots.
25. Preview Sandspin, Poison Breath, 1000 Needles, and Cannonball. Confirm the
    mechanics view separates landing, potency, duration, and utility and labels
    qualitative/unknown evidence without displaying invented coefficients.
26. Unload and reload. Confirm valid pins persist by item ID, not bag/index, and
    malformed pin scope/slot/item records are discarded safely.
27. Unload the addon. Confirm no continuing UI or command behavior.

## Host-side catalog checks

1. Run the bundled Ashita fixture through `tools/normalize_ashita_items.py`.
   Confirm the report hash matches the input, Main/Sub remains multi-slot,
   paired ring bits collapse to `Ring`, and description text remains
   evidence-only.
2. Merge the normalized fixture with an empty Horizon override file. Confirm all
   rows are `ID Verified` and cannot enter a runtime preview.
3. Run the Lua smoke test. Confirm one dual-slot owned instance fills only one
   physical slot, two instances may fill Main and Sub, and a Main-only lock still
   permits a compatible upgrade candidate in Sub.
4. Confirm pin regression coverage passes for manual-versus-formula attribution,
   missing and over-level fallback, duplicate physical instances, weapon locks,
   unverified stats, persistence migration, and upgrade protection.
5. Confirm mechanics validation rejects unknown outcomes with drivers,
   qualitative numeric weights, incomplete four-outcome rows, and unknown action
   references.
6. Confirm self-test regression coverage proves manager probes do not enumerate
   bags, unsafe plan flags fail, and refresh history is bounded.

## Safety checks

- Capture outgoing equipment traffic while changing GearBuddy controls. GearBuddy
  must produce none.
- Cast spells and use abilities with GearBuddy loaded. It must not delay, cancel,
  replace, or resend an action.
- Idle for five minutes with the console open and closed. Inventory generation
  must remain stable without a qualifying event.
- Send a burst of inventory updates. Diagnostics should show one coalesced scan,
  or a bounded forced scan followed by one settling scan.

## Evidence to attach

Attach the release manifest, validation output, `/gb selftest verbose`,
`/gb report`, relevant `/gb diag` lines, and any unexpected packet capture. File
findings through the included approval issue form. Do not attach a raw inventory
dump.
