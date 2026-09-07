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
