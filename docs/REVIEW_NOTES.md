# Review notes: RESEARCH.md, PRD.md, CLAUDE.md

Independent review, 25 Oct 2026. Targeted edits only; no section was restructured or shortened. Mark's six decisions (now PRD §6.0, OD-1…OD-6) were treated as authoritative.

## A. Fact-check (32 claims checked against the source notes)

Sources: `research_notes/iPhone organiser app research/*.md`. Claude model IDs and prices were also checked against the live Claude models overview and pricing pages. The product-self-knowledge skill only points to those docs.

**Supported as written (26):** Gmail restricted scopes, including `gmail.metadata` and `https://mail.google.com/`; `gmail.send` is sensitive; Testing mode allows 100 users and 7-day refresh tokens; unverified production apps capped at 100 users; refresh-token loss on password change, after 6 months unused, and above 100 per client; CASA trigger "store or transmit on servers" and annual recertification; Tier 2 lab price around $540 (2024); Gmail quota 6,000 units/min/user, `messages.get` 20 units, 80M/day threshold with charges "later in 2026"; LSA password IMAP ended 14 Mar 2025; Outlook.com basic auth ended 16 Sep 2024; iCloud app-specific passwords (max 25, revoked on password change) and IMAP/SMTP hosts and ports; YouTube default 10,000 units/day; `search.list` bucket from 1 Jun 2026; subscribe/unsubscribe 50 units; `captions.download` needs edit permission, 200 units; Watch Later/History unavailable since Sept 2016; 30-day storage, 7-day deletion, links open the YouTube app, 200×200 embed, error 153 from Nov 2025; guidelines 5.2.3, 5.2.2, 4.2.2, 4.5.1 and 5.1.2(i) (13 Nov 2025); EventKit has no read-only mode; `contacts.notes` entitlement; Siri AI not in the EU on iOS/iPadOS 27 but available on macOS 27; on-device context 4,096 (TN3193) vs 8,192 (WWDC26); PCC 32K, Small Business Program, under 2M downloads; Clockwise shut 27 Mar 2026; Notion Mail closed 22 Sep 2026; Copilot priority view removed Feb 2026; Pulse retirement announced 17 Jun 2026; Meta bought Limitless 5 Dec 2025 (capture off 19 Dec); Superhuman/Grammarly Jul and Oct 2025; Mesh rename 26 Mar 2026; UpHabit Apr 2026; Claude IDs `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-fable-5-1` and prices $0.10/$0.50, $2/$10, $4/$20; Sonnet/Opus 5.5 cache hits at 0.05×; batch not ZDR-eligible with 29-day retention; Fable needs 30-day retention (ZDR page); `inference_geo` only `global`/`us`; Ollama defaults (4,096 context, loopback, no `tool_choice` or caching); vLLM `/invocations` left unauthenticated; Cloudflare $5/month minimum and $6.99/month hourly-cron example; DPF upheld 3 Sep 2025 with a CJEU appeal pending; Pocket Casts iOS under MPL-2.0.

**Corrected or softened (6):**

| Claim | Problem | Fix |
|---|---|---|
| RESEARCH: Reclaim "absorbed Clockwise users" | The notes say Reclaim *offered price matching* | Reworded |
| RESEARCH: Overcast transcripts "generated on-device" | The notes say this is unconfirmed | Softened |
| RESEARCH: restricting Gmail "revokes existing tokens" | The notes say it revokes *untrusted* apps' tokens, and allows Trusted or "Specific Google data" apps | Reworded |
| RESEARCH: Haiku $0.10/$0.50 | Missing the ≤100K-prompt condition | Added the threshold |
| PRD BD-02: SwiftData mirroring "syncs whole containers" | Not in the notes; last-writer-wins comes from a secondary source | Softened |
| PRD BD-13: Graph `Mail.ReadWrite`/`Mail.Send`; BD-23: MSAL is MIT | Not in the notes | Marked "to verify" |

Also fixed: the Gmail AI Inbox wording in Appendix B5 (Education rollout is "in the coming months", not "not available"), and the OCR wording (Foundation Models `OCRTool` is OS 27 only).

## B. Consistency

