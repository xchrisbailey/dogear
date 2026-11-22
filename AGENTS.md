# Dogear

## Layout and commands

- `Core/`: UI-free Swift package (`DogearCore`). Seam 1 tests run against a fake Grimmory Server (`Core/Tests/DogearCoreTests/Harness/`) with fixtures from real v3.5.0 responses: `swift test --package-path Core`.
- `App/`: SwiftUI app. `Dogear.xcodeproj` is generated from `project.yml` and not committed: `"$(readlink -f "$(command -v xcodegen)")" generate`, then `xcodebuild build -project Dogear.xcodeproj -scheme Dogear -destination "id=$UDID" -derivedDataPath .build/DD` on a simulator you created and delete afterwards. Simulator builds are signed ad hoc so the Keychain works (no team needed); device builds need `DEVELOPMENT_TEAM=<team id>` or a team picked in Xcode.
- `AppTests/`: seam 2, the CFI bridge on a real Readium navigator with a fixture EPUB (`AppTests/Fixtures/LighthouseLedger`, self-written, CC0). Same as the build command with `test` instead of `build`.
- Packages: `Dogear.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is the only committed file under the generated project (XcodeGen keeps it). Commit it whenever a package in `project.yml` changes.
- TestFlight: `ASC_KEY_ID=… ASC_ISSUER_ID=… scripts/testflight.sh` archives and uploads with cloud-managed signing. The App Store Connect API key (Admin) lives at `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`, never in the repo.
- TestFlight feedback: the `testflight` MCP server in `.mcp.json` (`scripts/testflight-mcp/server.mjs`, Node 18+, no dependencies, read-only) lists and fetches beta feedback (tester comments, screenshots, crash logs) with the same key. It reads `ASC_KEY_ID`/`ASC_ISSUER_ID` from the environment or `~/.config/dogear/env` (Claude Code doesn't source that file for MCP servers), or infers the key ID from a single `.p8` and the issuer from `~/.appstoreconnect/issuer_id`. Screenshots and crash logs land in `.build/testflight-feedback/<id>/`. It only runs on Chris's Mac: the cloud container can't reach `api.appstoreconnect.apple.com`, so cloud threads use it through Remote Control. Test: `node scripts/testflight-mcp/test.mjs`.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `xchrisbailey/dogear`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
