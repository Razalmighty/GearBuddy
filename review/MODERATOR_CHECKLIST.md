# Moderator checklist

## Source and build

- [ ] Confirm the reviewed commit matches the tagged release source.
- [ ] Confirm the GitHub Actions validation workflow passes for that commit.
- [ ] Confirm the release ZIP's SHA-256 manifest verifies.
- [ ] Confirm source is unobfuscated and the MIT license is present.

## Safety boundary

- [ ] Confirm no equipment executor is attached or included.
- [ ] Confirm plans remain `read_only = true` and `executable = false`.
- [ ] Confirm there is no outgoing packet hook or packet-injection call.
- [ ] Confirm inventory scans are event-driven and not performed continuously.
- [ ] Confirm persisted settings exclude inventory locations and executable state.

## Data behavior

- [ ] Confirm automatic selection is restricted to verified catalog rows.
- [ ] Confirm candidate evidence cannot generate runtime data or affect scoring.
- [ ] Confirm unknown values remain unknown rather than becoming zero.
- [ ] Confirm contributors are credited without private account information.

## In-game evidence

- [ ] Review unaltered `/gb selftest verbose` output; any `FAIL` blocks approval.
- [ ] Review unaltered `/gb report` and relevant bounded `/gb diag` lines.
- [ ] Confirm controls produce no outgoing equipment traffic.
- [ ] Confirm casts and abilities are not delayed, canceled, replaced, or resent.
- [ ] Confirm inventory generation remains stable while idle.
- [ ] Confirm unload leaves no continuing UI or command behavior.

Use the [full approval test plan](../docs/APPROVAL_TEST_PLAN.md) for the detailed
27-step functional procedure. Findings can be filed with the repository's
`HorizonXI approval finding` issue form.
