# Nowcast

A native macOS app that turns hours of scattered information into a 2-minute markdown brief on the topics you care about — pulling from YouTube, X, Reddit, Hacker News, news, RSS, and the open web, with scheduled reports, dedup, history, and retention controls.

**Status:** Phases 1–8 shipped (manual + scheduled briefings, multi-source adapters, multi-LLM, chat, entities, semantic search, analytics). Now in a production-hardening pass. See [`docs/PLAN.md`](docs/PLAN.md) for the full project spec and phased roadmap.

## Stack

- Swift + SwiftUI, macOS native
- OpenAI API by default; pluggable for other LLMs
- SQLite (via GRDB) + flat markdown files for report storage

## Requirements

- **macOS 13** (Ventura) or later — deployment target.
- **Xcode 16.3 / Swift 6.1** toolchain or later, to resolve dependencies (GRDB 7's package manifest declares `swift-tools-version:6.1`). The app itself still compiles in Swift 5 language mode.

## Phases

| Phase | Scope |
|---|---|
| MVP   | Manual on-demand briefings, Hacker News only, history + retention |
| v1.5  | Topic presets, scheduling, macOS notifications, menu bar |
| v2    | Reddit / YouTube (search + channels + transcripts) / RSS / web search / news |
| v2.5  | X via Nitter, email digest |
| v3    | Multi-LLM, cost tracking, export, Spotlight indexing |

Each phase ships as a separate PR against `main` from a `phase/<n>-<slug>` branch.

## Testing & CI

There is no XCTest target yet; the regression net is an in-app `SelfCheck`
harness that runs the production `ReportPipeline` against a real database with
a mock LLM and asserts every persisted artifact materialized correctly.

Run it headlessly (DEBUG builds only):

```bash
xcodegen generate
xcodebuild -project Nowcast.xcodeproj -scheme Nowcast -configuration Debug \
  -derivedDataPath .build CODE_SIGN_ENTITLEMENTS= build
NOWCAST_SELF_CHECK=1 NOWCAST_SUPPORT_DIR="$(mktemp -d)" \
  .build/Build/Products/Debug/Nowcast.app/Contents/MacOS/Nowcast
echo "exit $?"   # 0 = pass, 1 = fail
```

- `NOWCAST_SELF_CHECK=1` makes the app run the self-check and exit instead of
  showing UI.
- `NOWCAST_SUPPORT_DIR=<dir>` redirects the database + reports into a throwaway
  directory so a run never touches `~/Library/Application Support/Nowcast`.
  This requires the sandbox-disabled build above (`CODE_SIGN_ENTITLEMENTS=`),
  since the sandbox blocks writes outside the app container. Production and
  release builds keep the app sandbox.

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs exactly this on
every push and pull request.

## Distribution

Use `scripts/notarize.sh` to archive/export a Developer ID app, submit it to
Apple, staple its ticket, verify it with Gatekeeper, and produce a ZIP.
The script never publishes the archive. Release builds require your Developer
ID identity; Debug builds remain ad-hoc for contributors and CI.

See [the release guide](docs/RELEASING.md) for setup, configuration, and validation.
