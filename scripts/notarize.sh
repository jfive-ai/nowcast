#!/bin/bash
# Build, export, notarize, and staple a Developer ID release. Does not publish.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/notarize.sh [--validate-config]
Required environment:
  NOWCAST_DEVELOPMENT_TEAM  Apple Developer team ID (10 letters/digits)
  NOWCAST_NOTARY_PROFILE    Existing notarytool Keychain profile name
  NOWCAST_RELEASE_VERSION   User-visible version (for example 1.2.0)
  NOWCAST_BUILD_NUMBER      Monotonically increasing integer build number
  NOWCAST_APPCAST_URL       HTTPS URL of the hosted Sparkle appcast
  NOWCAST_SPARKLE_PUBLIC_KEY  Base64 Ed25519 public key (32 bytes)
Optional:
  NOWCAST_RELEASE_DIR       New output directory (default build/release-<build>)

Uses your installed Developer ID Application certificate and Keychain profile.
No passwords or private keys are accepted by this script. --validate-config
checks inputs without accessing the Keychain, building, or submitting to Apple.
EOF
}
fail() { printf '%s\n' "$*" >&2; exit 1; }
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --validate-config|'') ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }
[[ "${NOWCAST_DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]] || fail 'Set NOWCAST_DEVELOPMENT_TEAM to your 10-character team ID.'
[[ -n "${NOWCAST_NOTARY_PROFILE:-}" ]] || fail 'Set NOWCAST_NOTARY_PROFILE to an existing notarytool Keychain profile name.'
[[ "${NOWCAST_RELEASE_VERSION:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail 'Set NOWCAST_RELEASE_VERSION to a numeric version, such as 1.2.0.'
[[ "${NOWCAST_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || fail 'Set NOWCAST_BUILD_NUMBER to a positive, increasing integer.'
python3 - <<'PYCONFIG'
import base64, os
from urllib.parse import urlsplit
url = urlsplit(os.environ.get('NOWCAST_APPCAST_URL', ''))
if url.scheme != 'https' or not url.hostname or url.username or url.password:
    raise SystemExit('Set NOWCAST_APPCAST_URL to an HTTPS feed URL without credentials.')
try:
    key = base64.b64decode(os.environ.get('NOWCAST_SPARKLE_PUBLIC_KEY', ''), validate=True)
except ValueError:
    raise SystemExit('NOWCAST_SPARKLE_PUBLIC_KEY must be a base64 Ed25519 public key.')
if len(key) != 32:
    raise SystemExit('NOWCAST_SPARKLE_PUBLIC_KEY must decode to 32 bytes.')
PYCONFIG
[[ "${1:-}" != --validate-config ]] || { printf 'Release configuration is valid.\n'; exit 0; }

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="${NOWCAST_RELEASE_DIR:-$repo_dir/build/release-$NOWCAST_BUILD_NUMBER}"
[[ ! -e "$release_dir" ]] || fail "Output directory already exists: $release_dir. Choose a new release directory."
for command in xcodegen xcodebuild xcrun security codesign spctl ditto python3; do
  command -v "$command" >/dev/null || fail "Required tool not found: $command"
done
identities="$(security find-identity -v -p codesigning)"
matching_identity=false
while IFS= read -r identity; do
  if [[ "$identity" == *"Developer ID Application:"*"($NOWCAST_DEVELOPMENT_TEAM)"* ]]; then
    matching_identity=true
    break
  fi
done <<< "$identities"
[[ "$matching_identity" == true ]] || fail 'No Developer ID Application signing identity found for the selected team.'
mkdir -p "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
export NOWCAST_RELEASE_OUTPUT="$release_dir"
python3 - <<'PY'
import os, plistlib
from pathlib import Path
p = Path(os.environ['NOWCAST_RELEASE_OUTPUT']) / 'ExportOptions.plist'
p.write_bytes(plistlib.dumps({
    'method': 'developer-id', 'signingStyle': 'manual',
    'signingCertificate': 'Developer ID Application',
    'teamID': os.environ['NOWCAST_DEVELOPMENT_TEAM'],
}))
PY
cd "$repo_dir"
xcodegen generate
xcodebuild -project Nowcast.xcodeproj -scheme Nowcast -configuration Release \
  -archivePath "$release_dir/Nowcast.xcarchive" \
  DEVELOPMENT_TEAM="$NOWCAST_DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$NOWCAST_RELEASE_VERSION" CURRENT_PROJECT_VERSION="$NOWCAST_BUILD_NUMBER" \
  NOWCAST_APPCAST_URL="$NOWCAST_APPCAST_URL" NOWCAST_SPARKLE_PUBLIC_KEY="$NOWCAST_SPARKLE_PUBLIC_KEY" \
  archive
# Archive/export signs nested frameworks and XPC services correctly. Do not
# replace it with codesign --deep, which can overwrite helper entitlements.
xcodebuild -exportArchive -archivePath "$release_dir/Nowcast.xcarchive" \
  -exportPath "$release_dir/export" -exportOptionsPlist "$release_dir/ExportOptions.plist"
app="$release_dir/export/Nowcast.app"
[[ -d "$app" ]] || fail 'Archive export did not produce Nowcast.app.'
codesign --verify --deep --strict --verbose=2 "$app"
signing_info="$(codesign -dv --verbose=4 "$app" 2>&1)"
[[ "$signing_info" == *'Authority=Developer ID Application:'* ]] || fail 'Exported app is not Developer ID signed.'
[[ "$signing_info" == *"TeamIdentifier=$NOWCAST_DEVELOPMENT_TEAM"* ]] || fail 'Exported app has the wrong signing team.'
[[ "$signing_info" == *'(runtime)'* ]] || fail 'Exported app is missing hardened runtime.'
zip="$release_dir/Nowcast-$NOWCAST_RELEASE_VERSION-$NOWCAST_BUILD_NUMBER.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOWCAST_NOTARY_PROFILE" --wait --output-format json > "$release_dir/notarization.json"
python3 - <<'PY'
import json, os
from pathlib import Path
result = json.loads((Path(os.environ['NOWCAST_RELEASE_OUTPUT']) / 'notarization.json').read_text())
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect notarization.json and the notarytool log before distribution.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# Repack after stapling, so the downloadable ZIP contains the ticket.
ditto -c -k --keepParent "$app" "$zip"
printf 'Verified release archive: %s\n' "$zip"
