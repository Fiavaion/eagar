# Eagar turns eight apps into one brief

No shipping product combines appointments, deadlines, college equipment loans, friendships, free trials, podcasts, YouTube and multi-account email in one native Apple app, and none does it local-first, open source, with the user's own Claude key, in the EU. Each area has strong single-purpose incumbents. The 2025–2026 shake-out points to a gap: **Clockwise shut down (27 Mar 2026), Notion Mail closed (22 Sep 2026), Microsoft removed Outlook's Copilot priority view (Feb 2026), ChatGPT Pulse was retired (Jun 2026), and Rewind/Limitless left the EU after Meta bought it (Dec 2025)**. Standalone AI prioritisation and always-on cloud capture have struggled to keep users or pay for themselves, and Google's integrated equivalents (Gmail AI Inbox, Gemini Daily Brief) launched US-first. The app is technically buildable as one multiplatform SwiftUI codebase, but four hard limits shape it. **Every Gmail scope that can read mail is "restricted"**, which means verification and possibly a paid CASA assessment for public distribution. **YouTube data can be listed, but never downloaded, played in the background or cached beyond 30 days.** **No API reads Apple Podcasts subscriptions or other apps' App Store subscriptions.** **iOS gives roughly 30-second, system-scheduled background windows**, so "new episode downloaded" alerts need a small push server. The legal centre of gravity is Mark's NCAD Workspace account. Mark has authority to use AI on it **for himself only**, under his own rule that **no college data leaves his local devices**. NCAD mail, the NCAD calendar and Canvas data are therefore processed only by local models on his 48 GB Mac and Apple's on-device model, never by Claude or any cloud service. Only his reviewed, non-identifying style profile may reach the cloud (Mark has confirmed this includes approved lines learned from his NCAD mail), and **no email is ever sent without his explicit approval**, the principle behind the Windows mail app he has already built. A per-account data boundary and a rules-only mode stay in the product because a staff rollout still needs institutional approval, and the governance pack is the evidence for extending beyond Mark. The most valuable novel features come from HCI research rather than from more AI. They include one brief delivered at natural breaks instead of constant checking, a confidence ladder that mostly does nothing and only sometimes asks or acts, per-account priority lanes, and a reviewable "About me" profile learned locally on Mark's 48 GB Mac. Together they make the app a calmer replacement for checking several apps and devices.

## Mark's decisions and context, as given

This section records the owner's own decisions and context as stated. The PRD should treat them as binding inputs, not findings.

**Who and how.** The user is **Mark, Digital Technical Officer at NCAD** (National College of Art and Design, Dublin), working across Fine Art Media, Product Design (Interaction) and Communication Design. The app will be **open source and distributed on the App Store under his own company**. He develops with **Claude Code in VS Code**, using a **RESEARCH.md + PRD.md (milestones M0–M6)** method; this document is the RESEARCH.md input. The target is **one multiplatform SwiftUI codebase for iPhone, iPad and Mac**.

**Compute.** His **Apple Silicon Mac has 48 GB of unified memory**, so heavy local AI (20–30B-class models through MLX or Ollama) runs on the Mac. **Apple's on-device Foundation Models** handle light tasks on iPhone and iPad. The **Claude API with his own key** is the first cloud tier. His **two NVIDIA DGX Spark systems** (linked by ConnectX-7 and part of the NCAD estate that his "Meitheal" orchestrator pools) come later as a self-hosted tier.

**Local learning pipeline.** The app downloads his email and analyses **his own output**: how he writes, how he responds, and his workflow patterns. This analysis uses **local AI only**. The app then **deletes the source emails used for processing** and keeps only a **non-identifying style/workflow profile** about him. **He reviews and approves that profile before it is shared with the cloud AI as generic context about his workflow and how he writes and responds. This explicitly includes approved profile lines learned from his NCAD mail.** (Interpretation for the PRD: "deletes" means the app purges its own downloaded working copies. It does not delete messages from the mail server. Open question 2 asks him to confirm this.)

**Work account: authorised for Mark, local-only.** His NCAD Google Workspace account falls under a **blanket IT rule that blocks Claude connectors and any local or cloud AI access to Workspace apps**. Mark says the rule exists mainly from lack of knowledge, and he is the **proof of concept** for whether such a solution is rolled out to other staff. **He has full authority for this work as long as it is limited to him only.** Within that scope his own data-protection rule applies: **no college data leaves his local devices** (Mac, iPhone, iPad). His decisions:

| Decision | What it means for the build |
|---|---|
| A per-account **data boundary** setting: `local-only` or `cloud-allowed` | NCAD mail, the NCAD Google calendar, Canvas and cdbooking data are `local-only`. They are processed by the Mac's MLX/Ollama model or Apple's on-device model, and never by Claude, Private Cloud Compute or any other cloud service. Personal accounts are `cloud-allowed`, with consent per feature. The boundary is enforced in the AI gateway and the sync layer, not just the UI. |
| The **local learning pipeline is ON for the work account** | Download → local analysis of his own output → delete the working copies → a profile he reviews line by line. Only approved, non-identifying lines may reach the cloud, and approved lines learned from NCAD mail are included. |
| **Approve-before-send** is binding for every account | No email is sent without his explicit approval (see the human-in-the-loop section). |
| A **rules-only "policy mode"** remains available per account | For staff whose institution has not approved AI, as the default for any new work account, and as a switch Mark can flip himself. |
| The **governance pack** is kept, but reframed | An IT allowlisting request, a draft DPIA for NCAD's DPO, a data-flow diagram, and pilot metrics with an approval ledger. It is the **evidence for extending beyond Mark**, not a precondition for his own use. |
| **Written authorisation** | Recommendation: keep an email confirming the scope ("limited to Mark only", local processing, approve-before-send) in the pilot record. |
| OAuth: an **NCAD-managed "Internal" client** for the work account, and **his own personal client ID** for personal accounts | Two Google OAuth client configurations, chosen per account. |

**Why the boundary still matters with authority in hand.** Work email contains **third parties' personal data (staff, students, external contacts) for which NCAD is the GDPR controller**. Even his own sent mail quotes and names other people. Mark's authorisation covers his own use. The local-only boundary keeps that use proportionate and keeps NCAD data away from Claude's US/global-only processing ([Claude data residency](https://platform.claude.com/docs/en/manage-claude/data-residency)). Two practical consequences follow. First, **authority is organisational, but Workspace API controls are technical**. If IT has restricted Gmail or blocked unconfigured apps, Eagar's OAuth client will get `admin_policy_enforced` until IT allowlists that client ID, whatever Mark's authorisation says. Restricting a service also revokes existing tokens of untrusted apps ([Workspace API controls](https://knowledge.workspace.google.com/admin/apps/control-which-apps-access-google-workspace-data)). The route his Windows app already uses may show what IT has effectively permitted (open question 1). Second, the authorisation covers no one else, so the staff rollout still runs through the governance pack. Forwarding work mail to a personal account remains out of bounds in every case, because it would move college data into a cloud mailbox and around admin controls.

**Existing Windows app.** Mark has already built a **Windows app that downloads email from his work account**, designed around a strong human-in-the-loop principle: **no email can be sent without his specific permission**. It worked well, and he wants Eagar to expand on it. A dedicated section below does that. The route the Windows app uses to reach work mail is not yet known.

**Google Calendar and Canvas.** He wants **Google Calendar** and **Canvas** (the LMS used at NCAD) integrated, but only if they don't add huge complexity. The assessment is under integrations below.

