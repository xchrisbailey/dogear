# Dogear

## Layout and commands

- `Core/`: UI-free Swift package (`DogearCore`). Seam 1 tests run against a fake Grimmory Server (`Core/Tests/DogearCoreTests/Harness/`) with fixtures from real v3.5.0 responses: `swift test --package-path Core`.
- `App/`: SwiftUI app. `Dogear.xcodeproj` is generated from `project.yml` and not committed: `"$(readlink -f "$(command -v xcodegen)")" generate`, then `xcodebuild build -project Dogear.xcodeproj -scheme Dogear -destination "id=$UDID" -derivedDataPath .build/DD` on a simulator you created and delete afterwards.
- Packages: `Dogear.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is the only committed file under the generated project (XcodeGen keeps it). Commit it whenever a package in `project.yml` changes.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `xchrisbailey/dogear`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
