# Permissions requested

GearBuddy requests approval to test and use `0.1.0-alpha.8` as a read-only
Ashita v4 addon on HorizonXI.

The requested scope is limited to:

- reading player job, effective level, and named buff state;
- reading accessible inventory and item-resource metadata;
- observing documented incoming packet IDs only as refresh hints, without
  parsing their payloads into gameplay automation;
- rendering local UI and handling `/gb` commands;
- saving validated local UI and planning preferences; and
- producing local self-test, status, report, and diagnostic output.

This request does not include permission to equip items, automate actions,
inject outgoing traffic, block packets, modify other addons, or enable the
future execution boundary. If reviewers approve only a narrower subset, the
project will treat that restriction as authoritative and revise the build
before use.

Requested reviewer decisions:

1. Is this read-only approval-test scope acceptable?
2. Are the observed incoming packet refresh hints acceptable as implemented?
3. Is any additional evidence required before an in-game test?
4. What conditions, labeling, or distribution limits should accompany approval?
