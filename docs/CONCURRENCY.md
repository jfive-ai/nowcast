# Concurrency and HTTP regression checks

The app remains in Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY: targeted`
in `project.yml`. StorageManager, ReportPipeline, source adapters, and LLM clients
have compiler-checked Sendable boundaries. ReportEmbedder's unchecked conformance
is backed by the existing NSLock around every NLEmbedding vector operation;
NLEmbedding must never be assumed safe for concurrent calls.

PDF rendering stays on MainActor. Speech delegate callbacks extract the immutable
playback session ID before hopping to MainActor, and notification callbacks
acknowledge delivery on their original queue before UI activation completes.

Run the stronger compiler audit without changing the project default:

```bash
xcodegen generate
xcodebuild -project Nowcast.xcodeproj -scheme Nowcast -configuration Debug \
  -derivedDataPath .build CODE_SIGN_ENTITLEMENTS= \
  SWIFT_STRICT_CONCURRENCY=complete build
```

The Xcode 26 SDK still emits AttributeScopes SwiftUI/Foundation key-path Sendable
warnings without app source locations. These are separate from application
concurrency diagnostics and are why this change does not enable complete checking
as the default or switch the whole app to Swift 6.

Every HTTP response uses `BoundedFetch`: 8 MiB for source feeds/JSON/HTML and mirror
probes, 16 MiB for LLM completions (including each retry), and 64 KiB for webhook
responses. Content-Length is rejected early when too large. The streaming delegate
also counts the actual delivered bytes, including decompressed data, so missing or
misleading length headers cannot bypass the limit. Oversize responses cancel the
underlying task and throw a localized error; they are not retried by HTTPRetry.
The per-task collector leaves redirect handling to the existing session delegate.

Run the isolated HTTP integration checks (also run in CI):

```bash
scripts/test-bounded-fetch.sh
```

The checks compile the production helper in Swift 6 with complete concurrency
checking and use a streaming URLProtocol fixture. They cover a small response,
exact cap, empty response with zero cap, preserved HTTP status, oversized declared
length, an unknown-length oversized stream, a nonempty response with zero cap,
and cancellation of a stalled response. They verify early transport cancellation,
not merely a size check after fully buffering the response.
