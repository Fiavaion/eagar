# Eagar

Eagar (working name; Irish *eagar*, "order") is an open-source, native personal organiser for iPhone, iPad and Mac, built from one multiplatform SwiftUI codebase. It turns appointments, deadlines, college bookings, Canvas, free trials, keep-in-touch, podcasts, YouTube and multi-account email into one brief delivered at natural breaks.

- **Per-source data boundaries, enforced in code.** Every record carries a data class; college data is processed only on the owner's own devices and never reaches a cloud AI, iCloud sync or backup.
- **Approve-before-send is absolute.** Nothing is sent without per-message approval bound to the exact outgoing message.
- **Rules first, AI second, cloud last.** Rules-only sources make no model calls; local models come before the Claude API, which uses your own key.

## Status

Pre-alpha. Milestone M0 (foundations) in progress.

## Repository layout

- `App/`: the multiplatform SwiftUI app and its test targets
- `Packages/`: local Swift packages holding all logic
- `docs/`: decisions, schemas, governance, benchmarks
- `Tools/`: lint and check scripts

See `CLAUDE.md` for the full layout and conventions.

## Build

```sh
brew install xcodegen
xcodegen generate --spec App/project.yml

# Unit tests for one package
swift test --package-path Packages/EagarAI

# All packages
for p in Packages/*/; do swift test --package-path "$p" || exit 1; done

# App build, iOS simulator
xcodebuild -project App/Eagar.xcodeproj -scheme Eagar \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# App build + unit/UI tests via the shared test plan, macOS
xcodebuild -project App/Eagar.xcodeproj -scheme Eagar -testPlan Eagar \
  -destination 'platform=macOS' test
```

## Sources of truth

`PRD.md`, `RESEARCH.md` and `docs/DECISIONS.md` are the sources of truth.

## Licence

MPL-2.0, see `LICENSE`.
