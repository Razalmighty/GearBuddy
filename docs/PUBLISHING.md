# Publication checklist

The source tree is GitHub-ready, but a repository owner and remote URL are not
embedded in the release. Perform the first publication only after confirming the
exact destination account.

## One-time repository setup

1. Create a public GitHub repository named `GearBuddy` with no generated README,
   license, or `.gitignore`; those files already exist here.
2. From the project root, initialize `main`, review every staged path, and make
   the first signed or otherwise attributable commit.
3. Add the confirmed repository as `origin` and push `main`.
4. Enable the included `validate` workflow. Require it on pull requests before
   merging to `main`.
5. Confirm issue forms and the pull-request template render correctly.

Example commands are intentionally placeholders until the owner and URL are
known:

```text
git init -b main
git add .
git status --short
git commit -m "Initial read-only GearBuddy approval build"
git remote add origin <confirmed-github-url>
git push -u origin main
```

Do not commit `dist/`; releases are reproducible from the tagged source. The CI
artifact is temporary review evidence, not the canonical release.

## Release validation

Run from a clean checkout:

```text
python tools/generate_data.py --check
python tools/validate_repo.py
python -m unittest discover -s tests
texlua tests/runtime_smoke.lua
python tools/build_release.py
python tools/verify_release.py dist/GearBuddy-v0.1.0-alpha.8-read-only.zip
```

Retain the ZIP SHA-256 printed by the build and the adjacent `.sha256` file.
Compare the local result with the GitHub Actions artifact before tagging.

## Tagged approval build

1. Confirm the repository owner and public support path.
2. Create an annotated `v<VERSION>` tag from the exact validated commit.
3. Push the tag and create a GitHub release from it.
4. Attach the deterministic ZIP and `.sha256` file without repacking them.
5. In the release notes, state that the addon is read-only and has no equipment
   executor, action interception, telemetry, or remote update path.
6. Open the HorizonXI approval issue with the exact commit, tag, ZIP SHA-256,
   `docs/APPROVAL_TEST_PLAN.md`, and expected self-test behavior.
7. Record findings with the included approval issue form.
8. Do not merge an equipment executor into the approval tag or move the tag
   after review starts.

Repository history must preserve reviewed JSON sources and generated Lua outputs
together so reviewers can diff both the evidence and runtime representation.
