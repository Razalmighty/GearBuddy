# Moderator review packet

This folder is the short entry point for reviewing GearBuddy
`0.1.0-alpha.8`. It links to the authoritative project files instead of
duplicating specifications that could drift.

GearBuddy is an open-source, read-only equipment planner for Ashita v4 on
HorizonXI. This approval build indexes accessible inventory, checks item
legality, and displays deterministic equipment previews. It does not equip
items, intercept actions, inject packets, or modify LuAshitacast.

## Suggested review order

1. Read [Safety boundary](SAFETY_BOUNDARY.md).
2. Read [Permissions requested](PERMISSIONS.md).
3. Use the [Moderator checklist](MODERATOR_CHECKLIST.md).
4. Consult [Data methodology](DATA_METHODOLOGY.md) and
   [Known limitations](KNOWN_LIMITATIONS.md) for evidence and scope details.
5. Review [Test results](TEST_RESULTS.md) and the pending
   [in-game sample report](SAMPLE_REPORT.txt).

## Authoritative project material

- [Runtime behavior](../docs/BEHAVIOR.md)
- [Architecture](../docs/ARCHITECTURE.md)
- [Data policy](../docs/DATA_POLICY.md)
- [Evidence ledger](../docs/EVIDENCE_LEDGER.md)
- [Full approval test plan](../docs/APPROVAL_TEST_PLAN.md)
- [Source code](../gearbuddy.lua)
- [License](../LICENSE)

The installable ZIP should be taken from a tagged GitHub Release or its matching
GitHub Actions artifact. The ZIP includes source code and a SHA-256 manifest;
this repository does not commit generated release archives.
