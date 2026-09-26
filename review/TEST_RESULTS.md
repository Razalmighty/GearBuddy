# Test results

## Host-side validation

Status for the source revision containing this packet:

- Generated-data drift check: pass
- Repository/schema validation: pass
- Python unit suite: pass, 45 tests
- Lua 5.1 syntax validation: pass
- Lua runtime resolver smoke test: pass
- Deterministic release build and archive verification: pass

The same checks are defined in [the GitHub Actions workflow](../.github/workflows/validate.yml)
and run on every push and pull request. A reviewer should rely on the workflow
result for the exact GitHub commit under review, because this file is only a
human-readable summary.

## In-game validation

The real alpha.8 `/gb selftest verbose` and `/gb report` capture is pending.
The placeholder in [SAMPLE_REPORT.txt](SAMPLE_REPORT.txt) must be replaced with
unaltered output from the test environment before the formal approval request.
A raw inventory dump should not be attached.

The complete manual procedure and approval evidence list are in the
[HorizonXI approval test plan](../docs/APPROVAL_TEST_PLAN.md).
