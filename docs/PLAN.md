# Nowcast — macOS Trend Briefing App

## Context

You consume too much information across YouTube, X, Reddit, HN, news, and blogs, and you're missing critical points on topics you care about (e.g. ETH this week, today, or in the last hour). You want a native macOS app that produces topic-scoped briefings on demand and on a schedule, archives them with retention controls, and pulls from sources you trust — including ones you can subscribe to specifically (YouTube channels, subreddits, RSS feeds, X accounts).

The intended outcome: a personal "nowcast" tool that turns N hours of doomscrolling into a 2-minute markdown brief with TL;DR, clustered stories, an opinionated signal section, and links back to original sources.

## Should you use the `topic-pulse` skill?

**Use it as a reference, not as a runtime dependency.**

`topic-pulse` lives at `/Users/humanjack/.agents/skills/topic-pulse/` and produces exactly the kind of output you want: TL;DR → clustered stories → Signal section → grouped sources, with per-topic seen-index dedup and a 24h/7d window. Its prompt design and output format are excellent — copy them.

But it can't be the engine because:
- It's a Claude Code skill — runs only inside the Claude CLI, not as a standalone macOS app.
- It uses Claude (not OpenAI) and depends on Claude's WebSearch/WebFetch tools.
- It doesn't cover X/Twitter, specific YouTube channels, or RSS — three sources you said matter.
- It has no scheduling, history archive, retention, or notification — the bulk of the value of *your* app.

**Recommendation:** Reimplement topic-pulse's report structure and dedup logic natively in Nowcast. Treat its `SKILL.md` as a design doc.

## Decisions locked from clarification

| Area | Decision |
|---|---|
| App stack | Swift + SwiftUI, macOS native |
| LLM | OpenAI by default; user supplies API key; provider abstraction for future Anthropic/others |
| Sources (v1+) | Web search, news, Hacker News, Reddit (search), YouTube (search) |
| Sources (later) | YouTube channels (with transcripts), RSS, X via Nitter |
| Scheduling | Hourly / every N hours, Daily at time, Weekly digest, plus on-demand |
| Delivery (per preset) | macOS notification, menu bar indicator, email digest, in-app only (default) |
| YouTube depth | Title + description + transcript |
| Scope | Phased MVP → v1.5 → v2 → v2.5 → v3 |

## Architecture overview

```
┌────────────────────── SwiftUI app ──────────────────────┐
│  TopicLibraryView   ReportView   HistoryView   Settings │
│                      MenuBarExtra                       │
└──────────────┬──────────────────────────┬───────────────┘
               │                          │
        BackgroundScheduler         NotificationManager
               │                          │
               ▼                          ▼
        ┌──────────────── ReportPipeline ─────────────────┐
        │ collect → dedupe → cluster → summarize → write  │
        └─────────┬────────────┬──────────────────────────┘
                  │            │
        SourceAdapter[]    LLMClient (OpenAI / …)
                  │
        StorageManager (SQLite + markdown files)
```

### Data model (SQLite)

- `topic_preset` — id, name, query, sources[], cadence, delivery_channels[], created_at, last_run_at
- `report` — id, preset_id (nullable for ad-hoc), topic, window, generated_at, markdown_path, byte_size, source_count
- `source_subscription` — id, kind (`youtube_channel` / `subreddit` / `rss` / `x_account` / `news_outlet`), identifier, label
- `seen_item` — id, preset_id, url_hash, first_seen_at — pruned at 90d (carryover from topic-pulse)
- `settings` — singleton: openai_api_key (Keychain), default_retention_days, default_delivery_channel, etc.

Markdown bodies live as files at `~/Library/Application Support/Nowcast/reports/<yyyy-mm-dd>/<id>.md` so they're greppable, exportable, and contribute visibly to the "total data size" UI.

### LLM abstraction

```swift
protocol LLMClient {
    func summarize(prompt: String, model: String) async throws -> String
}
```

Implementations: `OpenAIClient` (v1), `AnthropicClient` (v3). API key per provider stored in Keychain.

### Source adapter protocol

```swift
protocol SourceAdapter {
    var kind: SourceKind { get }
    func fetch(query: String, window: TimeWindow, subscriptions: [SourceSubscription]) async throws -> [RawItem]
}
```

Each adapter returns normalized `RawItem` (title, url, published_at, snippet, optional transcript). The pipeline merges, dedupes via `seen_item`, clusters, then sends to the LLM with topic-pulse's prompt template.

### External APIs / dependencies (verify availability before each phase)

| Source | Mechanism | Notes |
|---|---|---|
| Hacker News | hn.algolia.com (free) | Easy, no key |
| Reddit | reddit.com/.json (rate-limited) | App-only OAuth recommended |
| YouTube | YouTube Data API v3 (free quota 10k/day) | Requires Google Cloud project + API key in Settings |
| YouTube transcripts | youtube-transcript-api equivalent in Swift, or shell out to a helper | Some videos have none — handle gracefully |
| Web search | Brave Search API or SerpAPI (paid) | User supplies key in Settings |
| News | NewsAPI.org or Google News RSS | RSS is free but flaky |
| RSS | Native XML parsing (FeedKit) | No key |
| X (Nitter) | RSS endpoint per Nitter instance | Maintain a small list of mirrors with health-check fallback |

## Workflow

Before any code is written:

