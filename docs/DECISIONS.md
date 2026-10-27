# Decisions

Current milestone: M2 (in progress, on `m2/feeds`; M1 device checks still open, see D-022)

ADR-style log of decisions made during the build. Append only; never rewrite history. Format:

```text
## D-0xx  <title>  (YYYY-MM-DD, Mn)
Context: …  Decision: …  Alternatives: …  Consequences: …  Refs: BD-xx, FR-xx
```

## Owner decisions (authoritative)

| ID | Decision |
|---|---|
| OD-1 | One multiplatform SwiftUI app for iPhone, iPad and Mac. The Claude API with Mark's own key is the first cloud tier; DGX Spark / Meitheal routing comes later. |
| OD-2 | College data (NCAD Google Workspace mail, the NCAD calendar, Canvas, cdbooking) is processed only on Mark's local devices (the 48 GB Mac's local AI and Apple's on-device model) and is never sent to any cloud AI. Mark has authority for this, limited to himself only. |
| OD-3 | Personal accounts may use the Claude API, with the consent that App Store guideline 5.1.2(i) requires. |
| OD-4 | Local learning pipeline: download mail → analyse Mark's own output with local AI → delete the source copies → keep a non-identifying style/workflow profile about him → Mark reviews and approves it → the approved profile **is** sent to the cloud AI as generic information about his workflow and how he writes and responds. This explicitly includes profile lines learned from his NCAD mail. Per-line review and approval, and the non-identifying requirement, remain mandatory. |
| OD-5 | Approve-before-send is absolute. No YouTube downloading. |
| OD-6 | Google Calendar via EventKit; Canvas via its iCal feed early; the Canvas API optional later. |

## Binding design decisions

| ID | Title |
|---|---|
| BD-01 | One multiplatform SwiftUI codebase; minimum OS 26, OS 27 features availability-gated |
| BD-02 | Local-first storage in two physically separate stores; CloudKit private database for personal data only |
| BD-03 | Every record carries a data class; derived items inherit the most restrictive class |
| BD-04 | The college boundary covers every egress path, not just AI |
| BD-05 | Per-source processing modes and per-class tier pins |
| BD-06 | One AI gateway: `LLMProvider` protocol plus a router that is the only way to reach a provider |
| BD-07 | Claude via a thin in-house REST client with Mark's own key (BYOK) |
| BD-08 | Local AI: Apple on-device on every device; Ollama on the Mac as the primary local runtime; MLX optional |
| BD-09 | The Mac is the hub for college data; iPhone/iPad reach it directly over the local network or Tailscale |
| BD-10 | Local learning pipeline: download → strip → analyse → aggregate → purge → review |
| BD-11 | Approve-before-send is absolute |
| BD-12 | Graded autonomy per category, earned from evidence, never above L2 on college accounts |
| BD-13 | Email access routes and Google OAuth clients per account |
| BD-14 | Calendar through EventKit; Canvas through its iCal feed first |
| BD-15 | cdbooking integration through a versioned per-user feed and content-free webhook contract |
| BD-16 | A tiny push server that never holds college content |
| BD-17 | YouTube: list and organise, never download |
| BD-18 | Podcasts: RSS is the source of truth |
| BD-19 | Privacy ledger of every off-device call |
| BD-20 | Contextual, per-source, per-feature consent (App Review 5.1.2(i)) |
| BD-21 | Calm proactivity: one brief at breakpoints, a confidence ladder, "plans with you" |
| BD-22 | Shared rules and playbook format: JSON with a published JSON Schema |
| BD-23 | Licence: Mozilla Public License 2.0 |
| BD-24 | Minimal dependencies, from an allow-list |
| BD-25 | No third-party analytics; logs never contain secrets or content |
| BD-26 | Keep-in-touch data lives in Eagar |
| BD-27 | Trials and subscriptions without bank linking |
| BD-28 | MCP server on the Mac, with a per-client data boundary |
| BD-29 | Governance pack is evidence, not a gate |

Full text in PRD.md §6. Changing a BD requires Mark's approval and an entry below that references it.

## Log

## D-001  Project creation via XcodeGen  (2026-10-25, M0)
Context: PRD M0 requires the Xcode project to be created either by Mark in Xcode or by XcodeGen; Claude Code must not hand-write a `.pbxproj`.
Decision: Mark approved XcodeGen as a build-time tool (not a shipped dependency). `App/project.yml` is the committed source; `App/Eagar.xcodeproj` is generated with `xcodegen generate --spec App/project.yml` and is git-ignored. CI installs XcodeGen and generates the project before building.
Alternatives: Mark creates the project once in Xcode and Claude Code edits it; rejected because pbxproj edits are hard to review and error-prone.
Consequences: Developers run `xcodegen generate` after pulling changes to `project.yml`. XcodeGen is not on the BD-24 allow-list because it is not linked into the app; Homebrew installs it.
Refs: PRD §10 M0, BD-24

## D-002  Package conventions and where test doubles live  (2026-10-25, M0)
Context: PRD §7.2 asks for local packages with Swift 6 mode; `RecordingProvider` is listed under `EagarTestSupport`, which depends on `EagarAI`.
Decision: Every package uses swift-tools-version 6.2, `platforms: [.iOS(.v26), .macOS(.v26)]`, `swiftLanguageModes: [.v6]`, `.treatAllWarnings(as: .error)` and Swift Testing. AI doubles (`RecordingProvider`, `InMemoryLedger`) live in an `EagarAITestSupport` library inside the EagarAI package; `EagarTestSupport` re-exports them and adds `FixedClock`, `StubAuthenticator`, `InMemorySecretStore`. `Tier` (the locality without region) lives in `EagarCore` because the ledger (layer 3) records it and the router (layer 4) routes on it. The clock protocol is `EagarClock`, not `Clock`, to avoid shadowing `Swift.Clock`.
Alternatives: `RecordingProvider` in `EagarTestSupport` — impossible, because EagarAI's tests depending on it would form a package cycle, which SwiftPM rejects.
Consequences: Test doubles ship in a library product of EagarAI; the app target never links it.
Refs: PRD §7.2, §7.4

## D-003  Router and policy refinements  (2026-10-25, M0)
Context: PRD §7.4 gives the policy table and router steps but leaves edge cases open. Items marked **[Mark to confirm]** touch the boundary.
Decision:
- A request's permitted tiers are the intersection over every classified piece (inputs, system prompt and output schema), so each piece's restrictions hold. The system prompt and output schema are classified and take part in the taint rule (a verify pass found the schema channel unclassified; fixed with a boundary test).
- A source missing from the policy snapshot is treated as `rulesOnly` (fail closed). A policy-source failure refuses the call.
- **[Mark to confirm]** A payload with no source (user-authored text) is bounded by its data class only (processing mode treated as `cloudAllowed`). Personal user-authored text still needs consent before Claude.
- Consent is keyed by (source, purpose, tier) and is required for personal data (raw and derived) to reach Claude; `approvedProfile` and `publicContent` need none, as in §7.4.
- Two extra settings, both default off: `meithealPersonalEnabled` (§13 I2) and `applePCCForRawPersonal` (§7.4 "if enabled").
- An explicitly requested tier that policy forbids is refused with `.boundaryViolation` and a `blocked` ledger entry; the router never silently substitutes another tier for a forbidden one. An *unreachable* preferred tier falls back to the next permitted tier (local first), unless the request sets `requiresPreferredTier` (the key test does).
- `ClassifiedPayload.kind` defaults to `.rawBody`, the more restrictive kind.
- BD-05 per-(class, kind) tier pins: the defaults are enforced by `PolicyEngine`; the Settings UI to narrow them further arrives with Settings in M1 (Parked).
Alternatives: Effective-class-only policy (would let a personal input without consent ride along with public inputs); rejected.
Consequences: B-1, B-2, B-5 and B-14 tests exercise these rules; the policy-table test checks all 1,920 cells against an independent oracle.
Refs: BD-03, BD-04, BD-05, BD-06, FR-AI-02..04, PRD §7.4

