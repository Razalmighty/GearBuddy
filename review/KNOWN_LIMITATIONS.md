# Known limitations

- This is a BLU and BLM proof of concept, not a full-game optimizer.
- The reviewed runtime equipment catalog contains only seven fully verified
  seed items. Unverified gear cannot win automatic selection.
- The mechanics registry has four qualitative runtime rows and no active
  numeric formulas. Candidate multipliers and formulas remain quarantined.
- The preview reports verified gear contributions, not a character's complete
  combat totals or final damage.
- Base attributes, traits, food, songs, rolls, target defense, and complete
  spell-damage formulas are not reconstructed.
- The bounded-beam resolver is deterministic but is not yet a proof of global
  optimality for a future full catalog.
- Pins identify items by stable item ID; augment-aware fingerprints are future
  work.
- Incoming inventory packet IDs are refresh hints. If a server build does not
  emit the expected hint, the player must use `/gb refresh`.
- The first in-game alpha.8 self-test/report capture is still pending.
- Equipment execution is intentionally absent and outside this approval request.

Planned expansion is documented in the [roadmap](../docs/ROADMAP.md). A
limitation is not silently filled with inferred data; unknown values remain
visible and inert.