1. **Plan-as-docs.** Copy this plan to `docs/PLAN.md` so it lives in the repo and travels with the project. Commit on `main` as the first commit.
2. **GitHub remote.** Confirm a GitHub remote exists (`git remote -v`). If not, ask before creating one. `gh` CLI must be authenticated.
3. **Parent issue.** Create one umbrella issue: *"Build Nowcast — macOS trend briefing app"* with the Context + Decisions sections from this plan as its body.
4. **Sub-issue per phase.** Create five sub-issues (MVP, v1.5, v2, v2.5, v3), each linked to the parent and containing that phase's bullet list and verification checklist. Use GitHub task-list syntax in the parent so sub-issues render as a tracked checklist.
5. **One PR per phase.** Each phase ships as a single PR against `main`, branch named `phase/<n>-<slug>` (e.g. `phase/1-mvp`, `phase/1.5-scheduling`). Phases are merged in order; the next phase doesn't start until the prior PR is merged.
6. **Per-phase definition of done.** Phase PR is mergeable only when its verification checks (below) pass and the corresponding sub-issue checklist is fully ticked.

## Phased plan

### MVP (v1) — manual briefings, single source, working storage

Goal: end-to-end flow proves the loop works.

- SwiftUI app shell, Settings tab with OpenAI key field (Keychain) + retention days
- One adapter: **Hacker News** (free, no key, simplest)
- ReportPipeline: fetch → dedupe → single LLM call → markdown
- HistoryView: list of past reports with date, topic, byte size; tap to view
- "Clean history from oldest" button + automatic prune by retention_days
- Total data size shown in Settings
- New report flow: type topic, pick window (1h / today / 7d), Generate

**Critical files to create**
- `Nowcast.xcodeproj` — Xcode project
- `Nowcast/App/NowcastApp.swift` — `@main` entry
- `Nowcast/Views/TopicLibraryView.swift`, `ReportView.swift`, `HistoryView.swift`, `SettingsView.swift`
- `Nowcast/Pipeline/ReportPipeline.swift`
- `Nowcast/LLM/LLMClient.swift`, `OpenAIClient.swift`
- `Nowcast/Sources/SourceAdapter.swift`, `HackerNewsAdapter.swift`
- `Nowcast/Storage/StorageManager.swift` (GRDB.swift or Core Data — recommend GRDB)
- `Nowcast/Prompts/BriefingPrompt.swift` — port topic-pulse's TL;DR/Stories/Signal template
- `Nowcast/Models/*.swift` — `TopicPreset`, `Report`, `RawItem`, `SourceSubscription`
- `README.md`, `CLAUDE.md` (minimum project conventions)

### v1.5 — Topic presets, scheduling, native delivery

- Topic preset CRUD (name + query + sources + cadence + delivery)
- BackgroundScheduler using `NSBackgroundActivityScheduler` (works while app open or via login item)
- Cadences: hourly / every N hours, daily-at-time, weekly-at-day-time
- Delivery: macOS notification (UNUserNotificationCenter) + MenuBarExtra with unread count
- "On-demand" runs from the menu bar without opening the main window

### v2 — Source breadth

- Reddit adapter (search + per-subreddit subscription)
- YouTube search adapter (Data API v3, requires user-provided Google API key)
- YouTube channel adapter (with transcript fetch + graceful fallback to title+description)
- RSS adapter (FeedKit)
- Brave / SerpAPI web search adapter (user-provided key)
- News adapter (NewsAPI or Google News RSS)
- Source suggestion: when user types a topic, LLM call returns 5 suggested feeds/channels (only if user clicks "Suggest")

### v2.5 — X via Nitter, email delivery

- Nitter adapter pulling RSS from a configured mirror list with auto-failover when an instance returns 5xx/timeout
- Settings: configurable Nitter mirror list, default mirror health indicator
- Email digest delivery via SMTP (user provides creds) or `mailto:` open-in-default-client; recommend SMTP for true unattended delivery

### v3 — Multi-LLM + polish

- Provider switcher in Settings (OpenAI, Anthropic, local via Ollama)
- Cost/token tracking per report
- Export report (markdown / PDF / share sheet)
- Spotlight-indexed reports (Core Spotlight)

## Open risks worth flagging

- **Nitter is genuinely fragile.** Public mirrors come and go. Plan for X delivery to occasionally show "no recent activity" rather than failing the whole report.
- **YouTube Data API quota** (10k units/day) burns fast with many channels. Cache aggressively; fetch incrementally from `lastPublishedAt`.
- **OpenAI cost on hourly schedules.** Surface estimated cost per report in Settings so the user doesn't accidentally rack up $30/day on aggressive cadences.
- **Background execution on macOS** is more permissive than iOS but still needs the app launched at login or always-running. Document the tradeoff in onboarding.
- **Topic ambiguity.** topic-pulse stops and asks; a desktop app should instead generate but flag low-confidence at the top of the report.

## Verification

For each phase, the app is "done" when these end-to-end checks pass:

**MVP**
1. Set OpenAI key in Settings → Save → key roundtrips from Keychain.
2. New report on topic "ethereum", window = 24h, source = HN → markdown report appears in HistoryView with TL;DR + stories + signal + source links.
3. Re-run same topic → new items only (dedup verified against `seen_item`).
4. Settings shows non-zero "Total data size"; "Clean oldest" reduces it.
5. Set retention = 1 day; wait/skip clock → old reports auto-pruned on next launch.

**v1.5**
1. Create preset "ETH daily 8am" with HN + manual run → preset appears in library.
2. Set system clock or scheduler trigger → report generates in background.
3. macOS notification fires; clicking opens that report.
4. Menu bar shows unread badge; clicking item marks read.

**v2**
- Each new adapter returns ≥1 item for a known-active topic.
- YouTube channel "Bankless" subscription pulls last 5 uploads with transcripts where available.
- Source suggestion returns 5 plausible feeds for "rust async runtime".

**v2.5 / v3**
- Nitter mirror failover: kill the configured mirror → next run picks the next healthy one.
- Email digest arrives in inbox with markdown rendered as HTML.
- Switching provider OpenAI → Anthropic produces a comparable report on the same topic.
