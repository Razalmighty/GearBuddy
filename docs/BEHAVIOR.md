# Runtime behavior

## Read-only guarantee

The addon registers `load`, `unload`, `packet_in`, `command`, and
`d3d_present`. It never registers `packet_out`, blocks gameplay packets,
queues equipment commands, intercepts actions, or calls packet-injection APIs.
The action selector is manual preview state only; it does not observe or alter a
cast and it is not persisted.

Recognized `/gb` chat commands are marked handled so they do not reach the game
server. This is command UI behavior, not gameplay packet interception.

## Inventory refresh events

A full inventory index is scheduled after:

- addon load;
- zone packet `0x00A`;
- job/level-sync packets `0x01B` and `0x061`;
- inventory packet hints `0x01D`, `0x01E`, `0x01F`, and `0x020`;
- `/gb refresh`.

Packet IDs are hints, not parsed payload contracts. A 250 ms quiet-window debounce
coalesces packet bursts, and a 1.5 second maximum delay prevents starvation. The
render callback performs a cheap scheduler check. It scans bags only when that
check releases scheduled work.

Every successful scan increments both an immutable generation and a refresh
counter. GearBuddy retains only the most recent eight generation/time/reason
records in memory. The history is reviewer observability, not another trigger;
reading it never schedules or performs a scan and it is never persisted.

## Buff refresh

Named buff state is sampled four times per second for indicators. This reads the
player's small buff array; it does not inspect inventory. Chain Affinity and Burst
Affinity are resolved by resource name instead of hard-coded status IDs.

## Fail-safe behavior

Runtime reads use protected calls. A failed scan retains no fabricated candidate
and records a diagnostic. Empty slots remain empty. Unknown stats and effects do
not become zero-valued evidence.

Resolved previews also expose a read-only equipment plan containing item IDs and
container/index locations for a future executor. The plan is explicitly marked
non-executable in this alpha; it never queues or sends an equipment change.

Local preferences are saved through Ashita's settings service. The saved scope
contains UI/policy choices and explicit stable item-ID gear pins. Inventory
entries, bag/index locations, player/buff state, resolved sets, and
action/execution state are never persisted.

## Force Swap behavior

The Force Swap editor operates entirely on the latest cached inventory
generation. Opening it or changing a dropdown does not call Ashita's inventory
API. A full index still occurs only for the events listed above.

Pins are scoped to `job:context:priority-profile`, where the first-ranked
objective names the profile. Each physical slot offers `Auto (GearBuddy)` plus
currently owned items whose Ashita resource metadata proves job, effective-level,
and slot legality. Selecting Auto removes the preference. The resolver restores
the item by stable ID on future generations and chooses a live bag/index only
for the current read-only plan.

Weapon locks supersede pins. One physical instance cannot fill two positions.
A missing, over-level, wrong-job, wrong-slot, or otherwise illegal saved pin is
reported and that slot falls back to verified automatic selection. Explicitly
pinned gear with unverified catalog stats is allowed as a preference but is
marked unknown and contributes no numeric stats or hidden-effect tags.

Upgrade recommendations run through the same pinned resolver. They may improve
an unpinned compatible slot, but never propose replacing an active pinned slot.

## Action-mechanics behavior

Action routing and action mechanics are versioned separately. The mechanics
view reports landing, potency, duration, and utility independently. Qualitative
evidence is displayed for review but does not become a coefficient, projection,
or score. Missing evidence appears as `unknown` and remains inert.

## Compatibility self-test

`/gb selftest` checks the configured read-only mode, absence of an attached
executor, Ashita manager and event availability, settings backend, scheduled
inventory cache, bounded refresh history, cached legality fields, player
context, preview-plan safety, and data registries. `verbose` prints passing
checks as well as warnings and failures. `/gb report` reruns the same probes and
adds aggregate player, cache, resolver, pin, and scheduler evidence.

The self-test obtains the inventory manager object to prove API compatibility,
but it never enumerates container counts or items. It consumes the existing
cache and therefore reports a warning if the first scheduled refresh has not
finished or no cached item exists. A warning is actionable context; any failed
read-only or plan-safety check is an approval blocker.

Cache behavior is bounded and event-driven. Repeated render calls reuse the
prepared result; inventory bursts are coalesced by the scheduler; buff/action,
level, context, priority, weapon-policy, and data-version changes invalidate the
relevant key without performing a bag scan on the render or action path. Pin and
mechanics-data revisions are cache-key dimensions as well.