## D-004  Privacy ledger mechanics  (2026-10-25, M0)
Context: BD-19 and FR-PRIV-01..08 require the exact payload to be ledgered before an off-device request.
Decision: Providers expose `encodeRequest`, a pure function that produces the exact request bytes. The router ledgers those bytes, then builds the `RoutedCall` carrying them, and wire providers send them verbatim (retries reuse them). Payloads are kept only for calls that leave Mark's devices and carry no college data; on-device calls and anything college are metadata-only, and college entries live in CollegeStore. Costs are stored as integer millionths of a US dollar. A pending entry's completion is written once. Erasure needs device-owner authentication, is ledgered before anything is deleted, and never deletes earlier erase entries. A completion that fails to save leaves the entry visibly `pending` while the response is still returned (the call has already happened).
Alternatives: Ledger a canonical rendering of the request instead of the bytes; rejected because it is not "the exact payload".
Consequences: Known gap (low): code holding `EagarStores` could delete ledger rows through `ClassifiedStore.perform` without authentication. Hardening is Parked for M1.
Refs: BD-19, FR-PRIV-01..08, invariant 5

## D-005  Claude client details and price seeds  (2026-10-25, M0)
Context: BD-07 requires an in-house `/v1/messages` client. Model IDs and prices must come from `models.json`.
Decision: The client sends `anthropic-version: 2026-10-21` (the current API version per the Claude API reference; that version rejects sampling parameters, which Eagar never sends) and the `x-api-key` header, puts `cache_control` on the system prompt, and uses `output_config.format`/`effort`. It retries 429/5xx/network failures twice with back-off and a 60 s timeout. It sends no `fallbacks` parameter and has no Message Batches code (FR-AI-11). `models.json` seeds, from the Claude models overview and pricing reference on 2026-10-25: Haiku 5.5 $0.10/$0.50 (≤100K-token prompts; $0.50/$2.50 above), Sonnet 5.5 $2/$10 with cache reads $0.20, Opus 5.5 $4/$20 with cache reads $0.20, Fable 5.1 listed but not offered. **Discrepancy for Mark:** RESEARCH.md says Sonnet and Opus 5.5 cache hits cost 0.05×; the reference gives Sonnet 5.5 cache reads at $0.20/MTok (0.1×) and Opus 5.5 at $0.20 (0.05×). Haiku 5.5 cache prices are derived from the standard 0.1× read / 1.25× write multipliers and are marked "to verify" in the file.
Alternatives: `Authorization: Bearer` (what the new SDKs send); the raw-HTTP reference still documents `x-api-key`.
Consequences: Mark's live smoke test confirms the version header and Haiku `effort: low` against the real API.
Refs: BD-07, FR-AI-07..11

## D-006  Store hardening  (2026-10-25, M0)
Context: Parallel tests crashed (SIGSEGV, ~50% of runs) inside Core Data while loading several `ModelContainer`s for the same model types at once.
Decision: `EagarStores` creates containers one at a time, process-wide. The CollegeStore directory is excluded from backup, and every file in it is flagged explicitly after opening, because iOS does not report the directory's flag on its children (found by B-4 on the iOS simulator). A record whose stored class is unrecognised reads as `college`. Every save re-checks the class of inserted and changed models, and a throwing `perform` rolls back. `SyncRegistry` is the only gate a sync engine may use and refuses CollegeStore; the M1 `EagarSync` engine must register through it (until then B-4's sync half asserts the gate, not an engine).
Alternatives: Disable parallel tests; rejected, because the app may open stores from more than one task.
Consequences: Container creation is serialised; this is a one-off cost at launch.
Refs: BD-02, FR-CORE-02, B-3, B-4

## D-007  eagar-rules schema completions  (2026-10-25, M0)
Context: Appendix F.2 is an abridged sketch; F.6 is an example.
Decision: `guardSetting` and its extended guards are closed objects (`additionalProperties: false`), reusing `$defs/guardSettingFields`. `personalData.patterns` items require `name` and `regex`. Ledger export: `YYYY-MM-DD` period dates, `origin` and `providerLocality` enums, guard names limited to the eight guards, token patterns (no spaces, no `@`) for lane, category and edit classes, and `sendsWithoutApproval` as an integer ≥ 0 so a breach is visible. Date-times stay RFC 3339 strings in the Swift models so files round-trip exactly. Validation stops at nesting depth 96 and JSON parsing at depth 100 (a stack overflow was found and fixed). An L3 grant on a `localOnly` lane is an error (document refused on read and write); a grant above `policy.maxAutonomy` is a warning (grant ignored). Validation errors may quote document values, so `RulesError` is not `LogSafe`.
Alternatives: Keep the sketch's open objects; rejected because Appendix F says unknown properties are rejected.
Consequences: The Windows app should use the published schema files; questions for Mark are Parked.
Refs: BD-22, BD-24, Appendix F

## D-008  Localisation tooling  (2026-10-25, M0)
Context: NFR-L10N-01/02 need every string in String Catalogs and a `ga` scaffold. Command-line builds extract strings but do not update the catalog (only the Xcode IDE does).
Decision: The development language is `en-GB`. `Tools/sync-strings.py <DerivedData>` merges compiler-extracted strings into `App/Eagar/Localizable.xcstrings` and adds a `ga` pseudo-localisation (accented, bracketed, ~40% longer, format specifiers preserved) marked `needs_review`; `--check` fails if anything is missing. A UI test launches in Irish and checks a pseudo-localised label.
Alternatives: Hand-maintained catalog; rejected as error-prone.
Consequences: Run the script after adding UI strings (or open the project in Xcode). Real Irish translation is not a v1 deliverable.
Refs: NFR-L10N-01, NFR-L10N-02

## D-009  Toolchain, simulators and Keychain testing  (2026-10-25, M0)
Context: M0 acceptance asks to record which simulator runtime was used.
Decision: Built and tested with Xcode 27.1 (Swift 6.4, macOS 27 SDK) on macOS 26.6.2, deployment target 26.0, iOS 26.5 simulator runtime (iPhone 17, iPad Pro 13-inch (M5)). The macOS data-protection keychain needs a signed build with a team, so the real-Keychain attribute read-back runs on the iOS simulator; on macOS the attribute dictionaries are covered by `EagarSecurity` unit tests and Mark's signed build.
Alternatives: None practical without Mark's signing team.
Consequences: An unsigned macOS build cannot store the Claude key; Mark sets `DEVELOPMENT_TEAM` in `App/Config/Local.xcconfig`.
Refs: PRD §10 M0, invariant 6

## D-010  Corrections after checking live docs  (2026-10-25, M0)
Context: The live pricing page, authentication page and GitHub runner-image list were checked on 2026-10-25.
Decision:
- Corrects D-005: Sonnet 5.5 cache reads are **$0.10/MTok (0.05×)**, as RESEARCH.md said; `models.json` had $0.20. Haiku 5.5 cache prices ($0.01 read, $0.125 5-minute write; $0.05 and $0.625 above 100K-token prompts) are confirmed, so the "to verify" note is removed. Source: https://platform.claude.com/docs/en/about-claude/pricing
- The Claude client now sends `Authorization: Bearer <key>`; the authentication docs call `x-api-key` legacy (still supported). Source: https://platform.claude.com/docs/en/manage-claude/authentication
- CI runs on GitHub's `xcode-27` image (preview; Xcode 27.1 default, iPhone 17 on the iOS 27.0 runtime) pinned to Xcode 27.1. `macos-26` ships only Xcode 26.x. Resolves REVIEW_NOTES unresolved #3. Source: https://github.com/actions/runner-images
Alternatives: Keep `macos-26` and drop to Xcode 26.6; rejected, because the PRD needs the OS 27 SDK.
Consequences: CI's iOS tests run on the iOS 27.0 simulator runtime (deployment target stays 26.0); local runs use 26.5.
Refs: D-005, D-009, BD-07