**Owner decision 4 (work-derived profile lines go to the cloud once approved).** Fixed everywhere it appeared:
- **PRD:** §1 Summary, new §6.0, BD-10, §7.3 `ProfileLine`, the §7.4 policy table, FR-LEARN-08/09, FR-MCP-02, M4 acceptance (B-10 and Mark's live run), §10.1 B-10, Q5 (answered), §13 I3 and I14, Appendix A §5, Appendix B (B2 and B10), Glossary.
- **CLAUDE.md:** invariant 1 (declassification path) and invariant 11 (lint plus per-line approval).
- **RESEARCH.md:** intro, Mark's decisions (two places), the learning-pipeline paragraph (now marked resolved), Novel feature 11, open question 5 (answered).

Per-line approval and the non-identifying lint are kept. `sendToCloud` stays as a per-line opt-out that defaults to `true` once a line is approved. The `workDerived` tag is now provenance only, not a cloud filter.

**Dangling "User decision n" references.** The PRD cited "User decision 2–11", but no such list existed in any of the three documents. I added §6.0 (OD-1…OD-6) and remapped every reference. The rationales for BD-13, BD-15, BD-16 and BD-18 now cite RESEARCH sections, because no owner decision covers them.

**L3 vs approve-before-send.** RESEARCH and BD-12 defined L3 as an "approved-by-default send" under a category grant, which contradicts OD-5 and NG1. L3 is now a fast-path approval of each message plus a held send with undo. The change is in BD-12, FR-SEND-13, the M4 acceptance criteria, the Appendix F semantic rule 1, the Glossary, the RESEARCH graded-autonomy table and text, CLAUDE.md invariant 4, and new §13 entry I16.

**Milestones vs FRs.** §8 promised a per-milestone FR mapping that did not exist. I added an **FRs delivered** line to M0–M6. Two gaps were closed along the way:
- FR-SUG-01 (the event log) is now in M1, because M1's brief features FR-BRIEF-07/08 need it.
- FR-GOV-01 (manual Screen Time entry) is now in M2, because SM1 needs a baseline before M3.

**Terminology.** The Glossary now maps RESEARCH `local-only`/`cloud-allowed` to the PRD's `localOnly`/`cloudAllowed`, and the RESEARCH "processing class" to the PRD's "processing mode". It also explains how boundary relates to data class, and adds OD-n.

**Other fixes.**
- RESEARCH said the Canvas API would come in "M5 or M6"; it now notes that the PRD puts it in M6.
- The conflict between RESEARCH's conclusion ("approval queue first") and the PRD milestone order is recorded as §13 I17.

**CLAUDE.md vs PRD.** All BD numbers that CLAUDE.md cites (BD-04, 06, 10, 11, 12) exist and match. Test naming matches §10.1.

## C. Buildability

**M0 is now concrete enough to start.**
- Exact targets: app `Eagar`, `EagarTests`, `EagarUITests`.
- Shared scheme `Eagar` and test plan `Eagar.xctestplan`.
- An xcconfig for bundle and team placeholders.
- An explicit list of the M0 packages, with their platforms and Swift 6 mode.
- Extension targets and packages are created in the milestone that first needs them, not as empty shells.
- A five-step build order, each step ending in a passing test.
- `docs/DECISIONS.md` seeded with "Current milestone: M0", which CLAUDE.md relies on.
- `Tools/lint.sh` and `ci.yml` named.
- A project-creation decision, D-001: Mark creates the project in Xcode, or XcodeGen is approved. Claude Code should not hand-write a `.pbxproj`.
- Two new acceptance criteria: B-14 in unit form, and the build and test commands work.

**Testability fixes.**
- The M0 "builds on iOS 26 simulator" criterion now tolerates the runtime that is actually installed.
- CI uses the current Xcode, because OS 27 availability-gated code needs the 27 SDK.

**Layout.**
- §7.2 now lists `EagarShare`, the app test targets, `docs/benchmarks/` and schema `fixtures/`, plus an explicit package layer list. That list resolves where `EagarAI`, `EagarHubKit` and `EagarRules` sit, which the old one-line dependency rule left unclear.
- CLAUDE.md's layout now matches the PRD and shows which milestone creates each target.
- CLAUDE.md's build commands now use the test plan, add an iOS test run and a `Boundary` run for EagarStore, and mark which commands only work from M3 and M5.
- CLAUDE.md's `models.json` note now carries the verified seed IDs and prices.

## Unresolved (for Mark)

1. **Reinstating a standing-grant L3.** If Mark wants an L3 that sends under a category grant without approving each message, he would need to change OD-5 explicitly. As written, the documents don't allow it.
2. **Project creation route (D-001).** Mark creates the project in Xcode, or approves XcodeGen as a build-time tool.
3. **CI runner.** Confirm the GitHub macOS runner image has Xcode 27 and the iOS 26 and 27 simulator runtimes.
4. **Facts still to verify.** These are marked in the documents: Graph scopes, the MSAL licence, the Gemini Daily Brief EU status, and Shortwave's provider support. Everything in PRD §12.1 (V1–V18) is still open.
5. **Q4 (Tailscale, content-free iCloud state) and Q6 (L3 on NCAD).** These are still open. Under OD-5, the Q6 default (no L3 on college accounts) is now the only safe reading.
