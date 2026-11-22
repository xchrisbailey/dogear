# Dogear

## Layout and commands

- `Core/`: UI-free Swift package (`DogearCore`). Seam 1 tests run against a fake Grimmory Server (`Core/Tests/DogearCoreTests/Harness/`) with fixtures from real v3.5.0 responses: `swift test --package-path Core`.
- `App/`: SwiftUI app. `Dogear.xcodeproj` is generated from `project.yml` and not committed. `scripts/app.sh build` generates it and builds on a throwaway simulator; `scripts/app.sh compile` builds the app and its tests without booting one. Run anything else that needs a simulator through `scripts/with-simulator.sh <cmd>` (exports `$UDID`, always deletes the device); `scripts/with-simulator.sh status` checks for leftovers.
- `AppTests/`: seam 2, the CFI bridge on a real Readium navigator with a fixture EPUB (`AppTests/Fixtures/LighthouseLedger`, self-written, CC0): `scripts/app.sh test`.
- Guardrails: CI (`.github/workflows/ci.yml`) runs `scripts/check-*.sh`, seam 1 and `scripts/app.sh compile` on every PR, and seam 2 on main (its simulator boot takes minutes in CI; label a PR `seam-2` to run it there, and do when touching `App/Reader` or the Keychain store); the pre-commit hook runs the checks (enable once per clone: `git config core.hooksPath .githooks`). Review standards: `CODING_STANDARDS.md`.
- Merging a pushed branch: `scripts/merge-branch.sh <branch> [target]` (throwaway worktree; the main checkout never switches).
- Local config, outside the repo: `~/.config/dogear/env` (test Server and account, App Store Connect IDs; sourced by scripts) and `~/.config/dogear/secret-patterns`. Read values from there; never copy them into the repo.
- Grimmory API, Readium and AVFoundation behaviour (gotchas, endpoint shapes, upstream source paths): `docs/reference/`.
- Packages: `Dogear.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is the only committed file under the generated project (XcodeGen keeps it). Commit it whenever a package in `project.yml` changes.
- TestFlight: `scripts/testflight.sh` archives and uploads with cloud-managed signing. The App Store Connect API key (Admin) lives at `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`, never in the repo.
- TestFlight feedback: the `testflight` MCP server in `.mcp.json` (`scripts/testflight-mcp/server.mjs`, Node 18+, no dependencies, read-only) lists and fetches beta feedback (tester comments, screenshots, crash logs) with the same key. It reads `ASC_KEY_ID`/`ASC_ISSUER_ID` from the environment or `~/.config/dogear/env` (Claude Code doesn't source that file for MCP servers), or infers the key ID from a single `.p8` and the issuer from `~/.appstoreconnect/issuer_id`. Screenshots and crash logs land in `.build/testflight-feedback/<id>/`. It only runs on Chris's Mac: the cloud container can't reach `api.appstoreconnect.apple.com`, so cloud threads use it through Remote Control. Test: `node scripts/testflight-mcp/test.mjs`.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `xchrisbailey/dogear`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