## D-011  Signing, bundle ID and the macOS Keychain  (2026-10-25, M0)
Context: On a team-signed Mac build the Keychain returned -34018 (missing entitlement): the macOS data-protection keychain needs an application identifier, which only a provisioning profile supplies. Separately, a team-signed Debug test build crashed at launch because hardened runtime rejected the separately signed local-package frameworks Xcode links in test builds.
Decision: Bundle prefix `com.fiavaion` (Mark, 2026-10-25), so the App ID is `com.fiavaion.eagar`. Team-signed builds use `EagarSigned.entitlements`, which adds Keychain Sharing (`keychain-access-groups` = `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`) and makes Xcode create a Mac development profile. `App/Config/Local.xcconfig` (git-ignored) sets `DEVELOPMENT_TEAM` and `EAGAR_ENTITLEMENTS`; unsigned and CI builds keep the plain `Eagar.entitlements`. Hardened runtime is on for Release only. Mark's MacBook Pro was registered to team 9RWD38STJV with his approval. The real-Keychain attribute test now also runs on macOS whenever the entitlement is present.
Alternatives: The legacy file-based macOS keychain needs no entitlement, but it does not honour `WhenUnlockedThisDeviceOnly` (invariant 6); rejected.
Consequences: Each new Mac or device used for development must be registered to the team. Release builds keep hardened runtime for notarisation.
Refs: D-009, invariant 6, BD-07

## D-012  M0 live smoke test passed  (2026-10-25, M0)
Context: M0 acceptance requires a manual "test key" run with Mark's key.
Decision: Mark ran it on his team-signed Mac build with a key in a dedicated workspace. Result: "Key works with claude-haiku-5-5", cost US$0.000004. The ledger entry (kind `keyTest`, tier `anthropicCloud`, destination `anthropic`, region `global`, outcome `succeeded`, 18 input / 4 output tokens, 4 µ$, 1.19 s, class `publicContent`) holds the exact payload, including the fixed prompt, and no key or `Authorization` header. This confirms `anthropic-version: 2026-10-21`, Bearer auth and `effort: low` on Haiku 5.5 against the live API (D-005, D-010).
Alternatives: None.
Consequences: All M0 acceptance criteria are met except CI green on GitHub, which needs a push.
Refs: PRD §10 M0, FR-AI-07, FR-PRIV-01, FR-PRIV-04

## D-013  Owner answers: typed text and three eagar-rules rules  (2026-10-25, M0)
Context: D-003 left the routing of source-less (user-typed) text for Mark to confirm; D-007 listed three open rules-format questions.
Decision: Mark confirmed (2026-10-25):
- User-typed text with no source is bounded by its data class only, as built in D-003 (personal text still needs consent before Claude; college-class text never leaves his devices).
- An L3 autonomy grant whose `laneId` is not defined in the same document is refused (semantic error, on decode and encode), because its boundary is unknown (BD-12).
- `action` is a `oneOf` split by `type`; each branch is closed and requires its own field (`adjustScore`→`amount`, `setLane`→`laneId`, `setThreadState`→`state`, `addLabel`→`label`, `suggestPlaybook`→`playbookId`, `notify`→`level`, `muteUntil`→`until`; `markRead` none). The Swift `Action` is now an enum, so Swift cannot build an action the schema rejects. The validator's closest-branch ranking prefers the branch whose `type` const matches, so errors stay specific.
- A lane with `boundary: localOnly` and `processingMode: cloudAllowed` is a semantic error.
Alternatives: Defer to M3; Mark chose to settle them now.
Consequences: The Windows app's validator must implement the same two semantic rules to stay in step. Five new invalid fixtures cover the changes.
Refs: D-003, D-007, BD-05, BD-12, BD-22, Appendix F

## D-014  CI green on GitHub; lint proven on a test branch  (2026-10-25, M0)
Context: The last M0 criteria: CI green on push, and CI lint rejecting a deliberately added `print(` and a hard-coded `sk-ant-` string in a test branch.
Decision: Public repo https://github.com/Fiavaion/eagar (Mark chose public; author identity is his GitHub no-reply address). CI run 40225611094 on `m0/foundations` passed every step on the `xcode-27` runner (lint, lint self-test, all package tests, the macOS and iOS test plans, the catalog check). Branch `ci/lint-check` with a `print(` and a fake `sk-ant-` string failed at the Lint step (run 40227051417, `[no-print]` and `[secrets]`); the branch was then deleted. Getting to green fixed: a duplicate `EagarAI` copy in the app test bundle, the macOS 27 `Tab` element type, the Passwords autofill pop-up taking the first click, and inactive-window clicks on the CI VM (the ledger UI test now opens its tab with `-EagarInitialTab`; tap navigation stays tested on iOS).
Alternatives: None.
Consequences: Every M0 acceptance criterion in PRD §10 is met; awaiting Mark's sign-off before tagging `m0`.
Refs: PRD §10 M0, D-010, D-012

## D-015  M0 signed off  (2026-10-25, M0)
Context: Every M0 acceptance criterion passed (D-012, D-014).
Decision: Mark signed off M0. `m0/foundations` was fast-forwarded into `main` and tagged `m0`. Current milestone: M1.
Alternatives: None.
Consequences: M1 work starts on `m1/<topic>` branches, after an M1 plan is agreed.
Refs: PRD §10 M0, CLAUDE.md "How to work"

## D-016  App ID com.fiavaion.eagarapp; iCloud container and App Group  (2026-10-25, M1)
Context: Registering `com.fiavaion.eagar` failed: Apple reports it is registered to a different developer team. The earlier Mac build had used a wildcard profile, which hid this.
Decision: Mark chose `com.fiavaion.eagarapp`. Created under team 9RWD38STJV with Mark's approval: App ID `com.fiavaion.eagarapp` with iCloud (CloudKit container `iCloud.com.fiavaion.eagarapp`) and App Group `group.com.fiavaion.eagarapp`; Mark's iPad Pro 12.9" (5th gen, iPadOS 27.0.1) registered. The entitlements are in `EagarSigned.entitlements` only, so unsigned CI builds carry none. Eagar was installed and launched on the iPad.
Alternatives: Use the other team, if it is Mark's; he chose the new ID.
Consequences: Supersedes the bundle ID in D-011. Extensions will be `com.fiavaion.eagarapp.<name>`. CloudKit stays in the development environment until M6.
Refs: D-011, BD-02, PRD §10 M1

## D-017  M1 calendar, deadline and brief rules  (2026-10-25, M1)
Context: Edge cases the PRD leaves open for M1.
Decision:
- **Calendars:** a calendar on an `ncad.ie` account (subdomains included) is proposed as college; a calendar Eagar has never seen is treated as college until tagged (fail closed). Retagging moves the `CalendarRef` between stores. College-derived content is never written into a non-college calendar; personal content may go into a college calendar.
- **Availability:** all-day events block time only when busy or unavailable; the window is half-open; every event end is a breakpoint, and the 15-minute rule creates a gap breakpoint only where no event end already marks it (BD-21 counts both). Busy blocks, event-end breakpoints and conflicts carry the taint of their events.
- **Deadlines:** offsets of 2 hours or less are `timeSensitive`, others `active`; whole-day offsets use calendar arithmetic so local time survives DST; all-day deadlines notify at 09:00 local. Snoozing schedules a reminder when the snooze ends. Notification sync re-adds every planned request, so edits replace stale ones. College notifications say "College deadline" and never include the title. College deadlines mirror only to local or college reminder lists, never iCloud, unless overridden per item.
- **Brief:** sections are overdue (always first), today, deadlines, then the later-milestone sections; all-day events lead "today". The brief notification and its body are counts only for every class; widgets show personal titles and a college count. AI phrasing sends a section's college items and its other items as separate requests, so personal lines can use Claude (`claudeForPersonal` mode, with consent) while college lines are phrased only locally. Phrasing failures leave the deterministic text. Brief-level event-log entries take the brief's most restrictive class.
Alternatives: Phrase whole sections, which would force any mixed section to local only; rejected.
Consequences: B-6 and the counts-only egress test cover these paths.
Refs: FR-CAL-02..04, FR-DL-02/03, FR-BRIEF-01..08, BD-04, BD-21

