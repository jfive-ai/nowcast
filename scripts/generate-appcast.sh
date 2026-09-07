#!/bin/bash
# Generate signed Sparkle metadata locally; publishing is a separate action.
set -euo pipefail
if [[ "${1:-}" == --help || $# -ne 1 ]]; then
  printf '%s\n' 'Usage: SPARKLE_BIN_DIR=<Sparkle tools> NOWCAST_DOWNLOAD_URL_PREFIX=https://host/updates/ scripts/generate-appcast.sh <updates-directory>'
  [[ "${1:-}" == --help ]] && exit 0 || exit 2
fi
[[ -d "$1" ]] || { printf 'Updates directory does not exist.\n' >&2; exit 1; }
[[ -x "${SPARKLE_BIN_DIR:-}/generate_appcast" ]] || { printf 'Set SPARKLE_BIN_DIR to Sparkle’s bin directory.\n' >&2; exit 1; }
python3 - <<'PY'
import os
from urllib.parse import urlsplit
url = urlsplit(os.environ.get('NOWCAST_DOWNLOAD_URL_PREFIX', ''))
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
    raise SystemExit('Set NOWCAST_DOWNLOAD_URL_PREFIX to an HTTPS directory URL without credentials, query, or fragment.')
if not url.path.endswith('/'):
    raise SystemExit('NOWCAST_DOWNLOAD_URL_PREFIX must end with a slash.')
PY
# Sparkle retrieves its signing key from the login Keychain. No private key
# belongs in this repository, the app bundle, command arguments, or appcast.
"$SPARKLE_BIN_DIR/generate_appcast" --download-url-prefix "$NOWCAST_DOWNLOAD_URL_PREFIX" "$1"
printf 'Signed appcast generated locally. Publish it with the referenced archives after staging validation.\n'
