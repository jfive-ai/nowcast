# CLAUDE.md — Nowcast project conventions

## Project

Nowcast is a native macOS SwiftUI app that produces topic-scoped briefings from multiple sources. Full spec: [`docs/PLAN.md`](docs/PLAN.md).

## Build

The Xcode project is **generated** from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen) — `Nowcast.xcodeproj` is gitignored.

```bash
brew install xcodegen           # one-time
xcodegen generate               # produces Nowcast.xcodeproj
open Nowcast.xcodeproj          # opens in Xcode; Cmd+R to run
```

You also need full Xcode (not just Command Line Tools) — install from the Mac App Store, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

Deployment target: **macOS 13** (Ventura) — required for `MenuBarExtra` (used from v1.5).

## Conventions

- **Swift 5 mode** during MVP. We'll consider Swift 6 strict concurrency later.
- **No force-unwrapping (`!`) in production code** except for compile-time-known constants.
- **Async/await** for all I/O. Avoid completion handlers.
- **Models are `Codable` structs**; views use `@Observable` (Swift 5.9+) or `ObservableObject` for app state.
- **One type per file**, file named after the type.
- **Source organization** mirrors `docs/PLAN.md` architecture diagram:
  - `Nowcast/App/` — `@main` entry, app-wide state
  - `Nowcast/Views/` — SwiftUI views
  - `Nowcast/Pipeline/` — `ReportPipeline` and helpers
  - `Nowcast/Sources/` — `SourceAdapter` protocol + per-source adapters
  - `Nowcast/LLM/` — `LLMClient` protocol + provider clients
  - `Nowcast/Storage/` — `StorageManager`, `KeychainStore`, schema
  - `Nowcast/Prompts/` — prompt templates
  - `Nowcast/Models/` — value types

## Storage layout (runtime, on user's machine)

- SQLite DB: `~/Library/Application Support/Nowcast/nowcast.sqlite`
- Markdown reports: `~/Library/Application Support/Nowcast/reports/<yyyy-MM-dd>/<id>.md`
- Secrets: macOS Keychain, service `com.jfive-ai.nowcast`

## Adding a new source adapter

1. New file in `Nowcast/Sources/<Name>Adapter.swift` conforming to `SourceAdapter`.
2. Add a case to `SourceKind` in `Nowcast/Models/SourceKind.swift`.
3. Register in `ReportPipeline.adapters` (or wherever the adapter map lives).
4. Add to the `Phase 2` checklist in `docs/PLAN.md` if not already covered.

## Adding a new LLM provider

1. New file in `Nowcast/LLM/<Provider>Client.swift` conforming to `LLMClient`.
2. Add a Settings UI control to choose provider.
3. Store the API key under the provider's own Keychain account.

## Branch / PR rules

- Each phase ships as a single PR against `main` from `phase/<n>-<slug>` (per `docs/PLAN.md` Workflow).
- Phase PRs are mergeable only when the matching sub-issue's verification checklist is fully ticked.
- Don't start phase N+1 until phase N is merged.

## What not to do

- Don't add features beyond the current phase's scope. New ideas → next phase's sub-issue, not this PR.
- Don't shell out to `claude` or any LLM tool from app code. The LLM is reached via `LLMClient` protocol over HTTP.
- Don't commit `Nowcast.xcodeproj` — it's regenerated. If a PR needs an xcodegen change, edit `project.yml`.
- Don't commit API keys. Real keys go in Keychain via Settings UI.