**Internal OAuth client: partly confirmed, needs IT confirmation.** Google's restricted-scope verification page lists **"internal use within one Workspace/Cloud Identity org"** among the cases that don't need public verification. It also notes that **domain-wide installation still needs app verification if it uses sensitive or restricted scopes** ([Google restricted-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)). A 2026 Nylas guide likewise lists internal-only apps, and apps allowed by Workspace admins, among the exemptions ([Nylas](https://developer.nylas.com/docs/dev-guide/provider-guides/google/google-verification-security-assessment-guide)). So an Internal-user-type client owned by NCAD's Google Cloud organisation appears to avoid Google's public verification and CASA, **as long as staff consent individually rather than through a domain-wide install**. Three things still need confirming with NCAD IT. First, the Cloud project must sit inside NCAD's organisation, so IT creates or adopts it. Second, the exemption removes *Google's* review, not *NCAD's* API controls: the admin must still set the client to Trusted or "Specific Google data". Third, the notes don't show whether an Internal client avoids the 7-day refresh-token expiry that applies to External apps in Testing status. Treat it as likely but unconfirmed.

**cdbooking.com.** Mark is **master admin of cdbooking.com** ("NCAD Bookings — studios, rooms and equipment") and is **separately building a native CloudKit-based replacement app** with its own PRD. Integration will use a **per-user secret iCal/JSON feed plus a webhook**, designed to work with the replacement too. The public site shows only a single-page-app shell with no vendor branding, API documentation or iCal links, which fits a custom app whose data sits behind a login ([cdbooking.com](https://cdbooking.com)). As admin, Mark can add the feed himself.

**Working name: Eagar.** *Eagar* is Irish for order or arrangement, as in *in eagar* ("in order; edited"). It fits Mark's habit of Irish project names (Meitheal, Cuardach) and describes the product's job: putting his day in order. It is a placeholder he can change. One constraint applies to any final name: YouTube's branding rules forbid "YouTube" or "YT" in the app name ([YouTube Branding Guidelines](https://developers.google.com/youtube/terms/branding-guidelines)).

## Incumbents own single domains; nobody owns the day

Across all seven areas the pattern repeats. Polished native apps have little or no AI (Things, Fantastical, Overcast, Castro). AI-heavy apps are cloud-processed, subscription-priced and often web-view or laggy on mobile (Motion, Akiflow, Superhuman's weaker mobile app). Products in several categories have died, pivoted or been acquired. Each table below is compact, and the paragraph after it names the exploitable gap.

### Email triage and unified inboxes

| Product | 2025–26 status | Providers / platforms | Price | Distinctive | Weakness Eagar can exploit |
|---|---|---|---|---|---|
| Superhuman | **Bought by Grammarly Jul 2025; Grammarly renamed itself Superhuman Oct 2025** ([Fast.io](https://fast.io/resources/superhuman-ai-review-2026/)) | Gmail, M365 only | $30–40/mo, no free tier | Auto Labels, tone-matched Auto Drafts, Ask AI | No IMAP/iCloud; drafts replies to newsletters; weaker mobile |
| Shortwave | **Prices up 30 Jun 2026** (Pro $14→$18) ([UsagePricing](https://usagepricing.com/blueprint/activity/shortwave-2026-06-30-price-change)) | Gmail-centric (Outlook support disputed) | Free–$120/seat | Plain-English AI filters, voice-matched drafts, uses Claude; CASA Tier 2 ([Tooliverse](https://tooliverse.ai/tools/shortwave)) | Cloud sub-processors (Google, OpenAI, Anthropic, Pinecone) |
| Spark | Active | Gmail, Outlook, iCloud, Exchange, IMAP; all platforms | Free / $10 / $20 mo ([Spark](https://sparkmailapp.com/pricing)) | Smart Inbox, Gatekeeper | AI quotas; historically server-held tokens for push ([Readdle, 2015](https://readdle.com/blog/how-we-handle-your-account-information-in-spark)) |
| HEY | Active | Own mail host only | $99/yr ([HEY](https://www.hey.com/pricing/)) | Screener, Imbox, Feed, Paper Trail | Can't read external Gmail/Workspace |
| Canary | Active | Gmail, Outlook, iCloud, Exchange, IMAP | Free / $36 / $100 yr ([Canary](https://canarymail.io/fr/prix.html)) | **On-device triage**, local NL search ([Canary AI](https://web.canarymail.io/features/ai)) | Closed source; drafts in cloud |
| Mimestream | Active (iOS in beta) | Gmail API only, macOS | Paid | **No intermediary server; tokens only on device** ([Mimestream](https://mimestream.com/)) | No AI; Gmail only |
| Notion Mail | **Shut down 22 Sep 2026** (announced ~25 Jun 2026) ([Android Authority](https://www.androidauthority.com/notion-mail-is-shutting-down-3681674/)) | Gmail only, no iOS | AI needed Notion AI | NL auto-labels | Dead: "users prefer AI agents to an inbox" |
| Outlook Copilot priority view | **Removed Feb 2026** "due to user feedback and costs" ([MC1089318](https://mc.merill.net/message/MC1089318)) | Outlook mobile | ~$30/user/mo add-on | High priority / Needs replies | Dead |
| Gmail AI Inbox | Beta; Workspace Rapid Release from 12 Oct 2026, **Education "in the coming months"**, **US English only**, smart features off by default in EEA ([Drag](https://www.dragapp.com/blog/gmail-ai-inbox/)) | Single Google account | AI Plus/Pro | Ranks by contact and time signals | Not available to an Irish Education tenant soon; single-account |
| Apple Mail + Apple Intelligence | Categories and priority messages; in EU since iOS 18.4 ([TechCrunch](https://techcrunch.com/2025/03/31/apple-rolls-out-priority-notifications-as-apple-intelligence-expands-to-eu)) | Any account in Mail | Free | Priority at top of Primary | No API for third parties to read it |
| Inbox Zero / SaneBox / alfred_ | Active | Gmail+Outlook / IMAP / IMAP | $20 / $7 / $29.99 mo ([Inbox Zero](https://www.getinboxzero.com/blog/post/best-ai-email-assistants)) | Open-source rules (Inbox Zero); cross-inbox daily brief (alfred_) | Web-first, cloud-hosted |

No competitor advertises **prioritisation by source account**, and none advertises a mode that applies **no AI to one account while using AI on others**. The two 2026 shutdowns support a deterministic-rules-first design with AI as an optional layer. Canary shows on-device triage works, and Mimestream shows a serverless direct-API client works. Neither is open source or BYO-key.

### AI planners and calendars

| Product | 2025–26 status | Price | Distinctive | Weakness |
|---|---|---|---|---|
| Clockwise | **Shut down 27 Mar 2026**; team hired by Salesforce; ~1 week notice ([Dupple](https://dupple.com/learn/best-ai-scheduling-assistants)) | — | Focus-time optimisation | Dead |
| Reclaim.ai | **Acquired by Dropbox (2024)**; offered Clockwise users price matching ([Dupple](https://dupple.com/learn/best-ai-scheduling-assistants)) | Free / $10 / $15 seat | Flexible habits and focus blocks | "Repeated disruptions"; no standalone app |
| Motion | Active (pivot rumours unverified) | ~$19–49/mo ([Morgen](https://www.morgen.so/blog-posts/motion-review)) | Auto-schedules everything | Rigid; web-view mobile app; trial-billing complaints ([Kimola](https://kimola.com/reports/unlock-task-management-success-with-our-in-depth-analysis-app-store-us-151020)) |
| Morgen | **Dropped free plan Mar 2026** | $15–30/mo | **AI Planner proposes, user confirms** | Subscription |
| Sunsama | **First price rise in five years (2026)** | $20–25/mo | Guided morning plan and shutdown | 10–15 min ritual twice daily |
| Akiflow | Active; Aki assistant in-app since Mar 2025 ([Carly](https://www.usecarly.com/blog/akiflow-review/)) | $19–34/mo | Universal inbox from 12+ tools | Laggy mobile; trial billing; hidden caps |
| Amie | 2026 repositioned as "calendar-native AI executive assistant" | Unclear | On-device meeting transcription; **remote MCP server** ([Amie](https://amie.so/blog/best-ai-executive-assistant)) | Mac app reported laggy |
| Structured | Active | £17.99/yr ([CoolCuration](https://coolcuration.com/structured-app-review-uk)) | One timeline of tasks and events; energy monitor | AI "shuffles; it does not think" |
| Fantastical | Active; 40% price rise complaint | $4.75–6.99/mo ([Morgen](https://morgen.so/blog-posts/fantastical-pricing)) | NL entry, Openings, Proposals | No AI planning |
| Todoist | **Pricing change Dec 2025**; Ramble voice-to-tasks Jan 2026 ([MakerStack](https://makerstack.co/reviews/todoist-review/)) | $4–5/mo | Ramble, Email Assist | Tasks only |
| Things 3 | 3.22.x (Jan 2026), no AI ([Wikipedia](https://en.wikipedia.org/wiki/Things_(software))) | One-off | Best-in-class native polish | No AI, no integrations |
| Apple Reminders (iOS 26) | Suggested reminders from share sheet; Auto-Categorize ([Apple](https://support.apple.com/en-ie/124025)) | Free | System-level | Manual trigger only |

The planners split into "plans for you" (Motion, Reclaim) and "plans with you" (Morgen, Sunsama). The second pattern draws fewer "rigid" and "disruptive" complaints and suits an approval-gated design. **None ingests booking-system loans, trial end dates, relationship cadences or a media backlog.** Native Apple quality and AI rarely coexist.

### Keep-in-touch and personal CRM

| Product | 2025–26 status | Price | Distinctive | Weakness |
|---|---|---|---|---|
| Mesh (formerly Clay) | **Automattic acquired Clay Jun 2025; renamed Mesh 26 Mar 2026** ([Mesh](https://me.sh/stories/mesh); [Dex review](https://getdex.com/blog/mesh-review/)) | Free / $10–20/mo | Fading-relationship flags, Nexus NL search, MCP server | iMessage import failures; buggy (per competitor review) |
| Dex | Active | $12–20/mo ([Dex](https://getdex.com/blog/dex-vs-monica/)) | Pre-meeting brief emails, LinkedIn job-change alerts | Networking-oriented, cloud |
| UpHabit | **Personal CRM apps shut down Apr 2026** ([Dex list](https://getdex.com/blog/personal-crm-list/)) | — | — | Dead |
| Garden / FollowUp / Nouri | Abandoned or pivoted | — | — | Dead |
| Monica | Open source; v3 "Chandler" promised by end 2026 ([Monica](https://monicahq.com/en/blog/chandler-is-in-beta/)) | Free self-host / $9/mo | Stay-in-touch intervals, CalDAV export | **No mobile apps**, manual only |
| CatchUp / Up Ahead / Bond / Amato / Linc | Active | Free–$70 one-off ([TapSmart](https://www.tapsmart.com/features/catchup-apps-roundup/?amp=1)) | Randomised timing in cadence; weekday limits; **Bond's "can you cope this week?" total** | Manual, no automatic signals |

Two tiers exist: automatic, networking-oriented, cloud PRMs, and warm, manual friendship apps. **Nobody blends keep-in-touch into the day planner itself**, as in "free evening Thursday; Aoife hasn't heard from you in seven weeks". The category's high death rate is an argument for local-first, open data.

### Subscription and free-trial trackers

| Product | 2025–26 status | Detection method | Price | Gap |
|---|---|---|---|---|
| Bobby | Active | Manual tiles ([WhistleOut](https://www.whistleout.com/CellPhones/Apps/bobby-app-review)) | Free + IAP | Manual |
| TrialGuard | New 2026 | **Photo of a receipt** → AI extraction; reminders 1/3/7 days before ([App Store](https://apps.apple.com/us/app/-/id6756027142)) | $34.99/yr | Needs a photo; 6 ratings |
| Rocket Money | Active, **US only** ([Orbit Money](https://orbitmoney.io/compare/rocket-money-uk)) | Bank feed (Plaid) | Subscription | Unavailable in Ireland |
| Emma / Snoop / Little Birdie | Active, UK | Open banking; Little Birdie warns before trial end ([Which?](https://www.which.co.uk/news/article/how-apps-can-help-you-spot-subscriptions-a0ag58e0gyOY)) | Free–£83.99/yr | UK only |
| Revolut | Active in Ireland | In-bank recurring-payment view, merchant blocking ([Revolut](https://www.revolut.com/news/revolut_launches_smart_subscriptions_feature/)) | Bank feature | Only Revolut card payments; blocking ≠ cancelling |
| GoCardless Bank Account Data (Nordigen) | **New sign-ups disabled** ([dev.to](https://dev.to/johnfrandsen/gocardless-bank-account-data-alternatives-what-to-use-when-signups-are-disabled-326d)) | Free AIS API (formerly) | — | Alternatives need eIDAS certificate at €2,000–10,000/yr |

No surveyed tracker detects trials automatically from the inbox on Apple platforms. Bank linking is impractical for an individual developer in Ireland. **Email parsing is the realistic automatic channel**, backed by a share-sheet and screenshot fallback.

### Podcast players

| Product | 2025–26 status | Distinctive | Weakness / gap |
|---|---|---|---|
| Apple Podcasts | iOS 26: 0.5–3× speed, Enhance Dialogue per show ([MacRumors](https://www.macrumors.com/guide/ios-26-podcasts)); 26.2 auto-chapters and "mentions"; 26.4 HLS video; OS 27 video on Mac with PiP, search within show ([MacRumors](https://www.macrumors.com/2026/06/09/apple-podcasts-gets-video-on-mac-and-apple-tv/)) | Sync Library, per-show notifications, auto-downloads | Up Next queue reported to empty unexpectedly ([Apple Community](https://discussions.apple.com/thread/256116320)); library unreadable by third parties |
| Overcast | **Transcripts launched Apr 2026**, generated automatically on Apple Intelligence devices when missing (on-device vs server not confirmed) ([9to5Mac](https://9to5mac.com/2026/04/08/overcast-launches-podcast-transcripts-in-new-app-update-for-iphone/)) | Smart Speed, Voice Boost, server-side crawler ([marco.org](https://marco.org/2014/02/23/the-value-of-background-fetch)) | 2024 rewrite regressions show solo-rewrite risk ([Michael Tsai](https://mjtsai.com/blog/2024/07/18/overcasts-new-foundation/)) |
| Pocket Casts | **Playlists replaced Filters Nov 2025** ([blog](https://blog.pocketcasts.com/2025/11/24/playlists-a-new-way-to-organize-your-listening/)); web player free Mar 2025; iOS app **open source MPL-2.0** ([GitHub](https://github.com/Automattic/pocket-casts-ios)) | Smart Playlists, synced Up Next, explicitly avoids AI discovery ([TechCrunch](https://techcrunch.com/2025/03/11/podcast-app-pocket-casts-makes-its-web-player-free/)) | Server not open |
| Castro | Owned by Bluck Apps since Jan 2024; private-feed fixes 2025 ([Birchtree](https://birchtree.me/blog/castro-is-back-baby/)) | **Inbox→Queue triage**, Trim Silence, per-show caps ([castro.fm](https://castro.fm/)) | Small team |
| Snipd | 2026: YouTube link support, AI DJ (competitor source) ([BibiGPT](https://bibigpt.co/blog/posts/snipd-2026-update-vs-bibigpt-podcast-youtube-ai-en)) | Headphone-tap snips with AI summaries; Notion/Readwise export ([App Store](https://apps.apple.com/app/id1557206126)) | ~$42/yr for AI |

App churn also shapes this category: Stitcher closed in 2023 and Google Podcasts in April 2024 ([PodcastVideos](https://www.podcastvideos.com/podcast-app-graveyard-failed-podcast-platforms-google-podcasts-stitcher.md)). No 2025–26 podcast-app shutdowns were found. The gap is not a better player. It is a player whose **backlog sits inside the same attention budget as YouTube and the day plan**, with Castro-style triage and Claude summaries under the user's own key.

### YouTube subscription managers

| Product | Status | Distinctive | App Store viability |
|---|---|---|---|
| PocketTube | Active (2019 source) | Channel groups with per-group feeds ([gHacks](https://www.ghacks.net/2019/12/19/pockettube-offers-better-youtube-subscriptions-management/)) | Yes |
| Unhook | Browser extension | Removes recommendations and Shorts ([Edge](https://microsoftedge.microsoft.com/addons/detail/unhook-remove-youtube-r/hebpjnnclppdnfghdnmhgdljmjpfhggk)) | N/A |
| Play | Active | Save-for-later with tags, watched state, iCloud sync, Shortcuts ([MacStories](https://www.macstories.net/reviews/play-a-fantastic-utility-for-saving-and-organizing-youtube-videos-for-later/)) | Yes (its Downie hand-off conflicts with the no-download rule) |
| Readwise Reader | Active | Transcript-synced viewing and highlights ([Readwise](https://docs.readwise.io/reader/docs/faqs/videos)) | Yes |
| NewPipe / FreeTube | Active | Scrapes YouTube; downloads ([HandWiki](https://handwiki.org/wiki/Software:NewPipe)) | **No** — breaches YouTube terms and 5.2.3 |
| RSS readers (Serial, Miniflux) | Active | Separate Shorts and live; feeds flaky since Dec 2025 ([HN](https://hn.nuxt.dev/item/48030964)) | Yes |

The time-saving patterns are channel groups, no algorithmic home feed, Shorts and live filters, triage, and a time budget. None of these tools combines YouTube with podcasts, de-duplicates stories across the two, or puts the backlog into a daily plan.

### Unified assistants and daily briefs

| Product | 2025–26 status | What it does | Gap |
|---|---|---|---|
| ChatGPT Pulse | **Retirement announced 17 Jun 2026**, folded into Scheduled Tasks ([Digit](https://www.digit.in/news/general/openai-is-retiring-chatgpt-pulse-and-replacing-it-with-scheduled-tasks-here-is-why.html/amp/)) | Overnight cards; lesson: proactive works when "personalised, action-oriented, and steerable" | Generic feed underperformed |
| Gemini Daily Brief | **Announced 19 May 2026, US-only beta**; EU timing unconfirmed ([andrew.ooo](https://andrew.ooo/answers/what-is-gemini-daily-brief-overnight-agent-may-2026/)) | Overnight agent across Google apps; acts with approval | Google-only; not in Ireland |
| Rewind / Limitless | **Acquired by Meta 5 Dec 2025; capture disabled 19 Dec 2025; withdrawn from EU/UK** ([9to5Mac](https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/)) | "Remember everything" | Trust and regulatory risk of always-on capture |
| Martin AI | Active | Background EA with morning summary ($30–99/mo) ([AI Agent Rank](https://aiagentrank.io/blog/martin-ai-review-2026)) | **2–4 weeks onboarding**; non-English lags |
| Claude connectors | Calendar connector is **read-only** ([Claude docs](https://claude.com/docs/connectors/google/calendar.md)) | Gmail/Drive/Calendar context | Blocked for NCAD account anyway |
| Mem 2.0 / Saner / Raycast iOS | Active | Notes agent; AI daily plan; AI chat with Mac sync | Single-domain |

The big assistants converged on a **scheduled, connector-fed brief**. Google's version is US-first, and OpenAI's generic feed became user-scheduled tasks. An EU-usable, steerable, local-first brief that also covers loans, trials, friends and media has no direct competitor.

## Constraints that shape the design

These are hard limits found in the research, written as a checklist the PRD can enforce. Each line names the limit and its design consequence.

**Google and Gmail**

- [ ] **All Gmail read scopes are restricted**, including `gmail.metadata` (headers only), `gmail.readonly`, `gmail.modify` and the IMAP/SMTP scope `https://mail.google.com/` ([Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)). A "headers-only" mode does not lower the approval bar.
- [ ] **Public distribution with restricted scopes needs restricted-scope verification.** A **CASA security assessment** is required "if you store or transmit restricted scope data on servers". Recertification is annual ([Google](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)). Google doesn't say whether an on-device-only client is exempt. 2024 Tier 2 lab prices started around **$540** ([Switch Labs](https://www.switchlabs.dev/post/casa-tier-2-tier-3-security-review-providers-pricing-and-the-cheapest-option)). Never route Gmail data through a developer server.
- [ ] **Testing mode: at most 100 test users, and refresh tokens expire after 7 days** ([Google Cloud help](https://support.google.com/cloud/answer/15549945)). Unverified production apps show a warning screen and are capped at 100 users ([Google](https://support.google.com/cloud/answer/7454865)). Refresh tokens also die on a password change, after 6 months unused, and beyond 100 per account per client ([OAuth2](https://developers.google.com/identity/protocols/oauth2)). Plan a graceful re-consent flow.
- [ ] **Limited Use:** Google user data may be used only for user-facing features, with no human reading without consent ([User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)). **The Workspace API policy bans using user data to create, train or improve an AI model, except "that specific user's personalized model"** ([Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy)). The About-me profile must stay per-user and must never pool data across users.
- [ ] **Workspace admins can block the app** by client ID or bundle ID, restrict Gmail so only Trusted or "Specific Google data" apps get Gmail scopes (which revokes untrusted apps' existing tokens), restrict IMAP to listed OAuth client IDs, disable auto-forwarding and disable Apps Script ([API controls](https://knowledge.workspace.google.com/admin/apps/control-which-apps-access-google-workspace-data); [IMAP](https://knowledge.workspace.google.com/admin/sync/turn-pop-and-imap-on-or-off-for-users)). Treat `admin_policy_enforced` as the correct outcome and show a "request access from IT" path. Never offer a workaround.
- [ ] **Education editions let users over 18 request app access**, and requests appear under "Apps pending review" ([API controls](https://knowledge.workspace.google.com/admin/apps/control-which-apps-access-google-workspace-data)). This is the in-product route for the pilot request.
- [ ] **Less-secure-app password IMAP ended 14 Mar 2025** for Google ([Workspace](https://knowledge.workspace.google.com/admin/sync/transition-from-less-secure-apps-to-oauth)), and **Outlook.com basic auth ended 16 Sep 2024** ([heise](https://heise.de/-9767989)). **iCloud Mail has no third-party OAuth, only app-specific passwords** (max 25, all revoked on Apple Account password change) ([Apple](https://support.apple.com/en-us/102654)).
- [ ] **Gmail push needs a Cloud Pub/Sub topic and a server.** Google recommends polling for device apps ([Gmail push](https://developers.google.com/workspace/gmail/api/guides/push)). Email sync stays on-device in v1.
- [ ] **Gmail API quota:** 6,000 units/min per user, with `messages.get` at 20 units. Charges above 80M units/day per project are to be announced in 2026 ([quota](https://developers.google.com/workspace/gmail/api/reference/quota)). Not binding at personal scale.

**YouTube**

- [ ] **All YouTube OAuth scopes are sensitive**, including `youtube.readonly`, so public release needs verification: privacy policy on own domain, Search Console, demo video, typically 3–5 business days ([Google](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification); [Phyllo](https://www.getphyllo.com/post/youtube-oauth-scopes)). Subscribe and unsubscribe need the full `youtube` scope at **50 units** each.
- [ ] **Default quota is 10,000 units/day. `search.list` has had its own 100-calls/day bucket since 1 Jun 2026** ([revision history](https://developers.google.com/youtube/v3/revision_history); [quota](https://developers.google.com/youtube/v3/determine_quota_cost)). Channel suggestions must be frugal.
- [ ] **Watch Later and History have been unavailable through the API since Sept 2016** ([revision history](https://developers.google.com/youtube/v3/revision_history)). The unified queue is app-local, and "watched" is marked in the app.
- [ ] **No downloading, caching or offline playback. No background playback, no audio separation, no ad blocking, no overlays on the player.** **Non-authorised API data may be kept ≤30 days. Data is deleted within 7 days of in-app revocation**, and quota extensions need a compliance audit ([Developer Policies](https://developers.google.com/youtube/terms/developer-policies)).
- [ ] **Links must open in the YouTube app when it is installed.** Combined feeds must **clarify the difference** between YouTube and non-YouTube data, and metadata and thumbnails may not be altered ([policy guide](https://developers.google.com/youtube/terms/developer-policies-guide)).
- [ ] **Embedded player:** at least **200×200 px**, no overlays, and an HTTP Referer equal to the app's reverse-DNS ID. Since Nov 2025 iOS WKWebView embeds have failed with **error 153** without a proper Referer; the reliable fix is hosting the embed page on your own HTTPS domain ([RMF](https://developers.google.com/youtube/terms/required-minimum-functionality); [DEV](https://dev.to/davidvesely/fixing-youtube-error-153-in-ios-capacitor-apps-a-simple-proxy-solution-607)).
- [ ] **`captions.download` requires edit permission on the video** (200 units) ([docs](https://developers.google.com/youtube/v3/docs/captions/download)). No sanctioned way exists to get transcripts of other people's videos, so YouTube AI works from title, description and description chapters only.
- [ ] **Channel RSS feeds have been intermittently failing (404/500) since Dec 2025** ([Google forum](https://discuss.ai.google.dev/t/youtube-rss-feed-endpoint-returns-404-errors/113379)). Use RSS with an API fallback.

**Apple App Store and platform**

- [ ] **Guideline 5.2.3:** no saving, converting or downloading media from third-party sources such as YouTube. **5.2.2:** third-party use must be authorised. **4.2.2:** the app must not be primarily an aggregator or a collection of links. **4.5.1:** no scraping Apple sites ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- [ ] **Guideline 5.1.2(i) (revised 13 Nov 2025):** clearly disclose where personal data goes to third-party AI and **obtain explicit permission before sharing** ([TechCrunch](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai)). Use contextual, per-source consent, not a ToS clause.
- [ ] **EventKit has no read-only mode.** Reading events requires **full access**; write-only can't even read the app's own events, and Reminders is full-access only ([Apple](https://developer.apple.com/documentation/eventkit/accessing-the-event-store.md)). The permission prompt must justify full access.
- [ ] **Contact notes need the managed `contacts.notes` entitlement**, without which the app can't be publicly distributed ([Apple](https://developer.apple.com/documentation/contacts/cncontact/note.md)). Keep relationship notes in the app.
- [ ] **No API reads Apple Podcasts subscriptions.** MediaPlayer may not be used "to gather information about the user's audio content" ([Apple forums](https://developer.apple.com/forums/thread/719543)). Apple Podcasts has no OPML export on iOS. Onboard via OPML, search or a user-run Shortcut.
- [ ] **No API reads other apps' App Store subscriptions.** Apps "only receive transaction and subscription data associated with their bundle ID" ([Apple forums](https://developer.apple.com/forums/thread/681784)). The app can only deep-link to `apps.apple.com/account/subscriptions` and parse Apple's emailed receipts.
- [ ] **No iOS API reads Mail.app, iMessage, WhatsApp or call history.** MailKit is **macOS-only** ([MailKit](https://developer.apple.com/documentation/mailkit.md)). Relationship signals come from Contacts, calendars and connected mail.
- [ ] **Screen Time data cannot leave its sandboxed report extension** ([Apple](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport.md)). Pattern learning uses the app's own event log.
- [ ] **Background execution:** `BGAppRefreshTask` gets up to ~30 s at times the system chooses. **Silent pushes are throttled beyond 2–3 per hour** and are discarded if the app is force-quit. Background URLSession relaunches are rate-limited ([Apple](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app.md); [Apple](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app.md); [Apple](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background.md)). Time-based reminders are local notifications scheduled ahead, and externally triggered alerts need a server.
- [ ] **Live Activity remote updates and widget push reloads need your own APNs server** ([ActivityKit](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications.md); [WidgetKit](https://developer.apple.com/documentation/updates/widgetkit.md)).
- [ ] **CarPlay audio needs a requested entitlement** ([Apple](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements.md)).
- [ ] **SwiftData + CloudKit:** no unique constraints, all relationships optional, attributes optional or defaulted, and the **production schema is additive-only** ([Apple](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices.md)). `CKSyncEngine` leaves conflict resolution to the app ([Apple](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5.md)). Design the schema CloudKit-first from M0.
- [ ] **Siri AI is not available to EU users on iOS 27 / iPadOS 27**, so EU developers can't test it on iPhone. It *is* available on macOS 27 ([Apple Newsroom](https://apple.com/newsroom/2026/06/due-to-dma-siri-ai-delayed-in-eu-for-ios-27-and-ipados-27/)). App Intents, Shortcuts, Spotlight and widgets work everywhere.
- [ ] **Foundation Models:** the on-device context is **4,096 tokens per TN3193 but 8,192 on the OS 27 model** ([TN3193](https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md); [WWDC26](https://developer.apple.com/videos/play/wwdc2026/241)), so read `contextSize` at runtime. **The PCC model (32K) needs the Small Business Program, under 2M first-time downloads, a managed entitlement and daily limits** ([Apple](https://developer.apple.com/private-cloud-compute/)). Whether either is available on EU iPhones is unconfirmed.

**Claude API and self-hosting**

- [ ] **No EU data residency.** `inference_geo` is only `global` or `us`, and workspace data is stored in the US ([data residency](https://platform.claude.com/docs/en/manage-claude/data-residency)). Disclose this. The EU–US Data Privacy Framework survived the General Court (3 Sep 2025), but a CJEU appeal is pending ([WilmerHale](https://www.wilmerhale.com/en/insights/blogs/wilmerhale-privacy-and-cybersecurity-law/20251201-european-court-of-justice-to-review-challenge-to-eu-us-data-privacy-framework)).
- [ ] **No official Swift SDK.** `ClaudeForFoundationModels` is beta, OS 27+, has no batch, Files API or token counting, and labels `.apiKey` auth "development only" ([Anthropic](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models); [SDKs](https://platform.claude.com/docs/en/api/client-sdks)). Write a thin REST client for BYOK.
- [ ] **Batch requests are not ZDR-eligible and have 29-day retention** ([ZDR](https://platform.claude.com/docs/en/build-with-claude/zero-data-retention)). Never batch personal content. Use batch only for already-anonymised aggregates.
- [ ] **Ollama's Anthropic-compatible API lacks prompt caching, `tool_choice`, batch and token counting**, defaults to a **4,096-token context**, and doesn't validate API keys ([Ollama](https://docs.ollama.com/api/anthropic-compatibility.md); [FAQ](https://docs.ollama.com/faq)). **vLLM's `--api-key` leaves `/invocations` unauthenticated** ([vLLM](https://docs.vllm.ai/en/latest/cli/serve.html)). Use capability flags, raise `num_ctx`, and never expose servers publicly.

**Other**

- [ ] **Open banking is impractical for an individual in Ireland:** GoCardless/Nordigen closed sign-ups, and the alternatives need eIDAS certificates ([dev.to](https://dev.to/johnfrandsen/gocardless-bank-account-data-alternatives-what-to-use-when-signups-are-disabled-326d)).
- [ ] **Pocket Casts' iOS code is MPL-2.0**, a file-level copyleft: copied files stay MPL ([GitHub](https://github.com/Automattic/pocket-casts-ios)). Check compatibility with Eagar's licence before reusing files.

## A local-first architecture fits every constraint

The constraints point to one architecture. Mail and personal data are processed on the device or the Mac. User data syncs only through the CloudKit private database. A tiny push server handles external events and holds no personal content. AI escalates by data class rather than by convenience.

### Data and sync: CloudKit private database, designed additive from M0

For a single-user organiser, **SwiftData on the CloudKit private database** syncs across iPhone, iPad and Mac at no cost. Records count against the user's own iCloud quota and are invisible to the developer ([Apple](https://developer.apple.com/documentation/cloudkit/ckdatabase/scope/private.md)). Eagar has many entity types (accounts, mail metadata, commitments, trials, loans, people, episodes, videos, suggestions, ledger entries) and needs deduplication control, so the more robust option is a local store (SwiftData with `cloudKitDatabase: .none`, or GRDB) synced by **`CKSyncEngine`**. That costs more code but gives explicit conflict handling. Sensitive fields such as the style profile and privacy ledger can use CloudKit `encryptedValues`, keyed from iCloud Keychain, at the price of not being queryable and losing data if the user resets the encrypted-data key ([Apple](https://developer.apple.com/documentation/cloudkit/encrypting-user-data.md)). Raw email bodies should **not** sync at all. Each device fetches mail directly from the provider, and only derived items from `cloud-allowed` sources (a commitment, a trial, a lane decision) sync. Items derived from `local-only` sources (NCAD mail, the NCAD calendar, Canvas, cdbooking loans) follow the rules in the next subsection: each device fetches them from the original source, or reads them from the Mac over the local or Tailscale link. Only content-free state, if Mark allows it, goes through iCloud.

### Email: provider-native APIs, on-device sync, no developer server

Use the **Gmail REST API** (with `history.list` incremental sync) through GoogleSignIn-iOS or AppAuth, **Microsoft Graph or IMAP-OAuth** through MSAL for Outlook, and **MailCore2** for iCloud and other IMAP accounts ([MailCore2](https://github.com/MailCore/mailcore2); [GoogleSignIn](https://github.com/google/GoogleSignIn-iOS); [AppAuth](https://github.com/openid/AppAuth-iOS)). Apple's swift-nio-imap describes itself as "not ready to be used in production" ([GitHub](https://github.com/apple/swift-nio-imap)). Several of these libraries show maintenance-risk signals (hundreds of open issues), so check recent commit activity before committing. Mimestream proves a serverless direct-API Gmail client works on macOS, with tokens only on the device ([Mimestream](https://mimestream.com/)). On iOS, sync runs on app open and opportunistically in the background. On the Mac, a login item can poll continuously without iOS limits. The Mac therefore acts as the **"home base"**: it does heavy processing, then syncs derived results through CloudKit.

There are three Google distribution routes. For **Mark's own personal Gmail**, a Google Cloud project in Testing mode with himself as a test user is legitimate and exempt from verification, at the cost of re-consenting every seven days. Moving it to unverified production under the personal-use exception may avoid the 7-day expiry, which the docs imply but don't state, so test it. For **public App Store users**, the open-source-friendly route mirrors BYO Claude key: **each user supplies their own Google OAuth client ID**, making each user a personal-use developer. That adds friction but needs no verification. The alternative is full restricted-scope verification with a budget for possible CASA. For the **NCAD account**, use the NCAD-owned Internal client described above, or whichever route Mark's Windows app already uses, if IT has effectively permitted it.

**Access levels for a work account.** Mark's own NCAD account runs at the top level. The lower levels are the **rules-only policy mode** that a staff rollout starts from. (1) **No access**: a scheduled "check work mail" slot in the brief plus a deep link to the IT-approved client. (2) **Native notifications**: rely on the Gmail app's or Apple Mail's own VIP and priority settings, with no third-party access. (3) **Rules-only via an IT-approved scope**, for example `gmail.metadata` with a deterministic scorer (VIP senders, domains, Gmail's own labels). IT must still trust Eagar's client ID, because `gmail.metadata` is restricted. (4) A **Mac-only MailKit action handler** that flags or colours mail in Apple Mail by sender rules. MailKit's `MEMessage` exposes raw message content ([Apple](https://developer.apple.com/documentation/mailkit/memessage.md)), so this level needs the same approval. (5) **Full local processing**: bodies downloaded to the Mac and the device, local AI only, `local-only` boundary, approve-before-send. This is Mark's configuration. **Gmail's own server-side filters** set in the web UI are IT-neutral pre-sorting that every level can deep-link into.

**Work-mail sync without the cloud.** Under the `local-only` boundary, NCAD message bodies and AI outputs derived from them (drafts, summaries, extracted commitments) **do not sync through CloudKit**. iCloud is a cloud service, even when encrypted. Each device fetches work mail directly from Google, which is already the mail's host, so no new party is added. The Mac does the heavy processing. iPhone and iPad reach the Mac's results over a **direct local network or Tailscale link** ([Tailscale](https://tailscale.com/pricing)), or compute them with the on-device model. Only non-content state (a lane decision, a "done" flag keyed to a message ID) may sync through CloudKit, and even that should be a setting.

### Notifications and the tiny push server

Background budgets make on-device polling unreliable for anything driven by *external* changes: new episodes, new uploads, booking webhooks. Overcast, Pocket Casts and Castro all poll on servers ([marco.org](https://marco.org/2014/02/23/the-value-of-background-fetch); [Pocket Casts forum](https://forums.pocketcasts.com/forums/topic/some-feedback-for-the-devs-regarding-episode-update-delays/)). The cheapest always-on option is a **Cloudflare Worker** with Cron Triggers, Durable Objects or D1, and an APNs client. The paid plan starts at **$5/month**, and an hourly cron example costs about $6.99/month ([Cloudflare](https://developers.cloudflare.com/workers/platform/pricing/index.md); [cloudflare-apns2](https://jsr.io/@fivesheepco/cloudflare-apns2)). A container on Mark's own hardware is the self-hosted alternative. The server holds only **feed URLs, ETags, last-seen IDs and APNs device tokens**. It never holds OAuth tokens or mail, which keeps it outside Google's CASA trigger. **For `local-only` sources (the cdbooking feed and webhook, the Canvas feed), a third-party cloud poller would itself move college data off his devices.** So either the Mac does the polling and the cloud server only relays content-free "something changed" pushes, or the poller runs on his own hardware.

The "notify when downloaded" flow is: poll feeds every 10–15 minutes with conditional GET (WebSub/podping where hosts support it) → a background push wakes the app → **one background URLSession** downloads the enclosure → on `didFinishDownloadingTo`, post a **local** "Downloaded and ready" notification. When silent pushes are throttled or the app was force-quit, fall back to an alert push ("New episode available"). The client-only path (BGAppRefresh plus fetch on open) remains for self-hosters with no server. Deadlines, return dates, trial ends and birthdays need no server: they are **local notifications scheduled at sync time**.

### AI routing by data class, not by convenience

Define one `LLMProvider` protocol with capability flags (caching, `tool_choice`, strict schema, batch, max context, cost, **data locality**, reachability). Implement it for **Apple on-device**, **Apple PCC**, **Anthropic REST (BYOK)**, and a generic **Anthropic-compatible base URL**. The last one covers Ollama or MLX servers on the Mac and vLLM behind Meitheal on the DGX Sparks: both vLLM and Ollama now expose `/v1/messages` ([vLLM](https://docs.vllm.ai/en/latest/serving/online_serving/); [Ollama](https://docs.ollama.com/api/anthropic-compatibility.md)). On OS 27, each provider can also be wrapped as a Foundation Models `LanguageModel`, so `@Generable` types and Dynamic Profiles are shared across tiers ([Apple](https://developer.apple.com/documentation/updates/foundationmodels.md)).

Routing is set by **data class**:

| Data class | Allowed tiers | Example tasks |
|---|---|---|
| NCAD mail, NCAD calendar, Canvas, cdbooking (`local-only`) | iPhone/iPad on-device model; **Mac MLX/Ollama**. Never Claude or PCC. | Triage, drafts, commitment extraction, style analysis, Canvas deadlines |
| Any work account in rules-only policy mode (staff rollout) | **None**; deterministic rules only | Lane scoring by sender/domain/label |
| Raw personal email bodies, sent mail | iPhone on-device; **Mac local model**; later DGX via tailnet | Commitment extraction, style analysis, trial/receipt parsing |
| Derived, minimised items from `cloud-allowed` sources (a deadline, a trial row, a summary) | Above, plus Claude with consent | Daily brief composition, weekly review |
| Items derived from `local-only` sources (an NCAD commitment, a Canvas deadline, a loan) | Local tiers only; the boundary is inherited by everything derived from the source | Brief sections composed locally, then merged with cloud-phrased sections |
| Approved About-me profile | Claude as system context | Tone and planning guidance |
| Public metadata (podcast transcripts, YouTube titles/descriptions) | Any tier | Summaries, de-duplication, channel suggestions |

The DGX Sparks are reached over a **Tailscale tailnet** with `tailscale serve` (tailnet-only HTTPS, never `funnel`) plus an app-level key ([Open WebUI/Tailscale](https://docs.openwebui.com/ecosystem/computer/phone-and-remote/tailscale.md)). Tailscale Personal is free for non-commercial use ([Tailscale](https://tailscale.com/pricing)). Meitheal should front vLLM so its unauthenticated endpoints are never exposed. One caveat for the PRD: the Sparks belong to NCAD's estate, so using them for Mark's *personal* data mixes personal and institutional infrastructure. Whether they count as "his local devices" for NCAD data under his own rule is also undecided. Open question 11 covers both. Until it is answered, the Sparks tier is excluded from the `local-only` path.

**Claude costs are small at personal scale.** At **Haiku 5.5's $0.10/$0.50 per million tokens** (prompts ≤100K tokens; $0.50/$2.50 above) and **Sonnet 5.5's $2/$10**, with cache hits at 0.05× for Sonnet ([pricing](https://platform.claude.com/docs/en/about-claude/pricing)), a daily brief of ~20K input and ~1.5K output tokens on Sonnet costs about **$0.055**. Haiku triage of 300 personal messages at ~800 tokens each costs about **$0.03**. That puts the month well under **$5** (my arithmetic; the 4.7+ tokenizer adds ~30% tokens). The BYOK key belongs in the Keychain, this-device-only. The app should guide the user to create a **dedicated Claude workspace with a monthly spend limit and an expiring key** ([workspaces](https://platform.claude.com/docs/en/manage-claude/workspaces); [authentication](https://platform.claude.com/docs/en/manage-claude/authentication)) and show per-call cost from `usage`.

### The local learning pipeline on the 48 GB Mac

The pipeline runs only on the Mac, in a `BGProcessingTask`-style overnight job or a user-started run. **Ingest** downloads Mark's sent mail plus enough thread context to interpret replies into an encrypted, app-local working store. **Strip** removes quoted text, signatures of others, attachments and third-party named entities before any model sees the text, because Mark's own replies still mention other people. **Analyse** uses a 20–30B-class local model through MLX or Ollama. Raise Ollama's default 4,096-token context, which truncates threads silently ([Ollama FAQ](https://docs.ollama.com/faq)). The model produces structured, `@Generable`-style observations: greeting and sign-off habits, typical length by recipient class, response latency by account and sender class, time-of-day patterns, phrasing for declines and commitments, and recurring workflows. **Aggregate** turns the observations into a profile of categories and statistics, never quotes or names ("replies to students within 4 working hours, 60–120 words, signs off 'Thanks, M'"). **Purge** deletes the downloaded working copies and logs the deletion in the privacy ledger. **Review** shows Mark the profile as a card with a diff against the previous version. **Only an approved version** is ever sent to Claude, as system-prompt context.

This fits Google's rule that Workspace-API data may feed only "that specific user's personalized model" ([Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy)), and Apple's 5.1.2(i) consent requirement. The pipeline is **on for Mark's NCAD account** and runs entirely on the Mac. A per-account switch keeps it off by default for any other work account, so a staff rollout can enable it only where the institution has approved it.

**Resolved (Mark, 25 Oct 2026):** the cloud profile may mix signals learned from NCAD mail with those learned from personal mail. Mark's rule allows the profile to leave the device because it describes him and is non-identifying. Each line still carries a "work-derived" or "personal-derived" tag for provenance and the DPIA, and each line still needs his individual approval and must pass the non-identifying lint before it is sent.

### Calendar, contacts, bookings and media sources

**Calendar** needs EventKit full access for iCloud, Exchange and subscribed calendars, plus optional Google and Microsoft calendar APIs. **Contacts** supply birthdays and dates through iOS 18's limited-access picker or `ContactAccessButton` ([TechCrunch](https://techcrunch.com/2024/06/12/ios-18-cracks-down-on-apps-asking-for-full-address-book-access)). **Bookings** sit behind a `BookingSource` protocol with two adapters. The first is a **cdbooking adapter**: a per-user secret iCal feed (`/ical/<token>.ics`, which EventKit can also subscribe to natively), a token-authenticated `GET /api/me/bookings?since=` JSON endpoint, and an outbound webhook on approve, checkout and return-due that the push server converts to APNs. The second is a **native-replacement adapter** reading the replacement app's CloudKit data. Multi-user college data will likely live in the replacement's public database or a custom backend. Cross-app CloudKit container access requires both apps signed by the same team with the container in both entitlements, which is unverified. The safest contract is for **the replacement app to publish the same per-user iCal/JSON/webhook surface**, so Eagar needs no change at the switch-over. Confirmation-email parsing on the device is the fallback.

**Podcasts** use Podcast Index (free, keyed) and the iTunes Search API (~20 calls/min) for search, with RSS as the source of truth ([Podcast Index](https://podcastindex.org/); [Apple](https://performance-partners.apple.com/search-api)). The app parses Podcasting 2.0 `transcript`, `chapters`, `funding` and `person` tags ([namespace](https://github.com/Podcastindex-org/podcast-namespace)). Playback uses AVAudioEngine for speed, silence trimming and voice boost, MPRemoteCommandCenter, and CarPlay once the entitlement is granted. When a feed has no transcript, **SpeechAnalyzer/SpeechTranscriber** (iOS/macOS 26, on-device, long-form, timestamped) generates one ([WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/)).

**YouTube** onboarding works with no OAuth at all: import Takeout `subscriptions.csv` ([Invidious docs](https://docs.invidious.io/export-youtube-subscriptions/)), then use channel Atom feeds (the `UULF` long-form playlist ID excludes most Shorts) ([zegnat](https://zegnat.bearblog.dev/the-rss-world-of-youtube/)). Enrich with `videos.list` at 1 unit per 50 IDs for duration and live status, and fall back to `playlistItems.list` when RSS fails. Hourly refresh of 200 channels costs roughly 4,800 units/day, within quota for one user ([quota](https://developers.google.com/youtube/v3/determine_quota_cost)). Subscription management (subscribe/unsubscribe at 50 units, full scope) is a later milestone. In v1 it opens YouTube. Playback deep-links to the YouTube app on iPhone, with an optional compliant inline embed on iPad and Mac.

### Google Calendar and Canvas add little complexity if fed through EventKit and iCal

Mark wants both only if they don't add much complexity. On the evidence, both clear that bar at a basic level.

**Google Calendar is low complexity via EventKit.** Once Mark adds his Google accounts to Apple's Calendar accounts (CalDAV sync), their calendars appear in EventKit alongside iCloud and Exchange. Eagar then reads and writes them through the same full-access EventKit path it needs anyway ([Apple EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store.md)). That means no Google Calendar API, no extra OAuth scopes and no verification. Google's account-level CalDAV sync is general knowledge, not covered by the notes, so confirm it. There is one caveat to test on the NCAD tenant: Apple's account sign-in uses Apple's own Google OAuth client, and a Workspace admin can allow or block clients by ID. The notes confirm this for IMAP, where Apple Mail has predefined client IDs ([Workspace IMAP](https://knowledge.workspace.google.com/admin/sync/turn-pop-and-imap-on-or-off-for-users)). Calendar sync on the NCAD account is probably already in use, but verify it. The **NCAD calendar is `local-only`**. For Mark, local AI may use it for planning. Deterministic logic (free/busy, conflicts, return-due clashes, breakpoint detection for the brief) always works, including in rules-only mode for other staff. Calling the Google Calendar API directly is a later option, only if EventKit proves insufficient (for example, for attendee response details or Google-specific fields).

**Canvas is low complexity for v1 via its iCal feed, moderate for more.** Canvas gives each user a calendar feed URL for assignments and events, which is read-only. Eagar can ingest it through the **same per-user feed pipeline as the cdbooking integration**, polled by the app or the Mac. A cloud push server may only relay content-free change hints. Richer data (To Do items, the grading queue, announcements) needs the **Canvas REST API with a personal access token**. That is fine for Mark alone, but institutions can restrict token creation, and a staff rollout would need an institution-issued developer key (OAuth). These Canvas details are general knowledge and absent from the research notes, so confirm them against NCAD's Canvas instance and admin settings. Canvas content involving students is **NCAD-controlled personal data**, so it is `local-only` for Mark and rules-only for anyone without institutional approval.

**Recommendation.** Google Calendar via EventKit in an early milestone (M1). The Canvas iCal feed early, sharing the cdbooking feed adapter (M2). The Canvas REST API as an optional later milestone (the PRD places it in M6).

## Human-in-the-loop email: building on Mark's Windows app

Mark's Windows app already proves the core idea on his work account. It downloads mail locally, and **no email leaves without his specific permission**. Eagar treats **approve-before-send as a binding principle** across every account and every automation path, including AI drafts, playbooks, rules and App Intents. The research supports this. An email is the most irreversible action the app can take, and Horvitz's principles centre on **minimising the cost of poor guesses** and using dialog when uncertain ([Horvitz CHI '99](https://www.erichorvitz.com/chi99horvitz.pdf)). The better commercial clients already hold this line: Spark's AI drafts "are never auto-sent" ([Layer3Labs](https://www.layer3labs.io/guides/spark-email-review)). Superhuman's Auto Drafts is criticised for drafting replies to newsletters and notifications ([Fast.io](https://fast.io/resources/superhuman-ai-review-2026/)), which shows the cost of drafting without judgement. The design goal is not to remove Mark from the loop. It is to make each pass through the loop **cheaper**, with fewer, better-timed and better-explained approvals, and to collect evidence along the way.

### Graded autonomy is earned per category, from evidence

Each **action category** has an autonomy level. Categories are things like "acknowledge receipt", "equipment-booking answer", "meeting-time reply" or "student extension request".

| Level | Behaviour | How a category gets there |
|---|---|---|
| L0 — Rules only | No drafting; deterministic sorting only | Default for any account without approved AI (staff rollout) |
| L1 — Draft on request | Mark taps "Draft" on a thread | Default for new categories |
| L2 — Proactive draft to queue | Eagar drafts and places it in the approval queue | Category has a playbook or enough history |
| L3 — Send after delay, with undo | Fast-path approval (one gesture plus authentication per message), then the approved message is held locally for a delay (e.g. 10 minutes, or until the next brief), cancellable. *As first drafted this row said "approved-by-default send"; the PRD (BD-12) redefines L3 so it never sends a message Mark has not individually approved, because approve-before-send is absolute.* | **Explicit per-category opt-in**, and only after evidence: many approvals (e.g. ≥30) with **edit distance staying near zero** (e.g. median normalised edit ≤5%) and no pre-send guard triggers |

**Demotion is automatic.** A heavily edited draft, an undo, a guard trigger or a recipient complaint drops the category back to L2. Levels never rise on their own; Eagar only *suggests* a promotion through the confidence ladder, with the evidence attached. **L3 is off for the NCAD account.** Per-message approval there is both Mark's stated principle and the pilot's main evidence, so Eagar should keep it. (Mark has since confirmed that approve-before-send is absolute on every account, so the PRD never lets a standing per-category permission send a message he has not individually approved.) For any other staff member, L3 on a work account is never available without institutional sign-off. The delayed send is held by Eagar on the device or the Mac, not handed to the mail server early. The holding device must be awake when the delay ends. On iOS that is unreliable in the background ([Apple](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app.md)), so L3 sends should be held on the Mac or released at the next foreground session.

### Edit distance is the best local learning signal

Each approved draft produces a pair: what Eagar proposed and what Mark actually sent. **How much he changes a draft is the best signal Eagar has.** Lightly edited drafts confirm the profile. **Heavily rewritten drafts teach the most**, because they show exactly where the style model or playbook was wrong. Eagar computes a word-level normalised edit distance and classifies edits locally (tone softened, fact added, promise removed, greeting changed, shortened). It feeds three places: the About-me profile ("shortens drafts to students by ~40%"), the playbook that produced the draft, and the category's autonomy evidence. Following Mark's delete-the-source rule, the text pairs are kept only for a short rolling window on the Mac, distilled into profile and playbook updates, then purged, with the purge logged. A later option is a small on-Mac adapter fine-tune of the local model on these pairs (MLX supports LoRA fine-tuning; general knowledge, to confirm). It must stay local and per-user.

A **shadow mode** strengthens this from day one. For categories Mark hasn't enabled, Eagar silently drafts a reply, never shows it, and compares it with what he writes himself. That measures draft quality *before* asking him to review anything, and gives a fair baseline for "time saved" in the pilot.

### The approval view shows what he is committing to

Before Mark approves, the draft is annotated, not just displayed. **Commitments are highlighted**: dates and deadlines ("by Friday"), promises ("I'll send", "I'll check with"), money, attachments promised or included, and actions on his behalf. **Recipient risk is flagged**: addresses outside `ncad.ie`, reply-all to large lists, recipients he has never written to before, and a greeting name that doesn't match the recipient. Each draft also shows its **provenance**: which local model, which playbook version and which profile version produced it, and that the content stayed on-device (from the privacy ledger). **"Approve and track"** sends the message and turns its commitments into deadlines, linking directly to commitment extraction (novel feature 4).

### Pre-send guards catch the classic mistakes

Guards run locally on every outgoing message, approved or not, and never call the cloud for NCAD content.

| Guard | Trigger | Action |
|---|---|---|
| Wrong recipient | Recipient similar to a frequent contact but different; name in greeting ≠ recipient | Block until confirmed |
| Missing attachment | Text mentions "attached", "enclosed" or a file name, but nothing is attached | Block until resolved |
| External domain | Any recipient outside `ncad.ie` on a work thread | Highlight; confirm |
| Large reply-all | Reply-all above a threshold, or to a list address | Suggest reply-to-sender |
| Late-night send | Composed outside configured hours | Offer "send at 08:30" (held locally) |
| Personal data | Patterns such as student numbers (NCAD format to confirm), PPS numbers, dates of birth, health terms | Warn; suggest removal or a secure channel |
| Tone | Local model flags sharpness or a mismatch with the recipient class in the profile | Show the flagged phrases; never blocks |
| **Cross-account leak** | Replying to or forwarding an NCAD thread **from a personal account**, or adding a personal address to a work thread | **Block**: it would move college data across the boundary |

The cross-account guard is Eagar's own addition. It enforces Mark's data boundary at the moment it is most likely to be broken by accident.

### Approvals happen in batches, at natural breaks, on whichever device is at hand

Drafts accumulate in an **approval queue** that surfaces at breakpoints: the end of a class or meeting, the morning brief, a gap of 15 minutes or more. Interruptions at breakpoints cost less and get faster responses ([Iqbal & Bailey 2008](https://www.interruptions.net/literature/Iqbal-CHI08.pdf)). Perceived disruption sharply lowers acceptance ([Mehrotra et al. 2016](https://discovery.ucl.ac.uk/1502364/1/CHI16.pdf)). On iPhone the queue is a **swipe-to-approve, edit or reject** stack. Reject asks for a one-tap reason, which feeds the ledger and the scorer. **Face ID confirms each send** (LocalAuthentication; general knowledge). On **Apple Watch**, only one-line replies in categories Mark has marked "Watch-OK" can be approved. Anything longer says "approve on iPhone". The Watch has no Face ID, so it relies on wrist detection and passcode. The App Intents framework now provides **`OwnershipProvidingEntity` (confirmation before sensitive actions)** and **`UndoableIntent`** ([Apple App Intents updates](https://developer.apple.com/documentation/updates/appintents.md)). These let a "Send approved replies" Shortcut or Siri action keep the same confirmation and undo semantics, so no automation path bypasses approval.

**For the NCAD account, approval traffic stays on Mark's devices.** Drafts are generated on the Mac (or on-device on iPhone for short replies). They reach the iPhone over a **direct local network or Tailscale link** to the Mac, never through CloudKit, a push payload or any other cloud relay. Tailscale traffic is end-to-end encrypted WireGuard, even when relayed (general knowledge). Mark should confirm that this satisfies his "no college data leaves my devices" rule. When the Mac is unreachable, the iPhone can still fetch the thread from Gmail and draft with the on-device model. Push notifications for NCAD approvals carry no content ("3 replies ready to approve").

### Reply playbooks turn recurring requests into approved templates

Many of Mark's messages answer recurring requests: equipment-booking queries, room requests, student extension requests, kit-return reminders. A **playbook** captures one request type. It holds a trigger description, the facts it needs, a template in his voice, the guards that apply, and any **decision input that only Mark can provide**. An extension request playbook drafts "granted to [date]" or "please ask your HoD" only after he picks the outcome; Eagar never decides. Mark approves each playbook once. Every draft it produces still goes through the approval queue, and its edit distance is tracked per playbook version. Playbooks can pull local facts. The equipment-booking playbook can read availability from the cdbooking feed or the native replacement, so the answer is correct, not just polite. Playbooks are the natural place for autonomy to grow: a stable, low-edit playbook is the strongest L3 candidate on personal accounts.

### Threads have explicit states, with follow-ups and delegation drafted

Every thread is in one state: **Needs reply**, **Waiting** (on someone else), **Delegated**, or **Done**. This extends HEY's Reply Later and Set Aside ([HEY](https://www.hey.com/features/)) across all accounts. When a Waiting thread passes the recipient's expected latency (learned from the profile), Eagar drafts a polite follow-up into the queue (novel feature 5). **Delegation drafts** forward the thread to the right colleague with a short, locally generated summary and the ask. For NCAD threads, the summary is generated locally, the forward stays within `ncad.ie` unless he confirms otherwise, and the thread moves to Delegated with a check-back date.

### The approval ledger doubles as pilot evidence

Every draft, approval, edit, rejection, guard trigger, delayed send and undo is logged in an **approval ledger**. It sits alongside the privacy ledger and is exportable as **content-free metrics**: drafts generated per category, approval rate, edit distance over time, rejection reasons, guard catches, sends undone, and estimated time saved (approval time vs shadow-mode baseline compose time, labelled as an estimate). Because it contains no message text, the export can go to NCAD IT and the DPO as **evidence for extending Eagar beyond Mark**. It shows what the AI did, how often a human corrected it, and that nothing was sent without approval.

### Dry-run mode and a global kill switch

**Dry-run mode** runs the whole pipeline (drafting, guards, approvals) but replaces the send call with a "would have sent" ledger entry. It is how Eagar starts on any new account, and how a new staff member would start in a rollout. A **global kill switch** cancels all held sends, stops all drafting and all AI processing, and optionally signs out every mail account. It is reachable from Settings, a **Control Center control** (`ControlWidgetToggle`, available on iOS and macOS ([Apple WidgetKit](https://developer.apple.com/documentation/updates/widgetkit.md))), and a Shortcut. Each use is logged.

### A shared rules format lets the Windows and Apple apps interoperate

The Windows app and Eagar should share a **documented, versioned, plain-file format**: JSON or YAML with a published JSON Schema in the open-source repo. It covers lanes and sender rules, playbooks, guard configuration, per-category autonomy grants, and the approval-ledger export schema. Mark could then author a playbook once and use it on both platforms, and compare evidence across both clients. This also matters for a **mixed Windows/Mac staff rollout**, where IT would want one policy artefact, not two. Rule files are configuration, but they can contain colleagues' addresses, so for NCAD they move between machines over the same local or Tailscale path, or a folder Mark controls, not a consumer cloud. The format should be designed in M0, so the Windows app can adopt it incrementally.

**The route the Windows app uses to reach work mail is not yet known.** It might be IMAP with OAuth, the Gmail API with his own client ID, Outlook or Exchange, or something else. That route decides how much code and configuration are reusable. It also shows **what NCAD IT has already effectively permitted**: if it already works for his account, Eagar can follow the same route, or cite it in the allowlisting request. This is open question 1 below.

## Novel features and solutions

These eighteen features are where Eagar goes beyond its competitors. Each is tied to research evidence and checked against the constraints above.

### 1. Per-account priority lanes with data boundaries, and a rules-only lane

**What it is.** Every mail account is a *lane* with its own weight, schedule, **data boundary** (`local-only` or `cloud-allowed`) and processing class (`rules-only`, `local AI`, `cloud AI`). Mark's configuration: "NCAD — local AI, local-only", "Personal Gmail — cloud AI allowed", "Company — cloud AI allowed", "iCloud — low lane". A message's priority combines lane weight, sender rules and AI classification where the lane permits it. The lane badge shows *why* a message ranked where it did. A boundary icon shows where the message may be processed: a house for local-only, a cloud for cloud-allowed, and a lock for "rules only — no AI" for staff whose institution hasn't approved AI.

**Why it matters.** No surveyed client prioritises by source account, and none offers per-account AI boundaries. Mehrotra et al. found the **sender relationship strongly affects response**, and that each one-point rise in perceived disruption multiplied acceptance odds by **0.581** ([CHI 2016](https://discovery.ucl.ac.uk/1502364/1/CHI16.pdf)). Account of origin is a cheap, reliable proxy for both. The 2026 failures of AI-only prioritisation (Notion Mail, Copilot priority view) argue for rules as the foundation.

**Feasibility.** High. Rules need no AI. The boundary is enforced in the AI gateway: a `local-only` item cannot be routed to a provider whose data locality is cloud. A rules-only lane's data access is limited to whatever the institution permits (levels 1–4 above). Lanes can also be tied to Focus through `SetFocusFilterIntent`, so a Work Focus hides personal lanes and vice versa ([Apple Focus](https://developer.apple.com/documentation/appintents/focus.md)).

### 2. One brief at natural breaks instead of device-checking

**What it is.** A single brief replaces the habit of opening several apps. It covers today's commitments, due loans, trials about to bill, lane-ranked mail, who to reach out to, and a curated media slice. The default is a morning brief, with optional midday and end-of-day briefs. Delivery is **timed to breakpoints**: the end of a calendar event, a gap of 15 minutes or more, app open, or the configured slot. Every item is actionable (reply, snooze, return, cancel, queue).

**Why it matters.** Iqbal & Bailey found that deferring notifications to task breakpoints **reduced frustration and sped reaction to relevant notifications (~3.07 s vs ~4.08 s), at a mean deferral of only ~89 s**. General notifications suited coarse breakpoints ([CHI 2008](https://www.interruptions.net/literature/Iqbal-CHI08.pdf)). OpenAI's retirement of Pulse led to the lesson that proactive features work when "personalised, action-oriented, and steerable" ([Digit](https://www.digit.in/news/general/openai-is-retiring-chatgpt-pulse-and-replacing-it-with-scheduled-tasks-here-is-why.html/amp/)). Sunsama shows that a ritual which takes too long gets skipped ([Dupple](https://dupple.com/learn/best-ai-scheduling-assistants)). The brief should take under two minutes.

**Feasibility.** High. Calendar breakpoints come from EventKit. Delivery is a local notification at `passive` or `active` interruption level, with `timeSensitive` reserved for genuine deadlines ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel.md)). Composition runs on the Mac or device. Claude may phrase minimised items from `cloud-allowed` sources only; NCAD, Canvas and booking items are phrased locally. A home-screen widget mirrors the brief; push-driven widget reloads need the server.

### 3. Confidence ladder with a suggestion ledger

**What it is.** Every proactive suggestion carries a confidence score and passes through Horvitz's thresholds. Below p1, Eagar **does nothing**. Between p1 and p2 it **asks**, passively, in the brief or a suggestions list. Above p2 it **acts**, but only for reversible actions the user has whitelisted, with undo. **Thresholds rise when Mark is focused**: in a meeting, in a Focus mode, or teaching. Each suggestion goes into a **ledger** with its trigger, evidence, confidence, outcome (accepted, edited, dismissed with reason, ignored) and timestamp. Outcomes feed the scorer, and a daily cap limits prompts.

**Why it matters.** Horvitz's mixed-initiative principles call for weighing expected benefit against interruption cost, using dialog to resolve uncertainty, minimising the cost of poor guesses, scoping precision to uncertainty, and raising thresholds under attention load ([CHI '99](https://www.erichorvitz.com/chi99horvitz.pdf)). Mehrotra's dismissal reasons ("not urgent" 43%, "not important" 41%, "not useful" 38%) map directly onto one-tap dismissal reasons ([CHI 2016](https://discovery.ucl.ac.uk/1502364/1/CHI16.pdf)). Amershi et al.'s guidelines ask for explainability and learning over time ([MSR](https://www.microsoft.com/research/project/guidelines-for-human-ai-interaction/)). The ledger provides both through "why am I seeing this".

**Feasibility.** High. The scorer can start as Bayesian heuristics over a local append-only event log and graduate to on-device logistic regression or boosted trees trained overnight in `BGProcessingTask` ([Apple](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app.md)). Donating App Intents lets the OS learn too ([Apple](https://developer.apple.com/documentation/appintents/donating-your-apps-data-and-actions-to-the-system.md)).

### 4. Commitment extraction from his own sent mail

**What it is.** The local model scans Mark's *sent* messages for promises ("I'll send it Friday", "will have the kit list to you after the break") and proposes them as deadlines with the date resolved, the recipient, and a link back to the thread. One tap confirms the deadline into the plan or Reminders.

**Why it matters.** Todoist's Email Assist and Apple's share-sheet suggested reminders show demand for turning mail into tasks, but both need a manual trigger ([MakerStack](https://makerstack.co/reviews/todoist-review/); [Apple](https://support.apple.com/en-ie/124025)). Commitments a person *made* are the ones most often forgotten, because no inbound message reminds them.

**Feasibility.** High. This is short-text extraction, well within on-device Foundation Models (with `@Generable`, a fresh session per message, and the context budget per TN3193) or the Mac model. It runs locally on every account, which makes it **available on Mark's NCAD account**, where most of his commitments probably sit.

### 5. "Waiting for reply" tracker

**What it is.** Sent messages that ask a question or request something, and haven't been answered after a per-recipient expected latency, appear in a "Waiting on" list. Eagar offers a nudge draft written in Mark's style, which he approves before sending.

**Why it matters.** HEY's Reply Later and Set Aside show the value of explicit follow-up states ([HEY](https://www.hey.com/features/)). Superhuman users credit follow-up automation with large time savings, though that claim is vendor-reported ([Fast.io](https://fast.io/resources/superhuman-ai-review-2026/)). The expected latency per recipient class comes straight from the learned profile, which ties features 4, 5 and 11 together.

**Feasibility.** High. Thread-reply detection needs only headers (In-Reply-To/References). The "is this a request?" classifier is local. Sending a nudge needs the `gmail.send` scope (sensitive) or SMTP ([Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)). Nudges go through the approval queue like every other draft (see the human-in-the-loop section).

### 6. Borrowing returns checked against the calendar

**What it is.** Each cdbooking loan carries a due time. Eagar checks it against Mark's calendar and timetable. If the return falls while he's teaching, in a meeting or off-site, it proposes an earlier return slot near the returns desk or asks for an extension through the booking system. The return also appears as a Live Activity on the due day.

**Why it matters.** No planner ingests booking-system loans, so this is a gap no competitor fills (see planners table). Missed returns hurt other students' bookings, a real cost in a shared-equipment college.

**Feasibility.** High once the per-user feed exists. Mark is master admin and can add it. Conflict checking is local. Return reminders are local notifications. Webhook-driven changes (an approved extension) need the push server, and Live Activity remote updates need APNs ([Apple](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications.md)). The same contract carries over to the native replacement.

### 7. Free-trial detection with cancel-by dates

**What it is.** A local classifier flags trial-start confirmations, "your trial ends in 3 days" notices, App Store receipts and price-change emails. It extracts service, price, renewal date and cancellation path, then creates a tracked item with a **cancel-by date set a safe margin before billing**, plus a deep link to the cancel page or `apps.apple.com/account/subscriptions`. A share-sheet and screenshot path (OCR via Vision, or Foundation Models' `OCRTool` on OS 27) covers trials without emails.

**Why it matters.** Trial-billing traps are among the most common complaints about the AI planners themselves, Motion and Akiflow included ([Carly](https://www.usecarly.com/blog/akiflow-review/); [Kimola](https://kimola.com/reports/unlock-task-management-success-with-our-in-depth-analysis-app-store-us-151020)). TrialGuard needs a photo, Bobby is manual, and Irish bank feeds are out of reach. **Apple offers no API to read App Store subscriptions** ([Apple forums](https://developer.apple.com/forums/thread/681784)), so the inbox is the only automatic source.

**Feasibility.** High on personal accounts. Extraction is local, and reminders are local notifications. The app links out to cancel and can't cancel itself.

### 8. Relationship nudges within a weekly social-capacity budget

**What it is.** Mark sets a weekly capacity (for example, three catch-ups). Eagar infers "last interaction" from calendar events with attendees, email to and from the person on personal lanes, and manual check-ins, then proposes nudges only up to that budget. It places them in actual free slots ("Thursday evening is free; Aoife: 7 weeks"), randomises them within cadence, and respects weekday preferences. Birthdays come from Contacts.

**Why it matters.** Bond's "can you cope this week?" total and CatchUp's randomised timing were built to stop keep-in-touch apps from over-committing people ([TapSmart](https://www.tapsmart.com/features/catchup-apps-roundup/?amp=1)). Mesh and Dex automate signals but are networking tools, and several PRMs died in 2026 ([Dex list](https://getdex.com/blog/personal-crm-list/)). Putting nudges inside the planner is the gap.

**Feasibility.** Medium-high. iOS exposes no iMessage, WhatsApp or call history, so signals are partial. Manual "we talked" logging and an optional Mac-only Messages import (Full Disk Access, likely outside the sandbox, so excluded from the App Store build) fill the gap. Relationship notes live in Eagar, because contact notes need a managed entitlement ([Apple](https://developer.apple.com/documentation/contacts/cncontact/note.md)). Colleagues found through NCAD mail are `local-only` signals, and keep-in-touch is mainly about friends, so the work lane is opt-in here.

### 9. Attention budget and "backlog bankruptcy" across podcasts and YouTube

**What it is.** The podcast and YouTube backlogs share one **attention budget**: minutes per day or week that Mark is willing to spend. New items land in a Castro-style **Inbox**, and only the top items that fit the budget are promoted to the **Queue**. The total duration is always visible, and the brief offers "today's 45 minutes". When the backlog exceeds, say, three weeks of budget, Eagar proposes **backlog bankruptcy**: archive everything older than N days except starred items, in one reversible action.

**Why it matters.** Castro's Inbox/Queue triage and Pocket Casts' Smart Playlists ("Quick Listen" under 25 minutes) are the most-praised time-savers in the category ([castro.fm](https://castro.fm/); [Pocket Casts](https://blog.pocketcasts.com/2025/11/24/playlists-a-new-way-to-organize-your-listening/)). An ever-growing backlog becomes guilt that drives repeated checking, which is the opposite of the app's goal.

**Feasibility.** High. Durations come from RSS enclosures and `videos.list`. The budget is local logic. YouTube items stay app-local because Watch Later can't be read or synced ([revision history](https://developers.google.com/youtube/v3/revision_history)).

### 10. Cross-media de-duplication into story clusters

**What it is.** When the same interview, launch or topic appears as a podcast episode and as several YouTube videos, Eagar groups them into one **story cluster** and suggests watching or listening to just one. Podcast transcripts can be compared in full. YouTube items are compared on title, description and description chapters only. YouTube items stay visibly labelled and unmodified inside the cluster.

**Why it matters.** No competitor de-duplicates across media. YouTube's policy requires "clarifying the difference" when combining YouTube data with other sources, and forbids altering metadata ([policy guide](https://developers.google.com/youtube/terms/developer-policies-guide)), so the cluster design must keep sources distinct.

**Feasibility.** Medium. Embeddings or a local model handle similarity. YouTube metadata is purged within the 30-day rules ([Developer Policies](https://developers.google.com/youtube/terms/developer-policies)). No YouTube transcripts are used: `captions.download` requires ownership ([docs](https://developers.google.com/youtube/v3/docs/captions/download)), and scraping is prohibited.

### 11. "About me" profile card, versioned with diffs

**What it is.** A human-readable card of Mark's style and workflow profile, produced by the local learning pipeline. Example entries: "writes 60–120-word replies to students; formal with external suppliers; batches admin mail after 16:00; declines with an alternative offered". Each overnight run produces a **new version shown as a diff** ("+ now replies faster to Product Design staff"). Mark can approve, edit or delete any line. Only the **approved** version is sent to Claude, and he can see which version each cloud call used.

**Why it matters.** Martin AI's main complaint is **2–4 weeks of onboarding to teach it context** ([AI Agent Rank](https://aiagentrank.io/blog/martin-ai-review-2026)). A learned, inspectable profile removes that burden while keeping control, in line with Amershi-style transparency ([MSR](https://microsoft.com/research/project/guidelines-for-human-ai-interaction/)). It also gives Mark's NCAD pilot a concrete artefact to show the DPO: for NCAD data, this card is the *only* thing that leaves his devices. Each line carries a source tag (work-derived or personal-derived) for provenance; Mark has decided that approved work-derived lines go to the cloud like any other approved line.

**Feasibility.** High on the Mac. Profile content is categorical and non-identifying, and a lint step rejects names, email addresses and quotes. It stays per-user, consistent with Google's "personalized model" carve-out ([Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy)).

### 12. Privacy ledger of every cloud call

**What it is.** An append-only, user-visible log of every call that leaves the device or Mac. It records timestamp, provider and region (Anthropic global/US, PCC, Meitheal), model, purpose, **the exact payload sent** (viewable), tokens and cost, and the consent under which it was sent. The ledger also records local purges ("deleted 412 working copies"). It can be exported for the DPIA.

**Why it matters.** App Store 5.1.2(i) requires explicit permission before personal data goes to third-party AI ([TechCrunch](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai)). Claude has **no EU residency** ([data residency](https://platform.claude.com/docs/en/manage-claude/data-residency)). The Limitless EU exit shows how trust collapses when users can't see what's captured ([9to5Mac](https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/)). The ledger turns "trust us" into evidence for Mark and for NCAD's DPO.

**Feasibility.** High. All calls go through the single `LLMProvider` gateway, which writes the ledger entry before sending. The gateway also records **blocked attempts**: a `local-only` item that a code path tried to route to a cloud provider. For the pilot, a ledger showing zero cloud calls carrying NCAD content and zero boundary violations is the key evidence. Entries sync through the private database with encrypted fields. Entries about NCAD items record metadata only, never content, so the ledger itself doesn't move college data to iCloud.

### 13. MCP server on the Mac exposing Eagar to Claude Code and Claude Desktop

**What it is.** A local MCP server, hosted by the Mac app, exposing scoped, read-mostly tools: `get_brief`, `list_deadlines`, `list_loans`, `find_free_slots`, `list_waiting_on`, `add_task`, and `get_profile` (approved version only). Claude Code in VS Code, Claude Desktop and Meitheal agents can then query Mark's day. **The data boundary applies to MCP too.** Tool results are sent to whatever model the client is using, which for Claude Code and Claude Desktop is Anthropic's cloud. So `local-only` (NCAD) content is **redacted to free/busy and counts** for cloud-backed clients, and exposed in full only to clients Mark marks as local (for example, an agent on his Mac's Ollama). The boundary is set per client, and every exposure is written to the ledger.

**Why it matters.** Amie and Mesh both ship MCP servers so external agents can check availability and pull notes ([Amie](https://amie.so/blog/best-ai-executive-assistant); [Dex list](https://getdex.com/blog/personal-crm-list/)). Claude's own Calendar connector is read-only ([Claude docs](https://claude.com/docs/connectors/google/calendar.md)). For Mark, this connects Eagar to the rest of his Claude Code tooling, so a coding session can ask "what's due before Friday?" without opening another app.

**Feasibility.** High on macOS: a local stdio or loopback server, with every tool call written to the privacy ledger. Xcode 27's own MCP support ([FoneArena](https://www.fonearena.com/blog/484623/apple-wwdc26-foundation-models-gemini-support-xcode-27-agentic-coding-tools.html/amp)) suggests the ecosystem is converging on this pattern. Not offered on iOS.

### 14. The work-account pilot, designed as evidence for institutional rollout

**What it is.** Mark's own use is authorised, so the pilot runs from day one, and the NCAD lane ships with a **pilot kit** generated from the app's own configuration. The kit is the case for extending Eagar to other staff, not a gate on Mark. It starts with his **written authorisation** (the email confirming scope) as the first record. It contains an IT allowlisting request: app name, publisher, bundle ID, OAuth client IDs, exact scopes with a justification for each, the requested access level ("Specific Google data", per user or org unit), the open-source repo link, retention, and the no-forwarding guarantee. That list follows what the admin console actually asks for ([API controls](https://knowledge.workspace.google.com/admin/apps/control-which-apps-access-google-workspace-data)). It also contains a **draft DPIA** for NCAD's DPO (purpose, lawful basis options, third-party data, data minimisation, local-only processing, retention, DPF/SCC position if any cloud tier is ever proposed), a **data-flow diagram**, and **pilot metrics**: minutes per day spent checking mail, app-switches avoided, commitments captured, suggestion acceptance rate from the ledger, the approval ledger's draft statistics (see the human-in-the-loop section), and zero cloud calls carrying work content. A **staged consent ladder** lets IT approve other staff in steps: rules-only metadata → local commitment extraction and drafting → local style profile → (possibly) approved-profile-to-cloud.

**Why it matters.** Mark is the proof of concept for whether this reaches other staff. Gmail AI Inbox won't reach Education tenants soon, and even then it would be Google's own service under admin control ([Drag](https://www.dragapp.com/blog/gmail-ai-inbox/)). Evidence from a governed, authorised pilot is what can change a blanket rule that exists mainly from lack of knowledge.

**Feasibility.** High to produce. Approval for other staff is outside Mark's control. The architecture already isolates each lane, and per-account boundary and processing-class switches give IT clean controls for each person.

### 15. Data-class routing visible per item

**What it is.** Every derived item and AI output shows a small locality badge: "On iPhone", "On Mac", "Apple PCC", "Claude (US/global)" or "Meitheal (NCAD)". Settings let Mark pin any data class to a maximum tier. Example: "personal email bodies: Mac only, never cloud".

**Why it matters.** Data locality is the property users and DPOs care about most here, and capability flags already carry it. Making routing visible turns the privacy design into something the user can check, which an open-source app can then prove.

**Feasibility.** High. It is a UI over the provider abstraction.

### 16. "Downloaded and ready" notifications that respect the brief

**What it is.** New-episode notifications fire only once the file is **downloaded**, not merely published. Per-show rules decide whether a show **interrupts** (rare favourites) or **waits for the next brief** (most shows).

**Why it matters.** Mark asked explicitly for downloaded alerts, as Apple Podcasts provides. Per-show batching applies the Iqbal & Bailey breakpoint finding to media. It's the same mechanism as the brief, so media doesn't become a new source of device-checking.

**Feasibility.** Medium. This needs the tiny push server, because silent pushes are best-effort, throttled and lost after a force-quit ([Apple](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app.md)). There is a client-only fallback, and on the Mac, polling is unrestricted.

### 17. Value on day one, cadences learned rather than configured

**What it is.** First run asks for calendar access and one personal inbox, and produces a brief within minutes. Cadences, lane weights, expected reply latencies and media budgets start as defaults and are **proposed from observed behaviour** through the confidence ladder ("You open the brief at 08:40 on teaching days — move it?").

**Why it matters.** Setup burden is a recurring complaint: Motion's learning curve, SkedPal's dated setup, Martin's weeks of onboarding, Sunsama's ritual ([Morgen](https://www.morgen.so/blog-posts/motion-review); [AI Agent Rank](https://aiagentrank.io/blog/martin-ai-review-2026)). Tool sprawl and "automation that quietly fails" recur in surveys ([BigIdeasDB](https://bigideasdb.com/state-of-ai-tools-2026)).

**Feasibility.** High. The defaults are rule-based, and learning reuses the event log from feature 3.

### 18. Spend meter and safe-key setup for BYOK

**What it is.** A per-day and per-feature cost meter computed from API `usage`. It comes with a guided setup for a **dedicated Claude workspace with a monthly spend cap, per-model rate limits and an expiring key** ([workspaces](https://platform.claude.com/docs/en/manage-claude/workspaces); [authentication](https://platform.claude.com/docs/en/manage-claude/authentication)), plus a "test key" check.

**Why it matters.** Being free and open source sidesteps the subscription and trial-billing complaints, but users must not swap a subscription for surprise API bills. The research flagged cost transparency as a necessary companion to BYOK.

**Feasibility.** High.

## Conclusion

The research reframes the product. The hard part is not adding AI to eight domains. It is **subtracting checking**: one brief at breakpoints, lanes that make account of origin the first signal, a confidence ladder that mostly stays quiet, and media treated as a budget rather than a feed. The 2026 casualties (Notion Mail, the Copilot priority view, Pulse, Clockwise) were products that put AI or automation in the user's path. Eagar's defensible position is the reverse: rules first, local AI for anything sensitive, a human approving every send, and the cloud reached only through an approved profile and a visible ledger. The same design that satisfies Google's restricted-scope regime, YouTube's storage rules and App Store 5.1.2(i) is also the user experience the HCI evidence favours. The constraints and the product thesis point the same way.

The NCAD account is the strategic asset, not the obstacle. A personal organiser that works for one technical officer is a hobby project. One that arrives at IT with months of authorised, local-only use behind it is a template for staff across three departments. That record would show approval-ledger statistics, zero boundary violations, a drafted DPIA and a rule format already shared with a Windows client. It also connects naturally to the local AI estate Mark already runs through Meitheal. Build the local-only lane and the approval queue first, and make them pleasant. Let the ledger, not the argument, decide whether the rule changes.

## Open questions for Mark and items needing on-device verification

**Questions for Mark**

| # | Question | Why it matters for the PRD |
|---|---|---|
| 1 | **What route does the Windows app use to reach NCAD mail?** (IMAP-OAuth, Gmail API with his own client ID, Exchange/Outlook, other.) Which OAuth client ID does it use, and does it send through the same route? | Decides what is reusable, and shows what NCAD IT has already effectively permitted |
| 2 | Does "delete the source emails" mean purging Eagar's local working copies only (assumed), or also archiving or deleting on the server? | Server deletion would need `gmail.modify` and is irreversible |
| 3 | Has the "limited to Mark only" authorisation been confirmed in writing, and by whom (IT, the DPO, a HoD)? Does it cover the NCAD calendar and Canvas as well as mail? | It is the pilot's first record and defines scope |
| 4 | Does Tailscale (end-to-end encrypted, possibly relayed) between his own devices satisfy "no college data leaves my local devices"? Does content-free metadata (lane flags, "done" state) syncing through iCloud? | Decides the NCAD sync and approval transport |
| 5 | ~~May profile lines learned from NCAD mail go to Claude, or only personal-derived lines?~~ **Answered:** yes, once Mark approves each line. | Per-line source tag kept for provenance; not a cloud filter |
| 6 | Should any category ever reach L3 (send after delay) on the NCAD account, or is per-message approval permanent there? | Autonomy ceiling for the work lane |
| 7 | Which personal accounts are in scope at M1: personal Gmail, company mail (which provider?), iCloud, Outlook.com? | Sets the library stack (Gmail API vs Graph vs MailCore2) |
| 8 | Public distribution model for Google: BYO Google client ID per user, or pursue restricted-scope verification and possibly CASA? | Determines onboarding friction and annual cost |
| 9 | Will NCAD IT create the Internal OAuth client in NCAD's Google Cloud org, or allowlist Eagar's client ID, and at which access level? | Needed for Eagar's own client on the NCAD tenant |
| 10 | Minimum OS: iOS/macOS 27 (unlocks the Foundation Models `LanguageModel` protocol, PCC and ClaudeForFoundationModels) or 26? | Shapes the AI layer and the device floor |
| 11 | Do the NCAD-owned DGX Sparks count as "his local devices" for NCAD data? Should personal data go to them at all? | Decides whether the Meitheal tier is in the work-data path |
| 12 | Push server: Cloudflare Worker (~$5/month) or self-hosted on his own hardware? | Affects reliability and what self-hosters get |
| 13 | Can cdbooking currently send email confirmations, and will the native replacement publish the same per-user iCal/JSON/webhook contract? | Decides the `BookingSource` adapters |
| 14 | Does NCAD's Canvas allow staff personal access tokens, and is the calendar feed enabled? Is his role teaching (assignments) or support (fewer Canvas items)? | Canvas milestone scope |
| 15 | YouTube v1: read-only (Takeout + RSS, no OAuth), or include subscribe/unsubscribe (full `youtube` scope, verification)? | Scope verification effort |
| 16 | Should the local learning pipeline and approval queue be a shared Swift package with his planned Mac academic-helper app, which also learns his writing voice locally? | Avoids building the same pipeline three times (Windows, Eagar, academic helper) |
| 17 | Licence choice (e.g. MIT, Apache-2.0, GPL), given possible reuse of MPL-2.0 Pocket Casts files? | Licence compatibility |
| 18 | Keep "Eagar" as the name? | Placeholder only |

**On-device and on-account verification**

| Item | How to verify |
|---|---|
| Foundation Models on-device availability on his EU iPhone and iPad under iOS 27 | Check `SystemLanguageModel.availability` on device |
| Private Cloud Compute model availability in the EU, its daily quota, and Small Business Program eligibility for his company | Apply for the entitlement; test `PrivateCloudComputeLanguageModel` on an EU device |
| On-device model `contextSize` (4,096 vs 8,192) on each device | Read `contextSize` at runtime |
| Whether Siri Suggestions and Spotlight surface third-party App Intent donations on EU iPhones in iOS 27 | Donate intents and observe |
| Whether a personal-use, unverified *production* Google client avoids the 7-day refresh-token expiry with restricted scopes | Run for 8+ days |
| Whether an Internal-type OAuth client in NCAD's org avoids the 7-day expiry and public verification | Test with IT's client |
| What NCAD's Workspace actually blocks (`admin_policy_enforced` on Gmail API? IMAP-OAuth allowlist?) | Attempt consent with Eagar's client and record the error; compare with the Windows app's route |
| Whether the NCAD Google account syncs its calendar to Apple Calendar (CalDAV) under current admin settings | Add the account in Settings › Calendar |
| Canvas calendar feed URL and personal-access-token availability on NCAD's instance | Canvas › Calendar › Calendar Feed; Account › Settings |
| Face ID per-send confirmation latency, and Watch approval for one-line replies | Prototype the approval queue |
| Realistic `BGAppRefreshTask` frequency on his devices | Instrument and log for two weeks |
| YouTube embed in WKWebView without error 153, using his own HTTPS-hosted embed page | Test on iPhone, iPad and Mac |
| Throughput and context of 20–30B models via MLX vs Ollama on the 48 GB Mac for overnight pipeline runs | Benchmark on a representative sent-mail sample |
| `ClaudeForFoundationModels` status since OS 27 GA (still beta? current model names?) | Check the package release notes |
| Whether MailKit `rawData` is present on first pass or only after content download | Prototype the Mac action handler |
| CarPlay audio entitlement approval for a combined organiser/podcast app | Submit the request early |
| Shortwave's current Outlook/IMAP support and Gemini Daily Brief's EU status (for competitor positioning) | Check vendor pages before citing publicly |
