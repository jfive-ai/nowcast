# Nowcast

A native macOS app that turns hours of scattered information into a 2-minute markdown brief on the topics you care about — pulling from YouTube, X, Reddit, Hacker News, news, RSS, and the open web, with scheduled reports, dedup, history, and retention controls.

**Status:** Early planning. See [`docs/PLAN.md`](docs/PLAN.md) for the full project spec and phased roadmap.

## Stack

- Swift + SwiftUI, macOS native
- OpenAI API by default; pluggable for other LLMs
- SQLite (via GRDB) + flat markdown files for report storage

## Phases

| Phase | Scope |
|---|---|
| MVP   | Manual on-demand briefings, Hacker News only, history + retention |
| v1.5  | Topic presets, scheduling, macOS notifications, menu bar |
| v2    | Reddit / YouTube (search + channels + transcripts) / RSS / web search / news |
| v2.5  | X via Nitter, email digest |
| v3    | Multi-LLM, cost tracking, export, Spotlight indexing |

Each phase ships as a separate PR against `main` from a `phase/<n>-<slug>` branch.
