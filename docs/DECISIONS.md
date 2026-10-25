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

## Parked

(none yet)