## D-018  Sync and kill-switch rules after review  (2026-10-25, M1)
Context: A fresh-context review of EagarSync and the kill switch found no boundary breach but 5 high and 7 medium issues, each confirmed by a probe test. All are fixed, with regression tests.
Decision:
- **Kill switch:** each provider call races the kill switch through a one-shot continuation, so a halt returns within the 50 ms response budget even when a provider ignores cancellation; late answers are discarded. Caller cancellation is reported as `.cancelled`, not as a halt.
- **Sync decoding:** adapters declare every field's kind; a missing list equals an empty list (CloudKit may return either), so nothing re-uploads forever.
- **Sync merging:** read, merge and write of a fetched record happen in one store operation. A fetched record with no history (after an account change or lost state) is merged, not taken over, so unsynced local edits survive. "Later edit wins" compares when this device first saw the local edit against the server's modification time (models carry no per-field edit stamps yet). Lists merge last-writer-wins; set-union for tags and queue membership (§7.5) arrives with the first such field.
- **Deletions:** a local deletion is kept as a tombstone until the server confirms it; an older server edit does not resurrect the record.
- **Failures:** a fetched change that fails to apply is queued and retried on the next scan. Every CloudKit save and delete failure ends in a retry or a logged decision (unknown item, missing zone and encrypted-key reset clear the change tag and re-upload; zone deletion re-uploads everything). Pending saves with nothing to send are dropped from the engine queue.
- **State file:** a missing file is a fresh start, an unreadable one stops sync, and a corrupt one is moved aside, never overwritten.
- **Account change [Mark to confirm]:** on iCloud sign-out or account switch, local data is kept, bookkeeping is cleared and sync pauses until Mark confirms the account in Settings. Personal data is never uploaded to a different Apple ID automatically. (Apple's sample deletes local data instead.)
- **Not synced:** `CalendarRef` (EventKit identifiers differ between devices) and reminder-mirror IDs.
- **Not yet wired:** neither the kill switch nor `PersonalSyncEngine` is connected to the app at this point; the M1 criteria for them are not claimed until they are.
Alternatives: Delete local data on account switch (Apple's sample); rejected pending Mark's decision.
Consequences: `PersonalSyncEngine` itself has no unit tests (CKSyncEngine events can't be constructed); it is verified by the two-device test in M1 acceptance.
Refs: BD-02, PRD §7.5, FR-CORE-07, D-006

## D-019  AI brief phrasing: faithfulness check, default off  (2026-10-25, M1)
Context: In app testing the on-device model invented details: an all-day "Bin collection" became "on Saturday, 21st May, at 10:00 am", and "Submission week" became "from 11th to 17th November".
Decision: Phrasing defaults to off; Mark can turn on "local only" or "Claude for personal" in Settings. Every phrased sentence must pass a faithfulness check: each number, weekday and month name it mentions must appear in the input lines, otherwise it is discarded and the deterministic brief is shown. The prompt forbids adding dates, days, times, places or people, and all-day items are given to the model as "All day: …". The check does not catch every invention (for example an invented place), which is why the default is off.
Also in M1's app: a college deadline's iCloud Reminders override needs a confirmation; calendar edits made while Eagar is open refresh the view at once; the app integration's UI choices (six tabs; brief and timeline use only calendars included in the brief, while breakpoints use all; snoozed deadlines stay out of the brief until the snooze ends; brief notifications are scheduled only once notifications are allowed; phrasing reruns only when the brief changes) are as reported in the app commit.
Alternatives: Keep local phrasing on by default with the check; rejected while the check cannot catch every invention.
Consequences: The deterministic brief is what Mark sees by default.
Refs: FR-BRIEF-04, FR-DL-03, FR-CAL-05

## D-020  M1 wiring: kill switch, sync, widgets, Shortcuts  (2026-10-25, M1)
Context: Connecting the M1 packages to the app.
Decision:
- **Kill switch:** shared state in the App Group (`KillSwitchState`). The Control Centre control and the "Stop Eagar AI" Shortcut set it (one `SetKillSwitchIntent`, compiled into the app and the widget extension); Settings has a toggle. While the app runs it checks the state every 0.5 s and halts or resumes the router, so a change made in Control Centre stops AI within 1 s.
- **Sync:** compiled in only when `EAGAR_CLOUDKIT` is set (Mark's `Local.xcconfig`), because creating a CloudKit container without the iCloud entitlement crashes and CI builds are unsigned. Only `Deadline` syncs in M1. It syncs on app activation and after deadline changes. After an iCloud account change, Settings offers "Sync with this iCloud account" (D-018).
- **Widgets:** `EagarWidgets` extension (Brief, Next deadline, kill-switch control), App ID `com.fiavaion.eagarapp.widgets` with the App Group. The app publishes a `WidgetSnapshot` (personal titles, college count) after each brief composition and reloads timelines. The widget never sees college titles. Unsigned builds have no App Group, so widgets show placeholders.
- **Shortcuts (FR-OS-03):** "Add a deadline" (always personal) and "Show my brief", plus "Stop Eagar AI". The app donates "Add a deadline" only for personal deadlines; college items are never donated (B-7).
- **Signing:** `Local.xcconfig` sets `DEVELOPMENT_TEAM`, `EAGAR_ENTITLEMENTS`, `EAGAR_WIDGET_ENTITLEMENTS` and `EAGAR_CLOUDKIT`; CI uses the unsigned defaults in `Base.xcconfig`.
Alternatives: A Darwin notification from the extension instead of polling; polling is simpler and only runs while the app is open.
Consequences: The two-device sync test and the Control Centre toggle need Mark's signed builds.
Refs: FR-CORE-07, FR-OS-01..03, FR-BRIEF-06, BD-02, B-7, D-016, D-018

## D-021  M1 review fixes and the behaviour they settle  (2026-10-25, M1)
Context: A fresh-context review of all M1 code found no blocker but 5 high and 12 medium issues (each high one confirmed by a probe). All are fixed with tests.
Decision:
- **Calendars fail closed:** an event counts as personal only once Mark has **confirmed** its calendar as personal. Unconfirmed proposals and unknown calendars are college, so a Canvas or NCAD feed under any other account never shows or travels as personal. Calendar titles naming ncad.ie are also proposed as college. (Tightens D-017.)
- **Intent donations:** the planner never asks to donate a college deadline; the B-7 spy now records every call, so the test fails if it does. Moving a deadline to college withdraws "Add a deadline" donations (they can't be withdrawn one by one).
- **Writing Tools** are off on college deadline titles and on event fields for college calendars (BD-04).
- **Class change** copies every field into the new store first, then deletes the old record; a failure rolls back and is shown.
- **Brief delivery:** if Mark is free at the slot time with 15+ minutes to spare, the brief comes at the slot time. A slot delivered by opening the app is remembered for the day and not notified again. Granting notification permission schedules the brief.
- **Reminders mirroring:** rescheduling updates the mirrored reminder; marking done removes it; snoozing leaves it. A failed removal is shown and retried on every refresh.
- **Notification actions (FR-OS-05):** Done marks the deadline done; Snooze snoozes for 1 hour (it does not move the due date). Categories are registered once at launch for all notification kinds.
- **Controls (FR-OS-02):** "Start brief" opens Today; the kill-switch control is reloaded after an in-app or Shortcut change.
- **FR-CAL-04:** a "New event" sheet writes through `CalendarWriter` to a chosen modifiable calendar; manually typed events derive from nothing.
- **FR-CORE-06:** each calendar shows class, processing mode and a boundary icon (house: "Stays on your devices · Local AI only"; cloud: "Cloud AI with your consent").
- **"Claude for personal items" phrasing** is hidden until consent screens exist (Parked).
- **The widget's next deadline** is the earliest open, unsnoozed future deadline across all deadlines.
- **CI:** the iOS job boots the simulator first and retries failed tests once (the UI-test runner crashed while bootstrapping on a cold simulator).
Alternatives: Marking a mirrored reminder complete on done; the event-store adapter has no completion call yet.
Consequences: First-run tag confirmation matters: until Mark confirms "personal", those calendars' events appear as college counts.
Refs: D-017, D-019, D-020, FR-CAL-04, FR-CORE-06, FR-OS-02, FR-OS-05, FR-BRIEF-02/08, FR-DL-03, BD-04, B-7

## D-022  Start M2 before the M1 device checks  (2026-10-26, M2)
Context: M1 is built, reviewed twice and green in CI, but the device checks (calendar tag confirmation, the two-device sync test, the Control Centre kill switch, VoiceOver, V1, V3, the TestFlight record and the D-018 default) need Mark at the devices. Mark asked for as much work as possible overnight.
Decision: Mark chose to go ahead. `checkpoint/pre-m2` tags the M1 head (`eaa94ec`, pushed). M2 is built on `m2/feeds`, branched from `m1/calendar-brief`, and pushed for CI. M1 is not merged or tagged until Mark signs it off; any device-check failure is fixed on the branch, or M2 is reverted to the checkpoint if it can't be fixed.
Alternatives: Waiting for the device checks (loses a night); merging M1 to `main` first (puts unsigned work on `main`).
Consequences: The M1 device checks stay open (see the M1 list in the morning report). M2 decisions that touch college data, secrets or AI routing are marked "for Mark to confirm".
Refs: CLAUDE.md "One milestone at a time", D-018, D-021

## D-023  Trial screenshot extraction stays on the device  (2026-10-26, M2)
Context: FR-TRIAL-03 reads a trial from a screenshot or shared text. A receipt screenshot is personal, but it can show an account name or a card ending, and the task could be sent to Claude or Apple's Private Cloud Compute where policy allows personal data.
Decision: **For Mark to confirm.** OCR is Apple Vision on the device. The only model call goes through `AIRouter` (purpose `extraction`, one personal `rawBody` payload) with `requiresPreferredTier`, so the router uses the on-device model only and never falls back to the Mac, PCC or Claude, even where personal data would be allowed there. If the model is halted, unavailable or answers badly, the deterministic receipt parser supplies the draft. Model output is kept only where it is grounded in the recognised text (price digits present, date also found by the parser, service named, known currency code); invented values are dropped. The in-app import passes no `SourceID`: a screenshot is not a configured source, so it is attributed to nothing for policy and the ledger. `TrialScreenshotImporter` has a `.parserOnly` mode that makes zero model calls whatever router it is given. Nothing is stored until Mark confirms the proposal.
Alternatives: Let personal screenshots use Claude with consent (better accuracy; rejected, the content is incidental and the on-device path scores 12/12 on the fixtures with the parser alone); give imports a registered source ID (nothing to register yet).
Consequences: Boundary tests assert that only the on-device provider is ever called with cloud consented and PCC and Meitheal enabled, that there is no tier fallback, and that nothing is logged. The M2 receipt-import criterion (8 of 10) is met by the parser fallback on 12 synthetic fixtures rendered by a committed CoreText script.
Refs: FR-TRIAL-03, BD-05, BD-06, invariant 2

## D-024  Share extension is parser-only; pending imports hand over through the App Group  (2026-10-26, M2)
Context: `EagarShare` (iOS and macOS) receives a screenshot or text from the share sheet. An extension is short-lived and cannot show the full confirmation flow.
Decision: **For Mark to confirm.** The extension has no router, so it makes no model call of any kind; it runs Vision and the parser only. The proposal is written as one JSON file per `PendingTrialImport` (atomic, file protection until first unlock) in `PendingTrialImports/` of the App Group container. The app picks up the oldest one when it becomes active, shows it in the confirmation sheet and deletes the file on confirm or discard; unreadable files are skipped and removed so one corrupt hand-over never blocks the rest. Nothing becomes a `Trial` until Mark confirms. Unsigned builds have no App Group, so the extension reports "no container" and tells Mark to add the trial in Eagar; they use `EagarShare.entitlements` through `EAGAR_SHARE_ENTITLEMENTS`, and signed builds use `EagarShareSigned.entitlements` (same pattern as D-020).
Alternatives: Run the on-device model in the extension (memory limits and a second router); a URL scheme hand-over (puts content in a URL).
Consequences: Share-sheet proposals can be less complete than in-app ones; the confirmation sheet fills the gaps. The App Group hand-over needs Mark's signed build to test.
Refs: FR-TRIAL-03, invariant 3 (no model call), D-016, D-020

## D-025  Trial receipt parsing: prices, dates, defaults  (2026-10-26, M2)
Context: The PRD fixes the fields but not how a receipt is read or what a missing field becomes.
Decision: Prices are read with `€ £ $ US$ C$ A$` or `EUR GBP USD`, before or after the amount, with comma or point decimals; the last separator followed by one or two digits is the decimal mark. The charge is the best-scoring line: totals and per-period wording score up; VAT, tax, subtotals, discounts and zero amounts (a free trial's "£0.00") score down. Dates read as `3 Dec 2026`, `December 3, 2026`, `2026-12-03`, `03/12/2026` and `03.12.2026`; ambiguous numeric dates read day first (Irish usage), except with dollars, where they read month first, and dotted dates are always day first. Renewal, trial-end and billing wording scores up and purchase, order and invoice dates down; ties go to the later date. The service comes from a built-in merchant list (names only, no cancel URLs, which change too often; generic words such as "Apple" are excluded) or the first plausible header line. A confirmed draft needs a service and a renewal date; price defaults to 0, currency to EUR and period to monthly. Imported and manual trials are personal. `Trial.price` is a `Decimal`, and the sync adapter sends it as a locale-independent decimal string ("9.99") because CloudKit has no decimal type and a locale-formatted value would not round-trip.
Alternatives: Day-first only (wrong for dollar receipts); `Double` prices (rounding errors in totals).
Consequences: A model answer that disagrees with the parser on a date is dropped, not shown. Per-service cancel URLs are left to Mark, with Apple's subscriptions page as the fallback.
Refs: FR-TRIAL-01, FR-TRIAL-03

## D-026  Trial reminders have their own plan; cancel-by and the monthly total  (2026-10-26, M2)
Context: Cancel-by dates also appear among deadlines (FR-DL-01), whose M1 plan would notify a second time.
Decision: Trials notify only through `TrialReminderPlan`: identifiers `trial.<uuid>.<days>`, default days 7, 3, 1 and 0 before cancel-by (per trial, so configurable), fired at 09:00 local time because renewals are usually dates, not instants. Only the day itself (0) is time-sensitive (BD-21); earlier ones are active. Reminders roll on to the next renewal once a trial's cancel-by passes while it is still active. `TrialReminderSync` removes stale `trial.` requests and re-adds every planned one, leaving other prefixes alone. The notification's user info carries only the trial UUID and the cancel page, never the service name. Cancel-by is the renewal minus a safety margin (default 2 days) in calendar days, so local time survives DST and month ends clamp. Renewals are computed from the original date each time, so a monthly charge on the 31st does not drift. The cancel-by deadline (origin `trial`, same UUID as the trial) is shown in Deadlines and the brief but never stored, and carries no reminder offsets. Cancel opens the service's `http(s)` cancel link with a host, else Apple's subscriptions page (other schemes are ignored); the status becomes `cancelled` only when Mark confirms he cancelled, never on opening the page. The monthly summary appears in the brief on the 1st, counts active items only, totals per currency (no exchange rates) with yearly plans as a twelfth and weekly as 52/12, rounds to cents, and takes the taint of the trials it includes.
Alternatives: Reuse the deadline plan (double notifications); store a deadline per trial (two sources of truth).
Consequences: A college-class trial, which the app never creates, would get content-free reminders as college deadlines do (BD-04).
Refs: FR-TRIAL-01, 02, 05, 06, FR-DL-01, BD-21, BD-04, D-021

## D-027  Keep-in-touch: college-tainted interaction dates are never persisted  (2026-10-26, M2)
Context: "Last contact" can be inferred from calendar attendees (and, from M3, mail). `Person` syncs through CloudKit, but a signal from an NCAD calendar or work-lane mail is college data.
Decision: **For Mark to confirm.** `InteractionInference` returns two answers. `personalLatest` uses personal signals only and is the only value ever written to `Person.lastInteractionAt` (so the only one that can reach CloudKit). `effectiveLatest` also counts college signals, but only for a person whose work-signal opt-in is on (off by default); it exists in memory only and is recomputed on launch, activation and calendar changes. Its class is the taint of every counted signal, so it is college as soon as one college signal is counted, even if a personal date was the later one. Events count once they have ended; future-dated signals are ignored; an older date never moves `lastInteractionAt` backwards. Attendee email addresses sit on `CalendarEvent.attendeeEmails`, lower-cased, held in memory and never logged or persisted. A manual "we talked" log is always personal and may move the stored date. The People screen badges a last contact that came from a college signal.
Alternatives: Persist the effective date with its class (it would sit in a synced record); never use college signals (loses real information for people Mark sees through work).
Consequences: After a restart the effective date is rebuilt from the calendar, so it is empty until events load. Boundary and property tests cover the taint rule (FR-CORE-03).
Refs: FR-PEOPLE-03, BD-26, BD-03, FR-CORE-03

## D-028  Nudge planner rules; a nudge's class follows its slot  (2026-10-26, M2)
Context: FR-PEOPLE-04 and 05 leave the planning rules open.
Decision: **For Mark to confirm.** The planner proposes at most `weeklyBudget` (default 3) minus what is already committed, where committed means contact logs this week plus catch-ups Mark planned from nudges that have not started yet (kept locally as an opaque person ID and a time). Each nudge sits inside one free slot of at least 60 minutes, clipped to social hours 09:00 to 22:00 and to the rest of the week; at most one per day and never two in a slot; weekday preferences and snoozes are respected. A person's nudge falls in the last 25% of their cadence (day 22 to 30 for 30 days); overdue people and people with no known contact may go anywhere in the week. Order: most overdue first, then earliest due, then unknown contacts shuffled; within the rules the slot is random, from a SplitMix64 generator seeded with the week, so proposals stay put while nothing changes. Free slots come from the same availability engine as the brief, so busy time includes college events. The nudge's class is the taint of the person, the slot and the inferred interaction: one placed after a college event, or timed from a college signal, is college, shown in the app only, counted only in notifications and widgets, and kept away from cloud phrasing (B-6). Its "plan" action may only write a catch-up into a college calendar. Brief phrasing is built from catalog entries ("Thursday evening is free; Aoife: 7 weeks"). Cadence defaults to 30 days and is limited to 1 to 730.
Alternatives: Treat every nudge as personal (leaks the shape of college days); a fixed schedule (predictable and ignores free time).
Consequences: Defaults (budget, hours, 25% window) are tunables, to be reviewed during the pilot.
Refs: FR-PEOPLE-04, FR-PEOPLE-05, BD-26, BD-04, FR-CORE-03, B-6

## D-029  People data: limited contact access, matching and encrypted fields  (2026-10-26, M2)
Context: People are personal records that sync, and they identify real individuals. Birthdays also need reminders.
Decision: **For Mark to confirm.** Eagar sees only the contacts Mark chooses: the iOS limited-access picker with `ContactAccessButton`, and `CNContactPicker` on macOS. Only identifier, name, email addresses and birthday are read; `CNContactNoteKey` is never fetched, and `ContactImport` has no notes field. Matching on import is by contact identifier, then by any shared email address (identifiers can differ between devices); the oldest match wins, an update merges addresses and refreshes the birthday only when the import has one, and cadence, weekdays and relationship notes are never touched. The notes in Mark's own words, and everything that identifies the person (name, contact identifier, email addresses, birthday), travel only in CloudKit `encryptedValues`; cadence, weekdays, snooze and opt-in are plain. A contact log's free-text note is also encrypted and left out of the value copy. Birthday reminders are local notifications, identifier `birthday.<uuid>.<year>`, one per person for the next birthday at 09:00 local time, reconciled on launch and after changes; 29 February falls on 28 February in common years, and with no birth year the text leaves the age out.
Alternatives: Full Contacts access (more than needed); plain CloudKit fields (names readable by anyone with database access).
Consequences: Person, ContactLog and Trial join the shared schema and the PersonalStore coordinator under `EAGAR_CLOUDKIT`, as `Deadline` does (D-020). Encrypted field names are declared in the adapters.
Refs: FR-PEOPLE-01, 02, 06, BD-02, BD-26

## D-030  Feed sources: class by kind, defaults and the Canvas host guess  (2026-10-26, M2)
Context: FR-CORE-04 says sources on the college domain list default to college. Canvas's host for NCAD is unknown.
Decision: **For Mark to confirm.** A cdbooking or Canvas source is college by kind, whatever its host and whatever class the caller passes (`FeedSource` forces it); a generic iCalendar feed is college only when its host is `ncad.ie`, `cdbooking.com`, the Canvas host or a subdomain. `FeedCollegeDomains.default` includes `ncad.instructure.com`, which is a guess, not verified (PRD §12.1): a wrong guess cannot leak, because Canvas sources are college by kind, but a generic iCal link on the real host would be treated as personal until Mark tags it. Processing mode defaults: college is `localAI` for the owner and `rulesOnly` for any other profile; other feeds are `cloudAllowed` for the owner (still subject to consent) and `rulesOnly` otherwise. Unknown stored class values read as college and unknown modes as `rulesOnly`. The adapter is `CDBookingFeedSource` behind `BookingSource`, as BD-15 specifies.
Alternatives: Trust the host alone (a wrong host guess would class Canvas as personal).
Consequences: Verify the Canvas host on NCAD's instance and record it here.
Refs: FR-CORE-04, FR-CANVAS-02, BD-15, OD-2

## D-031  Feed secrets and source state  (2026-10-26, M2)
Context: A cdbooking feed URL embeds `feed_token`, the API token is a bearer secret, and a Canvas feed URL is a bearer secret too. Source bookkeeping (ETags, cursors, health) says when and what Mark's college systems answered.
Decision: **For Mark to confirm.** All three are Keychain-only (`cdbooking.<source>.feedURL`, `cdbooking.<source>.apiToken`, `canvas.<source>.feedURL`), keyed by `SourceID`, never in SwiftData, defaults, logs, errors or fixtures; a missing API token deletes any old one, and disconnect deletes the secrets along with the source's items, deadlines and record. Feed URLs must be `https`; `webcal://` is rewritten to `https://`. The `FeedSourceRecord` (ETag, fallback ETag, cursor, health, last attempt and success, admin-scope flag) holds no URL or token and lives in CollegeStore for college sources, because its timing and health are themselves college-derived; CollegeStore has no sync and is excluded from backup. Fetching uses an ephemeral `URLSession` (no cookies, cache or credential storage), so a response or token is never written to disk by the system.
Alternatives: Keep source state in PersonalStore (syncs college-derived bookkeeping); store the feed URL in the record (secret in SwiftData).
Consequences: Disconnect is a full purge of a source's items, deadlines, record and secrets; the secrets need Mark's own Keychain, so live checks are his.
Refs: FR-BOOK-01, FR-CANVAS-01, FR-CORE-04, invariant 1, invariant 6, BD-15

## D-032  Feed fetching: conditional GET, retry, and no fallback when a token is revoked  (2026-10-26, M2)
Context: CLAUDE.md requires timeout, retry with backoff and a visible error state for every integration. Appendix E.2 says `401` is rotation or revocation and `410` is a revoked feed.
Decision: **For Mark to confirm.** `FeedFetcher` sends `If-None-Match` and returns `304` as "not modified". The per-request timeout is 30 s; there are up to 3 attempts with delays of 2 s then 4 s, capped at 60 s, and a server `Retry-After` replaces the delay (still capped). Timeouts, connection errors, `5xx` and `429` are retried; `401`, `403`, `404` and `410` never are. Only `https` is fetched. Health is shown in Settings: `ok`, `unknown`, `failing` (transient, retried next time), and `notConfigured`, `unauthorised` (401) and `revoked` (410) which need Mark. For cdbooking, `401` and `410` on the JSON endpoint stop at once and never fall back to the iCal feed: a rejected token means stop and ask, not try another door with the same secret. The iCal fallback is used only when there is no API token, or when JSON is unavailable (`403`, `404`, `5xx`, `429` after retries, timeout) or is not `cdbooking.bookings.v1`. For Canvas, `401` and `403` are unauthorised and `404` and `410` revoked. No workaround to admin controls is attempted (invariant 9).
Alternatives: Fall back to iCal on any JSON error (hides a revoked token); retry forever.
Consequences: A rotated token shows "paste a new one" and stops until Mark does.
Refs: FR-BOOK-02, FR-CANVAS-01, BD-15, invariant 9, Appendix E.2

## D-033  cdbooking adapter details  (2026-10-26, M2)
Context: Appendix E leaves some reading rules open.
Decision: Endpoints are derived from the feed URL (the path before `/ical/` is the API base: `/api/v1/me/bookings?since=&include=items`, `/api/v1/me/admin-summary`), so the native replacement needs only a new feed URL. The first fetch (no `since`) is a snapshot that replaces everything; later fetches are incremental upserts plus `deleted_ids`, advancing `next_since`; the iCal path is always a full snapshot. `+` in an RFC 3339 offset is percent-encoded. iCal times use `Europe/Dublin` for floating and all-day values. A booking's kind is `X-CDB-KIND` if present, otherwise equipment, because Appendix E.3 does not define it for iCal; rooms use `end` and have no due time. Unknown status values read as `unknown`, not an error. The admin summary is counts only (pending approvals, overdue returns), is nil for a token without admin scope, `403` or `404`, and its deep link must stay on cdbooking's own host, else `/admin` on the origin. Class: bookings and the summary are college; the summary's counts are allowed in notifications and widgets (BD-04).
Alternatives: Assume rooms from iCal (would drop loans).
Consequences: The iCal equipment default should be revisited when Mark's cdbooking sends `X-CDB-KIND`.
Refs: FR-BOOK-02, FR-BOOK-06, FR-BOOK-08, BD-15, BD-04

## D-034  Loans: deadlines, return clash, Live Activity  (2026-10-26, M2)
Context: FR-BOOK-03, 04 and 07 need rules for turning loans into reminders and plans.
Decision: **For Mark to confirm.** An active loan (equipment, has a due time, not returned, checked out or overdue) becomes a college deadline (origin `booking`, stable ID from origin, source and booking ID) with return reminders 24 hours and 2 hours before due (the M1 plan, so notifications are content-free for college). A closed loan (returned, cancelled or rejected) produces a closed deadline so an existing one is marked done; a closed item with no existing deadline creates none (fix `0e75e75`). The return clash check uses a 15-minute window ending at the due time; if any busy block overlaps it, it proposes the latest free 15-minute slot in the previous 48 hours that is not in the past and falls in returns-desk hours 09:00 to 17:00 (assumed; not in Appendix E, tunable), or none, in which case it offers the extension page. The clash carries times and the booking ID only, never titles, and takes the taint of the loan and every busy block considered. The due-day Live Activity shows counts and times only (loans due today, overdue count, next due time); no item names, locations or booking IDs, so the Lock Screen is safe (BD-04). Its ID is `loans.YYYY-MM-DD`, stale at the next due time and ended an hour after the last due time (the app starts and ends it locally in M2).
Alternatives: Show item names on the Lock Screen (college titles on a surface others see); search the whole week for a slot.
Consequences: The desk hours need Mark's real figures. `DerivationID.bookingReturnClash` is added with its taint test.
Refs: FR-BOOK-03, FR-BOOK-04, FR-BOOK-07, FR-DL-01, BD-04, BD-15, B-8

## D-035  Mock cdbooking server in EagarTestSupport  (2026-10-26, M2)
Context: No test may hit the network (CLAUDE.md), and the real server is Mark's to build.
Decision: `MockCDBookingServer` in `EagarTestSupport` is an in-process `HTTPTransport` implementing Appendix E v1 with synthetic data. The ETag names the user's data version: `"j<n>"` for JSON and `"i<n>"` for iCal, bumped on every change, so a client's last ETag matches until something changes, then `304`. `since` returns upserts and `deleted_ids` with `next_since`; iCal uses `TZID=Europe/Dublin`, `DUE`, `X-CDB-STATUS` and folded long lines. The admin summary needs an admin token. Modes simulate rotation (401 everywhere), revocation (401 JSON, 410 iCal), a missing JSON endpoint (404), server error (500), rate limiting (429 with `Retry-After`), a malformed body and an unknown schema. Requests are recorded with whether a valid token was sent, never the token.
Alternatives: A recorded fixture per scenario (cannot test `since`, ETag or modes together).
Consequences: Real-server behaviour (ETag per user rather than per query, date formats) is checked by Mark's manual script when the endpoint exists.
Refs: FR-BOOK-02, Appendix E, CLAUDE.md "Testing expectations"

## D-036  Canvas feed heuristics  (2026-10-26, M2)
Context: Canvas's calendar feed format is general knowledge, not verified on NCAD's instance (RESEARCH.md, Canvas).
Decision: **For Mark to confirm.** An entry is an assignment when its UID contains `assignment` (Canvas uses `event-assignment-<id>`), is a calendar event when it contains `calendar-event`, and otherwise follows the link: `assignment` in the URL means assignment, else event. Only assignments become deadlines (origin `canvas`, college, default M1 reminders); events are shown, not deadlines. The summary's trailing `[CODE]` is the course code and is moved into the deadline title as "Title (CODE)"; the course ID comes from `course_<n>` or `/courses/<n>/`. An assignment's due time is `DUE`, else `DTSTART`; an all-day (`VALUE=DATE`) item is due at the start of that day in the device's time zone (floating and all-day values use it too). Cancelled events and events without a UID or start are skipped; only `https` entry links are kept (they need a login and are not the feed URL). The feed is read in full each refresh with `ETag`, and entries no longer in it are deleted, together with their deadlines. Everything is rules only, with no model call, and lives in CollegeStore. The fixture has all-day and time-zone cases.
Alternatives: Match on the summary text (fragile).
Consequences: Check against Mark's real feed (UID shape, all-day due dates) before relying on it.
Refs: FR-CANVAS-01, FR-CANVAS-02, FR-DL-01, invariant 3, B-8, D-030

## D-037  Pilot metrics: manual Screen Time entries stay on the device  (2026-10-26, M2)
Context: FR-GOV-01 asks for manual weekly Screen Time entries (SM1); the ledger-derived metrics SM2 to SM9 are not part of this slice.
Decision: Minutes and pickups per week, entered by hand for the apps Eagar replaces, are kept in `UserDefaults` (`pilot.screenTime`) on this device only: personal, numbers and a week start only, no content, not synced, because the pilot baseline is per device. Only this manual part is built.
Alternatives: SwiftData in PersonalStore (syncs a baseline that differs per device).
Consequences: Entries do not move to a new device. Only the manual part is built; the ledger-derived metrics are not.
Refs: FR-GOV-01, SM1

## D-038  Demo data flag  (2026-10-26, M2)
Context: Screenshots and demos need a full app without touching real data.
Decision: `-EagarDemoData YES` implies in-memory stores, the fake calendar with a rich demo week and skipping onboarding, then seeds synthetic trials, people and deadlines at launch and confirms the demo calendars' proposed tags (Home personal, NCAD college). Demo notifications go to a `DemoNotificationSink`, so demo records never reach the real notification centre. Every name, service and address is made up; no network or real account is touched.
Alternatives: A separate demo target (a second build to keep in step).
Consequences: Nothing from a demo run persists.
Refs: FR-TRIAL-01, FR-PEOPLE-01, NFR-L10N-01

## D-039  EagarCore additions for M2  (2026-10-26, M2)
Context: New packages need log categories and derived-class IDs (FR-CORE-03).
Decision: `LogCategory` gains `money`, `people` and `feeds`; all loggers still take `LogSafe` values only. `DerivationID` gains `keepInTouchInteraction`, `keepInTouchNudge`, `subscriptionSummary`, `feedDeadline` and `bookingReturnClash`, each with a `Derivation_<case>` test, which `Tools/lint.sh` requires.
Alternatives: Reuse existing categories (mixes content-free counts from different areas).
Consequences: Any new derivation must add its case and test.
Refs: FR-CORE-03, BD-25, BD-03

## D-040  Planned catch-ups: college ones in memory only, counted for the whole week  (2026-10-27, M2)
Context: Review found PeopleModel wrote every planned catch-up, college-slotted ones included, to standard defaults (device and iCloud backup), and stopped counting a catch-up against the weekly budget once it started, so the budget refilled mid-week and a just-planned person was proposed again.
Decision: **For Mark to confirm.** A catch-up is college if the event or the nudge is college (taint rule); college ones are kept in memory only, personal ones in defaults under `people.plannedCatchUps.v2`. The old `people.plannedCatchUps` key is removed on every launch. Planned catch-ups count for the whole week they fall in (supersedes the "until they start" wording in D-028), and anyone with one planned this week is not nudged again. A failed PersonalStore read skips reminder reconciliation instead of treating the empty list as truth.
Alternatives: A CollegeStore model for planned catch-ups (survives relaunch, but needs a new model and an AppServices change); dropping persistence altogether.
Consequences: After a relaunch, college catch-ups planned earlier in the week no longer count, so up to that many extra nudges can appear that week. A planned catch-up and a manual "we talked" log for the same meeting both count.
Refs: FR-PEOPLE-04, FR-PEOPLE-05, FR-PEOPLE-06, FR-TRIAL-02, BD-04, D-028

## D-041  Feed models share the store schema; only CollegeStore accepts them  (2026-10-27, M2)
Context: `FeedSourceRecord`, `BookingItem` and `CanvasItem` must live only in CollegeStore (B-8). EagarStores builds both stores from one model list, and SwiftData traps when code touches a model missing from a store's schema.
Decision: **For Mark to confirm.** The feed models join `AppServices.models`, so both stores carry them in their schema. The per-save class check refuses college records in PersonalStore, and no sync adapter exists for them (`AppServices.syncAdapters`, which the B-8 test reuses). Sources are created with the owner profile: college class and local AI, and a college source is clamped to local AI even if a stored record says `cloudAllowed`.
Alternatives: A CollegeStore-only schema (needs an EagarStore change to split model lists per store).
Consequences: Safety rests on the save-time class check plus the absence of an adapter; sync is CKSyncEngine with explicit adapters, never automatic CloudKit mirroring. Revisit if PersonalStore ever moves to automatic mirroring.
Refs: FR-BOOK-01, FR-CANVAS-01, FR-CORE-04, BD-04, B-8, D-030, D-031

## D-042  Feed setup, secrets display and demo secrets  (2026-10-27, M2)
Context: Settings needs to show which feed is configured without exposing the secret; demo mode must not touch the Keychain or network.
Decision: **For Mark to confirm.** Settings shows the last four characters of the feed URL and token, the same masking as the Claude key. Demo mode keeps feed secrets in an in-memory store and fetches from a fake transport on `.invalid` hosts. Removing a feed deletes its Keychain items.
Alternatives: Show nothing beyond "configured" (harder to tell two URLs apart).
Consequences: Four characters of a feed token are visible on screen.
Refs: FR-BOOK-01, FR-CANVAS-01, invariant 6, D-038

## D-043  Feed refresh cadence  (2026-10-27, M2)
Context: Feeds need refreshing without hammering cdbooking or Canvas.
Decision: Refresh on app activation, at most every 5 minutes; a calendar change only re-reads stored feed data. iOS adds a BGAppRefresh task `app.eagar.feeds.refresh` with a 30-minute earliest start. macOS refreshes on activation only (the hub takes over in M3).
Alternatives: A timer while open (wastes requests); push (M5).
Consequences: A loan added on cdbooking appears at the next activation after 5 minutes, or at the next background refresh.
Refs: FR-CORE-04, FR-BOOK-02, FR-CANVAS-02

## D-044  Loans in the brief, clash acceptance and reopening  (2026-10-27, M2)
Context: The brief must show loans due; a clash needs an action; cdbooking can correct a wrongly closed loan.
Decision: **For Mark to confirm.** "Loans due" uses the deadlines' 7-day horizon and lists loans not yet overdue, without repeating them under Coming up; an overdue loan stays in Overdue with the reschedule action and counts towards the brief notification's level (FR-DL-04 wins over an earlier draft that moved it). Lines are phrased on device only. Accepting a clash creates a local college deadline "Return …" with reminders 15 minutes before and at the time, rather than a calendar event, because the target calendar may sync to a server. A loan deadline reopens only when cdbooking moves the loan from closed back to open; a loan Mark marked done stays done.
Alternatives: A calendar event for the return (leaks college data to a synced calendar); reopening whenever the feed shows the loan open (undoes Mark's own "done").
Consequences: The accepted return slot is visible only in Eagar on that device.
Refs: FR-BOOK-03, FR-BOOK-04, FR-DL-01, FR-DL-04, BD-04, D-034

## D-045  Loan Live Activity and all-day overdue  (2026-10-27, M2)
Context: FR-BOOK-07 asks for a local Live Activity for loans due; Lock Screen content is visible without unlocking. Separately, all-day deadlines at 00:00 showed as overdue on their own day.
Decision: **For Mark to confirm.** The Live Activity (iOS only, started locally) shows counts and times only, never item names or locations, and ends when no loan is due today; it is not ended at its scheduled end unless the app runs. All-day deadlines count as overdue only after their day ends, fixed in the planner and brief checks rather than by moving Canvas due times to 23:59, so hand-entered all-day deadlines benefit too.
Alternatives: Item names on the Lock Screen (college content outside the device boundary rules); end-of-day due times in the importer only.
Consequences: A stale Live Activity can linger past midnight if the app never runs.
Refs: FR-BOOK-07, FR-DL-01, FR-CANVAS-02, BD-04, D-036

## D-046  Package string catalogs are maintained by hand  (2026-10-27, M2)
Context: `Tools/sync-strings.py` (D-008) covers the app, widget and share catalogs only; EagarBrief has its own package catalog.
Decision: New package strings are added to the package catalog by hand, with ga scaffolds, in the same commit.
Alternatives: Extend sync-strings.py to package catalogs (parked).
Consequences: Easy to miss; the catalog-completeness check catches gaps.
Refs: NFR-L10N-01, NFR-L10N-02, D-008

## Parked

- **Tier-pin settings (BD-05):** UI and storage to narrow per-(class, kind) maximum tiers; defaults already enforced. With Settings in M1.
- **Ledger delete hardening:** stop `ClassifiedStore.perform` from deleting ledger or consent rows outside `EagarLedger` (verify finding, low). M1.
- **`setLane` lane IDs:** nothing checks that a `setLane` action names a lane defined in the same document (found while applying D-013). Decide with the rules engine in M3.
- **Consent screens (FR-PRIV-07 UI):** the consent model, registry and revocation are built; per-source consent screens arrive with the first personal source (M2/M3), since M0 has no sources.
