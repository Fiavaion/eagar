# Decisions

Current milestone: M0

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

## Parked

- **Tier-pin settings (BD-05):** UI and storage to narrow per-(class, kind) maximum tiers; defaults already enforced. With Settings in M1.
- **Ledger delete hardening:** stop `ClassifiedStore.perform` from deleting ledger or consent rows outside `EagarLedger` (verify finding, low). M1.
- **eagar-rules questions for Mark:** (1) refuse an L3 grant whose lane is not defined in the same document (its boundary is unknown)? (2) per-action required fields (e.g. `adjustScore` needs `amount`) via a `oneOf` split — changes the shared schema the Windows app uses; (3) flag lanes with `boundary: localOnly` but `processingMode: cloudAllowed`?
- **Consent screens (FR-PRIV-07 UI):** the consent model, registry and revocation are built; per-source consent screens arrive with the first personal source (M2/M3), since M0 has no sources.
