# Releasing

Releases are cut by hand with the Release workflow (Actions › Release › Run workflow, or
`gh workflow run release.yml -f bump=patch`). It bumps the version from the latest `v*` tag (patch
by default; pick `minor` or `major`, or pass an explicit `version`), writes release notes listing
every commit since that tag grouped as Added / Changed / Fixed / Removed with a compare link
(`Scripts/release.swift`), runs the tests, builds the bundle stamped with that version, and publishes
the zip under the new tag. `dry_run=true` does everything except publish and keeps the zip and notes
as a workflow artifact. Pushes to `master` only run the tests (`.github/workflows/ci.yml`).

The notes can be previewed locally:

```sh
swift Scripts/release.swift notes v0.1.6 0.2.0
```

## Updates

The release workflow writes the Sparkle `appcast.xml` (with the notes as HTML) using the
`SPARKLE_PRIVATE_KEY` secret and attaches it to the release, where the app looks for it at
`releases/latest/download/appcast.xml`. The matching public key is `SUPublicEDKey` in
`Resources/Info.plist`. The private key also lives in the keychain of the Mac that generated it, as
"Private key for signing Sparkle updates". How the app consumes the feed is described in
[Installing](Installing.md).

## Signing and notarization

With four repository secrets in place the workflow signs the bundle with a Developer ID certificate
under the hardened runtime, notarizes it with Apple and staples the ticket, so downloads open
without the Gatekeeper dance. Without them it falls back to an ad-hoc signature.

1. Certificate: in Xcode › Settings › Accounts › Manage Certificates, add a **Developer ID
   Application** certificate. In Keychain Access, export it (with its private key) as a `.p12`
   with a password. Then
   `gh secret set MACOS_CERTIFICATE_P12 < <(base64 -i Certificates.p12)` and
   `gh secret set MACOS_CERTIFICATE_PASSWORD`.
2. Notarization key: in App Store Connect › Users and Access › Integrations › App Store Connect
   API, generate a team key with the Developer role and download its `.p8`. Then
   `gh secret set NOTARY_KEY_P8 < <(base64 -i AuthKey_XXXX.p8)`, `gh secret set NOTARY_KEY_ID` (the
   key's ID) and `gh secret set NOTARY_ISSUER_ID` (the issuer ID shown above the key list).

The identity name is read from the certificate, so nothing else needs configuring. Locally,
`make app SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` signs the same way
(notarization is CI-only).
