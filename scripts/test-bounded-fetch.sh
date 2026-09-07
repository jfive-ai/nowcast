#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
swiftc -module-cache-path "$build_dir/module-cache" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  Nowcast/Networking/BoundedFetch.swift tests/BoundedFetchRegression.swift \
  -o "$build_dir/bounded-fetch-tests"
"$build_dir/bounded-fetch-tests"
