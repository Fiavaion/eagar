# CLAUDE.md — Eagar

Eagar (working name; Irish *eagar*, "order") is an open-source, native personal organiser for iPhone, iPad and Mac, built from one multiplatform SwiftUI codebase. It turns appointments, deadlines, NCAD bookings (cdbooking), Canvas, free trials, keep-in-touch, podcasts, YouTube and multi-account email into one brief delivered at natural breaks. Owner: Mark (NCAD). Licence: MPL-2.0.

## Source of truth

1. `PRD.md` — owner decisions (OD-1…OD-6, §6.0), binding decisions (BD-xx), FRs, milestones M0–M6 with acceptance criteria and an "FRs delivered" list per milestone. **Binding.** Owner decisions override everything else, including BDs and RESEARCH.md.
2. `RESEARCH.md` — evidence and constraints behind the PRD. Read the relevant section before implementing a feature.
3. `docs/DECISIONS.md` — decisions made during the build (ADR style). Append; never rewrite history.

If code, PRD and research disagree, the PRD wins. If the PRD is silent or ambiguous, stop and ask (see "Ambiguity").

## How to work

- **One milestone at a time.** Find the current milestone in `docs/DECISIONS.md` ("Current milestone: Mn"). Do not start Mn+1 until every Mn acceptance criterion in `PRD.md` §10 passes and Mark has signed off.
- Before coding a feature, list the FR IDs and acceptance criteria it satisfies. Reference them in commit messages and test names.
- Small, reviewable steps. Build and test after each step. Never leave the build red.
- Do not add scope from later milestones, even if it looks easy. Note ideas in `docs/DECISIONS.md` under "Parked".
- When an acceptance criterion needs Mark (live account, device test, external setup such as cdbooking endpoints or a Cloudflare account), prepare everything, then ask him to run it and record the result.

## Repository layout

```
App/Eagar.xcodeproj          # one project; shared scheme "Eagar"
App/Eagar.xctestplan         # test plan "Eagar": app tests + every local package's tests
App/Config/Base.xcconfig     # bundle prefix and team ID placeholders
App/Eagar/                   # multiplatform SwiftUI app target (iOS, iPadOS, macOS 26+; not Catalyst)
App/EagarTests/ App/EagarUITests/
App/EagarWidgets/            # M1: widgets, Controls (kill switch), Live Activities
App/EagarIntents/            # M1: App Intents extension
App/EagarShare/              # M2: share extension (trial import)
App/EagarHub/                # M3: macOS login item: hub (+ MCP server in M6)
App/EagarNotificationService/  # M5
App/EagarWatch/              # M6, optional
Packages/Eagar*/             # all logic lives in local Swift packages (PRD §7.2)
PushServer/                  # M5: Cloudflare Worker (TypeScript)
docs/                        # DECISIONS.md, schemas/ (eagar-rules + fixtures/), governance/, benchmarks/
Tools/                       # lint.sh and check scripts used by CI
.github/workflows/ci.yml
```

Create an extension target or package only when the milestone that needs it starts (PRD §7.2, M0 deliverables). M0 creates the app, test targets and the packages `EagarCore`, `EagarStore`, `EagarSecurity`, `EagarLedger`, `EagarAI`, `EagarRules` (codec only) and `EagarTestSupport`. The Xcode project itself is created by Mark in Xcode or generated with XcodeGen, per D-001; do not hand-write a `.pbxproj`.

Package dependencies follow the layer list in PRD §7.2 (downward only: `EagarCore` ← `EagarStore`/`EagarSecurity` ← `EagarLedger`/`EagarSync`/`EagarHubKit` ← `EagarAI` ← domain packages ← `EagarBrief`/`EagarSuggest`/`EagarMCP` ← app). Only `EagarAI` may import `FoundationModels` or talk to model endpoints.

## Build and test

The scheme `Eagar` and test plan `Eagar` are fixed by PRD M0. Verified with Xcode 27.1 and the iOS 26.5 simulator runtime (D-009); update the simulator names whenever Xcode changes them. The project is generated (D-001): run `xcodegen generate --spec App/project.yml` first and after any change to `project.yml`. Unsigned local builds can pass `CODE_SIGN_IDENTITY=-`; macOS Keychain access needs `DEVELOPMENT_TEAM` in `App/Config/Local.xcconfig`.

```sh
# Unit tests for one package (fast; run constantly)
swift test --package-path Packages/EagarAI

# All packages
for p in Packages/*/; do swift test --package-path "$p" || exit 1; done

# Generate the Xcode project (D-001)
xcodegen generate --spec App/project.yml

# App build, iOS simulator
xcodebuild -project App/Eagar.xcodeproj -scheme Eagar \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# App build + unit/UI tests via the shared test plan, macOS
xcodebuild -project App/Eagar.xcodeproj -scheme Eagar -testPlan Eagar \
  -destination 'platform=macOS' test

# Same tests, iOS simulator
xcodebuild -project App/Eagar.xcodeproj -scheme Eagar -testPlan Eagar \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# iPad
xcodebuild -project App/Eagar.xcodeproj -scheme Eagar \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build

# Boundary and invariant suite only (must always pass)
swift test --package-path Packages/EagarCore --filter Boundary
swift test --package-path Packages/EagarAI --filter Boundary
swift test --package-path Packages/EagarStore --filter Boundary
swift test --package-path Packages/EagarCompose --filter SendInvariant   # from M3, when EagarCompose exists

# Lints (no print, no secrets, import/host boundary, pinned deps, string catalogs) and their self-test
Tools/lint.sh
Tools/lint-selftest.sh

# After adding UI strings: merge extracted strings into the catalog with a ga scaffold (D-008)
Tools/sync-strings.py ~/Library/Developer/Xcode/DerivedData/Eagar-*/

# Push server (from M5)
cd PushServer && npm ci && npm test
```

