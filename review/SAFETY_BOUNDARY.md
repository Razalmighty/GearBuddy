# Safety boundary

## What the approval build does

- Reads the player context, named buffs, and accessible inventory through
  Ashita v4 APIs.
- Rebuilds its inventory index only after documented events or `/gb refresh`.
- Resolves and displays equipment previews and upgrade suggestions.
- Saves UI and planning preferences, including item-ID pins.
- Exposes self-test, report, and bounded diagnostic output for review.

## What it does not do

- Equip, move, use, buy, sell, or discard an item.
- Send, inject, replace, delay, cancel, or block gameplay packets.
- Observe a cast in order to change equipment or actions.
- Issue equipment commands or attach an equipment executor.
- Read inventory continuously from the render loop.
- Persist inventory locations, inventory snapshots, buffs, or executable plans.
- Modify or generate LuAshitacast files.

The addon registers only the `load`, `unload`, `packet_in`, `command`, and
`d3d_present` events. Recognized `/gb` commands are consumed locally so they do
not reach game chat; this is command handling, not gameplay interception.

The future execution boundary is represented in source, but every alpha.8 plan
is explicitly `read_only = true` and `executable = false`. No executor is
included. Any future equipment-changing phase requires a separate code change
and explicit approval from the project owner and HorizonXI reviewers.

See [Runtime behavior](../docs/BEHAVIOR.md) and
[Architecture](../docs/ARCHITECTURE.md) for the complete implementation detail.
