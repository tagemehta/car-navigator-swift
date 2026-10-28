---
name: ios-build-test
description: Build the thing-finder iOS app and run its XCTest suite from the command line with xcodebuild. Use to verify any Swift change before reporting it done.
---

# Build and test thing-finder

Run from the repo root (the directory containing `thing-finder.xcodeproj`).

**Exit status:** every command below pipes into `tail`, so it must start with `set -o pipefail` in the **same** shell invocation. One-shot exec calls don't keep shell state. Without it, the pipeline returns `tail`'s exit code (0) even when `xcodebuild` fails (65). Judge pass or fail by the exit code. A nonzero exit is a failure even if the tail output looks clean.

## 1. Pick a simulator
```bash
xcrun simctl list devices available | rg iPhone | head -3
```
Use the first iPhone name (e.g. `iPhone 16 Pro`) as `$SIM` below.

## 2. Build (fast check for compile errors)
```bash
set -o pipefail
xcodebuild build -project thing-finder.xcodeproj -scheme thing-finder \
  -destination "platform=iOS Simulator,name=$SIM" -quiet 2>&1 | tail -40
```

## 3. Test
Whole suite:
```bash
set -o pipefail
xcodebuild test -project thing-finder.xcodeproj -scheme thing-finder \
  -destination "platform=iOS Simulator,name=$SIM" -quiet 2>&1 | tail -60
```
One class or method (much faster; prefer this while iterating). Keep `set -o pipefail` and the `| tail` from above:
```bash
set -o pipefail
xcodebuild test ... -only-testing:thing-finderTests/VerifierSelectorTests 2>&1 | tail -60
xcodebuild test ... -only-testing:thing-finderTests/VerifierSelectorTests/testSomething 2>&1 | tail -60
```

## Facts
- Schemes: `thing-finder` (dev) and `thing-finder-prod`. Targets: `thing-finder`, `thing-finderTests`. Test plan: `thing-finderTests/thing-finder.xctestplan`.
- Tests are grouped by layer under `thing-finderTests/` (`Core`, `Services`, `Verification`, `Navigation`, `Utilities`, …). Shared fakes live in `Mocks/`, canned API JSON in `Fixtures/`. Put new tests beside their layer and reuse those helpers.
- `thing-finder/Secrets.xcconfig` and `CVModels/` are gitignored. If the build fails on a missing YOLO model or missing keys, stop and tell the user; do not create or commit secrets.
- Editor "No such module" import errors are a VS Code indexing artifact. Trust `xcodebuild`, not the editor.
- Pipe output through `tail`, always with `set -o pipefail`. Full xcodebuild logs are huge and waste context.
- Report: the exit code, build result, tests run/passed/failed, and the first failure message with file:line.