Simulator names change with Xcode releases; use `xcrun simctl list devices available` and update the commands above.

## Coding conventions

- **Swift 6 language mode, strict concurrency complete.** Warnings are errors in CI. No `@unchecked Sendable` or `nonisolated(unsafe)` without a comment explaining why and a DECISIONS.md entry.
- **SwiftUI + Observation** (`@Observable`). No Combine for new code unless an Apple API requires it. No UIKit/AppKit except where SwiftUI lacks the capability, wrapped in a small representable.
- **SwiftData** models are CloudKit-compatible from day one: no `@Attribute(.unique)`, all relationships optional, every attribute optional or defaulted, no ordered relationships, additive changes only. Enforce logical uniqueness in upsert code, with tests.
- Every persisted model conforms to `Classified` and has a `dataClass`. Every derivation computes its class with the taint rule (`DataClass.max`).
- Deployment targets iOS/iPadOS/macOS 26. Gate OS 27 APIs with `if #available(iOS 27, macOS 27, *)` and provide a 26 path.
- async/await and actors; no completion-handler APIs in new code; no `DispatchQueue` except to bridge old APIs.
- Errors are typed enums per package; never swallow errors. Every external integration has timeout, retry with backoff and a visible error state.
- British/Irish English in UI strings and docs ("organiser", "colour", "licence" as noun). All user-facing strings go in String Catalogs; no concatenated sentences.
- Accessibility is part of done: VoiceOver labels (including boundary/locality badges), Dynamic Type, 44 pt targets, button equivalents for swipes.
- Logging only through `EagarLog` with `LogSafe` values. `print` is forbidden outside tests.
- Keep files focused; prefer value types; document public APIs with `///`.

### Dependencies

No third-party dependency without Mark's approval and a DECISIONS.md entry. Current allow-list (pin exact versions; commit `Package.resolved`; check recent commit activity before adopting):

| Package | Use |
|---|---|
| GoogleSignIn-iOS (or AppAuth-iOS if multi-client needs it) | Google OAuth with PKCE |
| MSAL (Microsoft) | Microsoft Graph auth |
| MailCore2 | iCloud / generic IMAP and SMTP |

Everything else is in-house: REST clients (Claude, Gmail, Graph, YouTube, Podcast Index), RSS/Atom/OPML/iCalendar parsing, JSON Schema validation subset, edit distance, MCP JSON-RPC. The push server may use one APNs client library, chosen and approved in M5.

## NON-NEGOTIABLE invariants

Breaking any of these is a release blocker. Each has tests in the boundary/invariant register (PRD §10.1). If a task seems to require breaking one, stop and ask Mark.

1. **College data boundary.** Data of class `college` (NCAD mail, NCAD calendar, Canvas, cdbooking, and anything derived from them) is processed only on Mark's devices by Apple's on-device model or the Mac's local model. It never reaches Claude or any cloud AI, Apple Private Cloud Compute, CloudKit/iCloud (sync or backup), push payloads, the push server, Spotlight/App Intents donations, notification or widget content (counts only by default), logs or diagnostics, or cloud-backed MCP clients (free/busy and counts only). The DGX Sparks/Meitheal are **not** local devices until Mark says so (`meithealIsLocal = false`).
   - College records live only in `CollegeStore`, which has no sync engine and is excluded from backup.
   - The only declassification path is Mark's per-line approval of About-me profile lines (BD-10, OD-4). Approved lines **are** sent to Claude as context, including lines learned from NCAD mail; the `workDerived` tag is provenance, not a filter. Unapproved, rejected or lint-failed lines never leave the Mac, and no raw college text ever accompanies the profile.
