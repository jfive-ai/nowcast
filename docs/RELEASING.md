# Developer ID releases

Install a **Developer ID Application** certificate and its private key through
Apple's supported developer account/Xcode workflow. Verify it appears in
`security find-identity -v -p codesigning`. Record your ten-character team ID.
Create a notarization profile once using `xcrun notarytool store-credentials`;
enter credentials interactively so passwords do not enter scripts or shell history.

Set the following non-secret values in your release shell:

```bash
export NOWCAST_DEVELOPMENT_TEAM=YOURTEAMID
export NOWCAST_NOTARY_PROFILE=nowcast-notary
export NOWCAST_RELEASE_VERSION=0.1.0
export NOWCAST_BUILD_NUMBER=2
scripts/notarize.sh --validate-config
scripts/notarize.sh
```

Use a **strictly increasing** build number for each distributed artifact.
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` feed the generated Info.plist.
The default output is `build/release-<build>/`; the script refuses to reuse an
existing output directory. Set `NOWCAST_RELEASE_DIR` to a new path if necessary.

The script archives and exports through Xcode, verifies the Developer ID team
and hardened runtime, submits a ZIP and requires Apple's `Accepted` status,
staples the app, validates its ticket, and requires Gatekeeper acceptance.
It then regenerates the ZIP with the stapled app. Keep `notarization.json` with
the build record. If Apple rejects the submission, use its submission ID with
`xcrun notarytool log` and fix the finding before retrying in a new directory.
Never distribute an archive from a failed run.

Nested frameworks and XPC services must be signed by Xcode's archive/export
workflow; do not recursively re-sign them with `codesign --deep`.
`codesign --deep` in the script is used only for **verification**.

A certificate-free local Release compile can be checked explicitly with:

```bash
xcodegen generate
xcodebuild -scheme Nowcast -configuration Release CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

That override produces a development artifact, **not a distributable release**.
Local Debug builds and the headless self-check need no Developer ID certificate.

Actual notarization and a Gatekeeper check on another Mac require the configured
certificate, Apple account profile, and network access. Input validation and
mocked workflow tests do not establish notarization success.

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Sparkle archive/export signing guidance](https://sparkle-project.org/documentation/sandboxing/).

## Sparkle automatic updates

The app uses Sparkle 2.9.6 with its installer XPC service and sandbox Mach lookup
entitlements. Debug builds with no update configuration never start the updater;
the menu item is disabled. The headless runner exits before constructing it.

Resolve the Swift package, then locate Sparkle's tools under
`<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/`. Run `generate_keys`
once to store an Ed25519 private key in your login Keychain. Record the printed
**public** key; keep the private key backed up using Sparkle's documented process.
Never commit or paste the private key into a PR or shell command.

Set these additional non-secret release values before running `notarize.sh`:

```bash
export NOWCAST_APPCAST_URL=https://your-update-host.example/updates/appcast.xml
export NOWCAST_SPARKLE_PUBLIC_KEY='<your base64 public key>'
```

These are placeholders for your actual hosted feed and key, not a working update
service. Release input validation requires HTTPS and a 32-byte public key.
Xcode expands them into `SUFeedURL` and `SUPublicEDKey` in the built app.
The archive/export workflow also signs Sparkle's nested helpers.

Put notarized release ZIPs in a staging directory and generate the signed feed:

```bash
export SPARKLE_BIN_DIR='<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin'
export NOWCAST_DOWNLOAD_URL_PREFIX=https://your-update-host.example/updates/
scripts/generate-appcast.sh build/updates
```

The generator reads the private key from Keychain and writes the appcast/deltas.
Publish the generated feed at `NOWCAST_APPCAST_URL` and its archives/deltas at the
matching download prefix. The script does not upload or enable hosting.

Before public distribution, use two genuine Developer ID signed and notarized
versions with increasing build numbers on a staging HTTPS feed. In the older
app, select **Check for Updates…**, then verify detection, download, signature
validation, installation, restart into the newer build, and sandbox operation.
Also test a tampered archive is rejected. Local configuration/self-check tests
cannot establish that full install path. Hosting, key provisioning, and this
end-to-end validation remain release requirements.

Sources: [Sparkle setup](https://sparkle-project.org/documentation/),
[SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/),
[sandbox requirements](https://sparkle-project.org/documentation/sandboxing/).