2. **Single AI gateway.** Every model call goes through `AIRouter`; providers accept only `RoutedCall`. Never call a provider, `URLSession` to a model host, or `FoundationModels` from feature code.
3. **Rules-only sources make zero model calls** of any kind.
4. **Approve-before-send is absolute** (OD-5, BD-11). The only send API takes an `ApprovalRecord` whose hash matches the exact outgoing MIME. Every message needs its own approval with device-owner authentication. New accounts start in dry-run. No App Intent, Shortcut, MCP tool, rule, playbook, suggestion, timer or autonomy grant may send without that per-message approval; L3 is only a fast-path approval plus a held send with undo (BD-12), and never applies to college accounts. Sending is never a whitelistable proactive action.
5. **Privacy ledger for every off-device call.** Write the ledger entry (with the exact payload for non-college data) **before** the request; if the write fails, do not send. Ledger blocked attempts, purges, MCP calls, push registrations and key tests.
6. **Secrets only in the Keychain**, `WhenUnlockedThisDeviceOnly`, non-synchronizable: the Claude BYOK key, OAuth tokens, app-specific passwords, feed tokens (cdbooking, Canvas feed URL), hub keys. Never in SwiftData, UserDefaults, files, logs, exports, test fixtures or source. No App Attest for BYOK.
7. **Never log secrets or content.** No message bodies, subjects, addresses, names, transcripts or profile text in logs, crash reports, analytics (there are none) or test snapshots.
8. **No YouTube downloading.** No download, offline cache, background playback, audio extraction, ad blocking, player overlays, or fetching captions of others' videos. YouTube metadata expires after 30 days; disconnect deletes YouTube data. Links open the YouTube app. Never put "YouTube" or "YT" in the app name.
9. **No workarounds to admin controls.** `admin_policy_enforced` is a correct outcome; show the IT request path. Never forward mail between accounts, never use Apps Script, scraping or relays.
10. **No developer server touches mail or tokens.** The push server stores only feed URLs, ETags, last GUIDs, device tokens and webhook route IDs.
11. **Learning pipeline purges its source copies** after each run and never modifies or deletes mail on the server. Profile lines must pass the non-identifying lint and Mark's per-line approval before they can be declassified. Profiles are per-user; never pool data across users.
12. **No Message Batches API for personal or college content.**

### Review checklist for any change touching data

- What data class does this read, create or emit? Is the taint rule applied?
- Which egress paths does it touch (AI, CloudKit, push, notification, widget, Spotlight, log, MCP, export)? Is each one allowed for that class (PRD BD-04 and the §7.4 policy table)?
- Is there a test that would fail if a college record leaked through this path?

## Testing expectations

- Unit tests for all package logic; table-driven tests for `PolicyEngine`, rules and guards; property-based tests (in-house generator) for the router and send invariants.
- Boundary tests use `RecordingProvider` and spies on CloudKit, push, notifications, Spotlight donations and logs. Name them `Boundary_B<n>_<description>` and `SendInvariant_S<n>_<description>` to match PRD §10.1.
- Use `EagarTestSupport` fakes (mock Gmail/Graph/IMAP, mock cdbooking server per PRD Appendix E, stub YouTube API, fixed clock). No test hits the network or uses real accounts; live checks are manual scripts that Mark runs.
- Fixtures are synthetic. Never commit real mail, names, addresses, tokens or keys.
- Coverage: ≥80% lines for `EagarAI`, `EagarRules`, `EagarCompose`, `EagarLedger`, `EagarLearning`; ≥60% elsewhere.
- A feature is done when: acceptance criteria pass, tests are green in CI, VoiceOver labels exist, strings are in the catalog, and DECISIONS.md is updated if anything was decided.

## Ambiguity and decisions

- If the PRD is ambiguous, conflicts with itself, or a requirement looks unsafe: **stop and ask Mark** with a concrete proposal and the trade-off. Do not guess on anything touching the data boundary, sending, secrets, or external policies (Google, YouTube, App Review).
- For small, reversible choices within a milestone, choose the simplest option consistent with the PRD, and record it in `docs/DECISIONS.md`:
  ```
  ## D-0xx  <title>  (YYYY-MM-DD, Mn)
  Context: …  Decision: …  Alternatives: …  Consequences: …  Refs: BD-xx, FR-xx
  ```
- Changing a binding decision (BD-xx) requires Mark's explicit approval and a DECISIONS.md entry referencing the BD. Owner decisions (OD-xx) are Mark's alone; never propose working around one.
- Facts marked "to verify" in the PRD are not to be assumed true; implement behind a check or setting, and record the verification result when known.
- Model IDs and prices come from `models.json` (in `EagarAI`), not code. Seed values, checked against the Claude models overview and pricing pages on 25 Oct 2026: `claude-haiku-5-5` $0.10/$0.50 per MTok (prompts ≤100K tokens; $0.50/$2.50 above), `claude-sonnet-5-5` $2/$10, `claude-opus-5-5` $4/$20. Do not invent model IDs; check the Claude models overview if a change is needed.

## Commits and branches

- Branch per milestone task: `m<n>/<short-topic>` (e.g. `m0/policy-engine`). Merge to `main` only with CI green.
- Conventional Commits with FR/BD references:
  ```
  feat(ai): add PolicyEngine table and router dispatch (FR-AI-01, FR-AI-02, BD-06)
  test(boundary): B-2 taint rule for mixed payloads
  fix(mail): handle invalid_grant with re-consent card (FR-EMAIL-05)
  docs(decisions): D-004 choose CKSyncEngine zone layout
  ```
- One logical change per commit; tests in the same commit as the code they cover.
- Never commit secrets, real data, `.p8` keys, `.env` files or `GoogleService-Info.plist` with real values. `.gitignore` covers them; CI scans for secret patterns.
- Tag milestone completion `m0`, `m1`, … after Mark signs off.
- Do not push or open PRs unless Mark asks.
