# Baplet: build, sign, distribute

Planning document. Nothing here has been run or created yet. Facts about this project come from `CLAUDE.md`, `scripts/release.sh`, `ExportOptions.plist`, `baplet/baplet.entitlements` and `project.pbxproj`. Facts about Apple and GitHub come from the linked docs; where I could not verify something it says so.

## Where things stand

> **Decision (2026-11-15):** no paid Apple Developer Program membership; Baplet is free software. Releases are signed with a self-signed certificate ("Baplet Release Signing", see the README's "Signing" section) so calendar access survives updates, and first launch keeps the Open Anyway step. The Developer ID, notarization and App Store phases below are kept for reference only.


- Bundle ID `io.konkord.baplet`, version `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` (Debug and Release alike), deployment target macOS 26.3.
- Signing is `Automatic` with team `H2MCB54VDW`, which is a free Personal Team. The only local identity is a free "Apple Development" certificate. Apple only issues Developer ID certificates, notarization and App Store access to paid members.
- Hardened runtime is on, sandbox is off (`ENABLE_APP_SANDBOX = NO`). The only entitlement is `com.apple.security.personal-information.calendars`. `LSUIElement` is set.
- Only dependency: KeyboardShortcuts 3.1.0 (pinned, `Package.resolved` committed).
- `scripts/release.sh` already does archive, Developer ID export, DMG, notarize, staple. It cannot work yet: it needs a paid account and a stored notarytool profile built from an Apple ID and app-specific password.
- The GitHub repo `konkord-io/baplet` is **public** (since 2026-11-14), owned by an organisation on the Free plan. CI (`ci.yml`) and a draft-release workflow (`release.yml`, signed with the self-signed release certificate) exist; see the README's "Releasing" section.
- The README's "Sharing the app with friends" section describes the free workaround (Gatekeeper "Open Anyway"). It is the right answer until Phase 0 is done, and obsolete after.

What "no Gatekeeper warnings" requires: the app is signed with a Developer ID Application certificate, uses the hardened runtime, has been notarized by Apple, and the notarization ticket is stapled so it also works offline. See [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/).

## Phase 0: one-time manual steps (owner)

Only the Account Holder can do the certificate steps, so do them from the enrolled Apple ID.

- [ ] **Enrol** in the [Apple Developer Program](https://developer.apple.com/programs/enroll/) ($99/yr). Pick Individual or Organization (see open decisions). Individual enrolment uses your legal name as the public seller name. Organization enrolment needs a legal entity and a D-U-N-S number and takes longer.
- [ ] **Turn on two-factor auth** for the Apple ID (required to enrol).
- [ ] **Check the Team ID** after enrolment (developer.apple.com, Membership details). I am not certain the paid team keeps the Personal Team's ID `H2MCB54VDW`. If it differs, change `DEVELOPMENT_TEAM` in `project.pbxproj` (both configurations, and the project-level entries) and `teamID` in `ExportOptions.plist`.
- [ ] **Create the Developer ID Application certificate.** Easiest: Xcode, Settings, Accounts, select the team, Manage Certificates, `+`, "Developer ID Application". Alternative: upload a CSR at developer.apple.com, Certificates. See [Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/). Only Developer ID Application is needed for the app and DMG. The "Developer ID Installer" certificate is only for `.pkg` installers, which we don't use.
- [ ] **Export the certificate as `.p12`** from Keychain Access (My Certificates, expand the entry so the private key is included, right-click, Export). Use a strong password and store both in your password manager. This is also your backup: the certificate cannot be re-downloaded with its private key. (The old `calkitty.p12` is treated as lost.)
- [ ] **Create an App Store Connect API key** for notarization: App Store Connect, Users and Access, Integrations, Team Keys, `+`. Name it "baplet-ci-notary". Download the `.p8` once (it cannot be downloaded again) and note the Key ID and the Issuer ID shown at the top of the page. See [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api). Notarization works with the Developer role. Use Admin only if you also want the same key for Phase 2 uploads and cloud signing (see Phase 2). One key per purpose is cleaner and revocable. An API key is preferred over an Apple ID plus app-specific password because it is not tied to your personal login, can be revoked on its own and does not need 2FA handling.
- [ ] **Register the bundle ID** `io.konkord.baplet` under Certificates, Identifiers & Profiles, Identifiers (explicit App ID, macOS). Not strictly required for Developer ID distribution of this app (no profile is needed), but required for Phase 2 and cheap to do now. Xcode's automatic signing may already have registered it under the Personal Team. Check that it exists under the paid team.
- [ ] **Store notarytool credentials locally** to test by hand: `xcrun notarytool store-credentials baplet-notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer ISSUER-UUID`. This is what `release.sh` expects under the profile name `baplet-notary`.
- [x] **Decide where downloads are hosted.** Decided 2026-11-14: GitHub Releases on this (now public) repo; later also `baplet.konkord.io` on Cloudflare Pages.
- [ ] **Dry run locally** once with `scripts/release.sh` (after the small fixes in "How `release.sh` relates") before building CI. A local success makes CI failures much easier to diagnose.

After the first signed build, users who ran the old "Apple Development"-signed build may be asked for calendar access again, because the code signature (designated requirement) changed. Bundle ID stays the same, so `UserDefaults` are kept.

## Phase 1: pipeline

### Versioning

- `MARKETING_VERSION` (user-visible, `CFBundleShortVersionString`): semantic version, taken from the git tag. Tag `v1.2.0` gives `1.2.0`.
- `CURRENT_PROJECT_VERSION` (build number, `CFBundleVersion`): a monotonically increasing integer. In CI use `${{ github.run_number }}`. Phase 2 needs this to be unique and increasing per version in App Store Connect; `run_number` satisfies that as long as one workflow produces both.
- Do not commit version bumps per release. Pass both as `xcodebuild` overrides (`MARKETING_VERSION=... CURRENT_PROJECT_VERSION=...`). The values in `project.pbxproj` stay at a dev default. Locally, `release.sh` should take the same two values as arguments.

### Steps

1. **Archive.** `xcodebuild archive -scheme baplet -configuration Release`. For CI, sign manually with the imported certificate (no Apple ID is logged in on the runner): `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=<id>`. Use the stable identity prefix, not the full certificate name, so the workflow survives a certificate renewal.
2. **Export for Developer ID.** `xcodebuild -exportArchive` with an export options plist: `method` = `developer-id`, `signingStyle` = `manual`, `signingCertificate` = `Developer ID Application`, `teamID`. The existing `ExportOptions.plist` uses `automatic`, which needs a signed-in Xcode account and will not work in CI. CI generates its own manual plist in the workflow (below), so the committed file stays for local use.
3. **Check hardened runtime and signature** on the exported app (fail the build if any check fails):
   - `codesign --verify --deep --strict --verbose=2 Baplet.app`
   - `codesign -dvv Baplet.app 2>&1 | grep -E "flags=.*runtime|Authority=Developer ID Application|TeamIdentifier"` (flags must include `runtime`, a secure timestamp must be present).
   - `codesign -d --entitlements - Baplet.app` must show only the calendars entitlement, and must not contain `com.apple.security.get-task-allow` (notarization rejects it).
4. **Notarize and staple the app first.** Zip it with `ditto -c -k --keepParent`, submit with `notarytool submit --wait`, then `stapler staple Baplet.app`. Stapling the app means it validates offline even after being dragged out of the DMG.
5. **Create the DMG** with the stapled app and an `/Applications` symlink so users can drag-install. `hdiutil create -srcfolder <staging dir> -format UDZO` is enough. [create-dmg](https://github.com/create-dmg/create-dmg) adds a background and icon layout if you want polish. A `.zip` made with `ditto` also works (Safari unzips it automatically), but a DMG is the usual choice and gives the drag target.
6. **Sign the DMG** (`codesign --sign "Developer ID Application" --timestamp Baplet.dmg`), notarize it, staple it. `release.sh` currently skips signing the DMG and stapling the app. Notarizing only the DMG also works because the ticket covers its contents, but the two-step version is more robust.
7. **Verify** the final artifact as Gatekeeper would:
   - `xcrun stapler validate Baplet.dmg` and `... Baplet.app`
   - `spctl --assess --type open --context context:primary-signature -vv Baplet.dmg` (expect "accepted, source=Notarized Developer ID")
   - `spctl --assess --type execute -vv Baplet.app`
   - Final manual test on a clean Mac or user account: download the DMG through a browser (so it gets the quarantine flag), open, drag, double-click. No dialog other than the usual "downloaded from the internet" prompt should appear. Do this before announcing the first release.
8. **Publish.** Name the file `Baplet-<version>.dmg` and also keep a stable `Baplet.dmg` alias if you want a fixed "latest" link.

### Where to host downloads

> **Update (2026-11-14):** the repo is now public, so its own GitHub Releases are publicly downloadable. The separate releases repo and `RELEASES_REPO` below are no longer needed; keep releases on `konkord-io/baplet`. The rest of this subsection is kept for reference.

A GitHub Release attached to a private repo is only downloadable by people with repo access, so it does not give a share-able link. Options:

- A **separate public repo** (for example `konkord-io/baplet-releases`) that holds only releases. CI creates the release there with a token that can write to it. This is free and keeps the source private. It needs a fine-grained personal access token or a GitHub App token as a secret, because `GITHUB_TOKEN` is scoped to the current repo.
- **Object storage or your own site** (S3, Cloudflare R2, a static site). Costs pennies, gives a branded URL, and gives a place for a Sparkle appcast later.
- **Make the source repo public.** Simplest, but a decision about the code itself (the README says "All rights reserved").

The workflow below assumes the separate public releases repo and keeps a `RELEASES_REPO` variable so it is easy to change.

### Cost of CI on GitHub

> **Update (2026-11-14):** the repo is public, and GitHub-hosted standard runners (macOS included) are free for public repos, so the quota below no longer applies. The first CI run took 42 seconds.

The organisation is on the Free plan: 2,000 included minutes per month, and macOS minutes count 10x, so about 200 macOS minutes. See [About billing for GitHub Actions](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions). A release run (build plus two notarization waits) is roughly 10 to 20 runner minutes, so 100 to 200 billed minutes per release. That is one or two releases a month on the free quota, which is fine for a release-on-tag workflow. Do not run this workflow on every push. Build-only PR checks should be a separate, unsigned workflow or be skipped (build locally). Overage is billed per minute at the macOS rate. Verify current rates on the billing page. The same pipeline run on your own Mac costs nothing, and `release.sh` stays as the fallback.

### Proposed workflow (not created)

Triggers on a `v*` tag. It needs a macOS runner image that has the Xcode version you build with. Check the exact `Xcode_26.x.app` name against the [runner-images software list](https://github.com/actions/runner-images) before using it, and pin actions by commit SHA once chosen.

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: macos-26
    timeout-minutes: 60
    env:
      TEAM_ID: ${{ vars.APPLE_TEAM_ID }}
      RELEASES_REPO: ${{ vars.RELEASES_REPO }}   # e.g. konkord-io/baplet-releases
      XCODE_APP: /Applications/Xcode_26.3.app     # verify against runner-images
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: |
          sudo xcode-select -s "$XCODE_APP/Contents/Developer"
          xcodebuild -version

      - name: Compute version
        id: ver
        run: |
          echo "marketing=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"
          echo "build=${{ github.run_number }}" >> "$GITHUB_OUTPUT"

      - name: Import certificate into temporary keychain
        env:
          CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_CERT_P12_BASE64 }}
          CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/build.keychain-db"
          KEYCHAIN_PASSWORD="$(uuidgen)"
          echo "KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
          echo "$CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security import "$RUNNER_TEMP/cert.p12" -P "$CERT_PASSWORD" \
            -A -t cert -f pkcs12 -k "$KEYCHAIN"
          security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
          security find-identity -v -p codesigning "$KEYCHAIN"
          rm -f "$RUNNER_TEMP/cert.p12"

      - name: Write notarization API key
        env:
          ASC_KEY_P8_BASE64: ${{ secrets.ASC_API_KEY_P8_BASE64 }}
        run: |
          echo "$ASC_KEY_P8_BASE64" | base64 --decode > "$RUNNER_TEMP/AuthKey.p8"
          echo "NOTARY_KEY=$RUNNER_TEMP/AuthKey.p8" >> "$GITHUB_ENV"

      - name: Archive
        run: |
          xcodebuild archive \
            -project baplet.xcodeproj -scheme baplet -configuration Release \
            -archivePath build/Baplet.xcarchive \
            MARKETING_VERSION="${{ steps.ver.outputs.marketing }}" \
            CURRENT_PROJECT_VERSION="${{ steps.ver.outputs.build }}" \
            CODE_SIGN_STYLE=Manual \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN"

      - name: Export (Developer ID)
        run: |
          cat > build/ExportOptions.ci.plist <<EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0"><dict>
            <key>method</key><string>developer-id</string>
            <key>teamID</key><string>$TEAM_ID</string>
            <key>signingStyle</key><string>manual</string>
            <key>signingCertificate</key><string>Developer ID Application</string>
          </dict></plist>
          EOF
          xcodebuild -exportArchive \
            -archivePath build/Baplet.xcarchive \
            -exportOptionsPlist build/ExportOptions.ci.plist \
            -exportPath build/export

      - name: Verify signature and hardened runtime
        run: |
          APP=build/export/Baplet.app
          codesign --verify --deep --strict --verbose=2 "$APP"
          codesign -dvv "$APP" 2>&1 | tee build/codesign.txt
          grep -q "flags=0x[0-9a-f]*(runtime)" build/codesign.txt
          grep -q "Authority=Developer ID Application" build/codesign.txt
          codesign -d --entitlements - "$APP" 2>&1 | tee build/entitlements.txt
          ! grep -q "get-task-allow" build/entitlements.txt

      - name: Notarize and staple app
        run: |
          ditto -c -k --keepParent build/export/Baplet.app build/Baplet-app.zip
          xcrun notarytool submit build/Baplet-app.zip --wait \
            --key "$NOTARY_KEY" \
            --key-id "${{ secrets.ASC_KEY_ID }}" \
            --issuer "${{ secrets.ASC_ISSUER_ID }}"
          xcrun stapler staple build/export/Baplet.app

      - name: Build, sign, notarize and staple DMG
        run: |
          VERSION="${{ steps.ver.outputs.marketing }}"
          mkdir -p build/dmg
          cp -R build/export/Baplet.app build/dmg/
          ln -s /Applications build/dmg/Applications
          hdiutil create -volname Baplet -srcfolder build/dmg -ov -format UDZO "build/Baplet-$VERSION.dmg"
          codesign --sign "Developer ID Application" --timestamp --keychain "$KEYCHAIN" "build/Baplet-$VERSION.dmg"
          xcrun notarytool submit "build/Baplet-$VERSION.dmg" --wait \
            --key "$NOTARY_KEY" \
            --key-id "${{ secrets.ASC_KEY_ID }}" \
            --issuer "${{ secrets.ASC_ISSUER_ID }}"
          xcrun stapler staple "build/Baplet-$VERSION.dmg"

      - name: Gatekeeper checks
        run: |
          VERSION="${{ steps.ver.outputs.marketing }}"
          xcrun stapler validate "build/Baplet-$VERSION.dmg"
          xcrun stapler validate build/export/Baplet.app
          spctl --assess --type open --context context:primary-signature -vv "build/Baplet-$VERSION.dmg"
          spctl --assess --type execute -vv build/export/Baplet.app

      - name: Publish release
        env:
          GH_TOKEN: ${{ secrets.RELEASES_REPO_TOKEN }}
        run: |
          VERSION="${{ steps.ver.outputs.marketing }}"
          gh release create "$GITHUB_REF_NAME" "build/Baplet-$VERSION.dmg" \
            --repo "$RELEASES_REPO" --title "Baplet $VERSION" --generate-notes

      - name: Cleanup
        if: always()
        run: |
          security delete-keychain "$KEYCHAIN" || true
          rm -f "$NOTARY_KEY" "$RUNNER_TEMP/cert.p12"
```

Secrets and variables it needs (repository Settings, Secrets and variables, Actions):

| Name | Kind | Content |
| --- | --- | --- |
| `DEVELOPER_ID_CERT_P12_BASE64` | secret | `base64 -i cert.p12 \| pbcopy` of the exported Developer ID Application certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | secret | the `.p12` export password |
| `ASC_API_KEY_P8_BASE64` | secret | `base64 -i AuthKey_XXXX.p8` |
| `ASC_KEY_ID` | secret | Key ID of the API key |
| `ASC_ISSUER_ID` | secret | Issuer ID (UUID) from the Integrations page |
| `RELEASES_REPO_TOKEN` | secret | fine-grained PAT with Contents: read and write on the releases repo only (not needed if releases stay in the private repo) |
| `APPLE_TEAM_ID` | variable | the Team ID (not secret) |
| `RELEASES_REPO` | variable | `owner/repo` that receives releases |

Notes on the workflow:
- The keychain password is generated per run, never stored. The keychain is deleted in an `always()` cleanup step. GitHub-hosted runners are discarded after the job anyway; the cleanup matters if you ever move to a self-hosted Mac. See GitHub's guide [Installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/use-cases-and-examples/deploying/installing-an-apple-certificate-on-macos-runners-for-xcode-development) (the keychain recipe here follows it).
- Tag push is the only trigger. Protect tags (repository rules) so only maintainers can create `v*` tags, since a tag is what spends the signing secrets. Use a GitHub Environment named `release` with required reviewers if you want a manual approval before secrets are exposed.
- Secrets are not available to workflows triggered from forks, which is what you want.
- `release.sh` pipes `xcodebuild` through `tail -1`, which hides errors in logs. The workflow does not. Consider `xcbeautify` for readable logs.
- I did not verify that `macos-26` is the right label or which Xcode 26.x is installed. Check the runner-images list.

### How `release.sh` relates

`release.sh` has the right shape. I recommend it becomes the single implementation of build, sign and notarize, with CI only preparing the keychain and secrets and then calling it. That keeps local and CI releases identical. Changes it needs:

1. Accept `MARKETING_VERSION` and build number (arguments or env) and pass them to `xcodebuild`.
2. Authenticate `notarytool` with the API key when `NOTARY_KEY`, `ASC_KEY_ID`, `ASC_ISSUER_ID` are set, and with the keychain profile otherwise. Update the stored-credentials hint to the API key form.
3. Use a manual-signing export plist when running in CI (or always, if you prefer one behaviour).
4. Notarize and staple the app before building the DMG, add the `/Applications` symlink, sign the DMG.
5. Add the verification steps above.
6. Stop swallowing output with `tail -1`.

Until then the workflow above is self-contained and does not call the script. If you adopt the script approach, the Archive through Gatekeeper-check steps collapse into one `scripts/release.sh` call. The script is 100% reusable on a laptop for a quick hotfix when CI is down.

## Updates for direct-download users

Without an updater, users stay on whatever version they downloaded and you have no way to push a fix. For a menu bar app that runs all day, that matters. [Sparkle 2](https://sparkle-project.org/) is the standard solution.

- **Needed now?** No. For the first release to a few people, "download the new DMG" is acceptable. Add Sparkle before you promote the app widely, or before you ship a release you expect to need hotfixes for. Recommended target: version 1.1.
- **What it takes.** Add Sparkle through Swift Package Manager (add its license to `OpenSourcePackage.all`, as `CLAUDE.md` requires, and add the version to the pinned set). Generate an EdDSA key pair with `generate_keys` (the private key goes in your keychain and into a CI secret, for example `SPARKLE_ED_PRIVATE_KEY`). Add `SUFeedURL` and `SUPublicEDKey` to the Info.plist. Add a "Check for Updates" item. Host an `appcast.xml` plus the update archives over HTTPS. CI runs `generate_appcast` or `sign_update` after notarizing and uploads the appcast. The not-sandboxed app avoids Sparkle's extra sandbox setup (XPC services and mach-lookup entitlements).
- **Cost.** Software is free (MIT-style license). Work is roughly one to two days including the CI step. Hosting: the appcast and archives must be fetchable without authentication, which brings back the private-repo problem. A public releases repo with the appcast on GitHub Pages, or a static site, works.
- **Constraints.** Updates must be signed with the same Developer ID and notarized, and the Sparkle EdDSA key must never be lost (users could no longer be updated). Sparkle must be compiled out of the App Store variant, because the App Store forbids self-updating.

## Phase 2: Mac App Store

> **Deferred (2026-11-14):** the owner chose to distribute from their own website (Phase 1) and park the App Store for now. Keep this section as reference; don't start on it without a new decision.

### The sandbox problem and the plan

The Mac App Store requires `com.apple.security.app-sandbox` ([App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)). Baplet's profile picker needs two things the sandbox blocks (tested earlier): reading other browsers' profile files and passing launch arguments to the browser.

Options I considered:

- **A. Separate App Store variant with profile selection removed (recommended).** A second build configuration with the sandbox on, built from the same code with a compile flag. Browser choice stays, profile choice goes.
- **B. Temporary-exception entitlements** (`com.apple.security.temporary-exception.files.home-relative-path.read-only` for the browsers' folders). Reading the files might work, but launching with profile arguments is still blocked, so it solves only half the problem. App Review also tends to reject broad temporary exceptions. Not recommended.
- **C. User-granted access via an open panel** (`com.apple.security.files.user-selected.read-only` plus security-scoped bookmarks). Same problem: reading works, launching with arguments does not.
- **D. One sandboxed app for everyone and drop profile selection entirely.** Simplest to maintain, but takes a feature away from direct-download users who already have it. It is the fallback if two variants turn out to cost too much.

**Plan for A.**
- New build configuration `Release-AppStore` (and a scheme `baplet-appstore`) in the same target. It sets `ENABLE_APP_SANDBOX = YES`, `CODE_SIGN_ENTITLEMENTS = baplet/baplet-appstore.entitlements`, and `SWIFT_ACTIVE_COMPILATION_CONDITIONS = APPSTORE`.
- `baplet-appstore.entitlements`: `com.apple.security.app-sandbox` = true, and `com.apple.security.personal-information.calendars` = true. No network client entitlement is needed unless code makes network requests (Baplet currently only opens links via `NSWorkspace`; verify when implementing). No hardened-runtime setting needed: App Store builds are always signed with hardened runtime requirements handled at upload.
- Under `#if APPSTORE`: `BrowserService` lists browsers via `NSWorkspace` and opens meeting links in the chosen browser without profile arguments; the profile picker in Settings, Meetings is hidden. Without a choice it opens in the chosen browser's default profile. Verify in the sandbox that opening a URL with a specific application (`NSWorkspace.open(_:withApplicationAt:configuration:)`) works; the browser list uses `NSWorkspace.urlsForApplications(toOpen:)`, which I expect to work but have not tested.
- Same bundle ID `io.konkord.baplet`, so one product identity. The two variants cannot both be installed at once without confusing each other (same ID); that is normal and acceptable for a menu bar utility, but say so in release notes.
- Sparkle code excluded under `#if APPSTORE` (and the package linked only in the direct configuration).

**What the App Store variant loses:** the browser-profile picker (and the Chrome and Firefox profile reading behind it), self-updating through Sparkle (App Store handles updates instead), and any future feature that needs arbitrary file access or launching other apps with arguments.

**How settings differ.** A sandboxed build stores `UserDefaults` in `~/Library/Containers/io.konkord.baplet/Data/Library/Preferences/io.konkord.baplet.plist` and the direct build in `~/Library/Preferences/io.konkord.baplet.plist`. Consequences:
- `SettingsStore` already migrates from the old container on first launch of the unsandboxed build (`SettingsStore.swift`, around line 214). That migration must be compiled out of the App Store variant, where `UserDefaults.standard` already is the container, and the sandbox would not allow reading the unsandboxed plist.
- There is no automatic way to carry settings from the direct build to the App Store build (or back). If that matters, add Export and Import of settings as a small JSON file through an open or save panel (works in both). Otherwise tell users they start fresh.
- Calendar permission is granted per signing identity, so moving between variants prompts again.
- `CLAUDE.md` instructions about reading prefs by path apply to the direct build only. Add a note for the App Store build.

### KeyboardShortcuts and the App Store

KeyboardShortcuts is built on the Carbon `RegisterEventHotKey` API, which works inside the sandbox without extra entitlements and is used by shipping Mac App Store apps. The package's README states it is sandbox- and App Store-compatible (verify on the 3.1.0 README when implementing). Two caveats: it requires macOS 10.15+, which is no problem at macOS 26.3, and global hotkeys that conflict with system or menu shortcuts are rejected at record time by the library itself. It adds a privacy manifest question, see below. Also confirm that the package ships a `PrivacyInfo.xcprivacy` or that Xcode reports no missing privacy manifest for it when archiving, since Apple requires privacy manifests for listed third-party SDKs ([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)). I did not check this.

### App Store Connect setup

- Agree to the **Paid Apps Agreement** and enter banking and tax info (Business section). Needed before charging anything. Free apps need no banking.
- Create the app record (My Apps, `+`, New App): platform macOS, bundle ID `io.konkord.baplet`, SKU, primary language.
- Listing: name (must be unique on the Store, so "Baplet" may be taken), subtitle, description, keywords, category (Productivity), screenshots (Mac sizes, at least one), 1024x1024 icon, support URL, **privacy policy URL** (required), copyright.
- **App Privacy** questionnaire: Baplet reads calendars on device and, as far as I can tell, collects nothing. "Data Not Collected" if that stays true.
- **Export compliance:** set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` so uploads are not blocked on the encryption question (the app only uses standard OS cryptography, if any).
- Pricing: paid upfront or free with in-app purchase. Apple takes 30%, or 15% under the [Small Business Program](https://developer.apple.com/app-store/small-business-program/) (under US$1M proceeds a year, application required). No licence-key system is needed for a paid upfront app.
- Age rating questionnaire, review notes (explain why calendar access is needed, that it is a menu bar app with no Dock icon, and how to open Settings).
- Signing material: **Apple Distribution** certificate (Mac App Store apps are signed with it; the older "3rd Party Mac Developer Application" also exists) and a **Mac App Store provisioning profile** for the bundle ID. With Xcode managed signing or cloud signing you do not create these by hand. Details in [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

### TestFlight for Mac

Builds uploaded to App Store Connect appear in TestFlight automatically. Internal testers (up to 100 people with App Store Connect roles) can install without review. External testers (up to 10,000, invited by email or public link) need Beta App Review for the first build of each version. Testers install through the TestFlight app on macOS and builds expire after 90 days. This is also the practical way to test the sandboxed variant on other Macs. See [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

### CI path for the App Store

Options, with my recommendation first:

1. **GitHub Actions with `xcodebuild` cloud signing and upload (recommended).** Archive the `baplet-appstore` scheme, then `xcodebuild -exportArchive` with an options plist containing `method` = `app-store-connect` and `destination` = `upload`, run with `-allowProvisioningUpdates -authenticationKeyPath AuthKey.p8 -authenticationKeyID ... -authenticationKeyIssuerID ...`. Xcode then creates or fetches the distribution certificate and profile through the API and uploads the build, with no certificate import step. This needs an API key with the **Admin** role (or App Manager with cloud-managed certificate access; check the current role requirements in Apple's docs when setting it up). Same secrets as notarization, plus the key role. Build number comes from `github.run_number`, the same counter as Phase 1. Trigger: a separate tag pattern (for example `appstore-v*`), or a `workflow_dispatch` with a version input, so that a direct-download release and a Store build are independent decisions.
2. **Export a `.pkg` and upload with `xcrun altool --upload-app -f Baplet.pkg -t macos --apiKey ... --apiIssuer ...`**, or with the Transporter app/CLI. Works with manually imported Apple Distribution and Mac Installer Distribution certificates. More secrets (two more certificates). Note `altool`'s validation features are deprecated in favour of newer tooling, but uploads were still documented when I checked; verify.
3. **Xcode Cloud.** Apple's hosted CI, configured in Xcode and App Store Connect, builds, signs automatically and distributes straight to TestFlight, with no certificates or secrets to manage. It includes a monthly free compute-hour allowance with the Developer Program membership (25 hours when I last saw it; check [Xcode Cloud pricing](https://developer.apple.com/xcode-cloud/)). It must be granted access to the private GitHub repo. It cannot replace the Developer ID notarize-and-publish pipeline in Phase 1, so you would run two CI systems. Good choice if you prefer to avoid secret handling for the Store build. Verify what macOS post-actions it supports before committing.
4. **fastlane.** Fine, but adds Ruby tooling for steps that `xcodebuild` and `notarytool` already cover.

Whichever you pick, App Store Connect rejects a build whose build number is not higher than the previous one for the same version.

### Review risks

- **Calendar usage description.** `NSCalendarsFullAccessUsageDescription` exists: "Baplet needs access to your calendars to display upcoming events." Make it say what is done with the data (alerts only, nothing leaves the Mac), because reviewers check that the purpose string matches behaviour. Full access (not write-only) is justified because the app reads events. Be ready to explain this in the review notes.
- **Global hotkeys.** Allowed: Carbon hotkeys need no accessibility permission and ship in many Store apps. Keep the hotkey optional with no default (already the case), so nothing intercepts keys unexpectedly.
- **LSUIElement (agent app).** Allowed and common. Reviewers must be able to find the app: say in the review notes that it lives in the menu bar and how to open Settings. Make sure the first-run welcome guide (`OnboardingView`) appears reliably on a fresh container, since it is the reviewer's first impression. If the menu bar icon is hidden by a crowded menu bar on the reviewer's Mac, a reviewer who cannot find the app rejects it. The guide helps.
- **Full-screen alerts.** The borderless full-screen alert at `.popUpMenu - 1` takes over the screen. Make sure it is always dismissible (Esc, Return, click) so it cannot be read as locking the user's Mac. Guideline 2.4.5 (Mac apps) and 4.x design guidelines are the relevant ones to re-read. See [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- **Sandbox leftovers.** Any code path touching files outside the container, or opening other apps with arguments, will fail or crash only in the sandbox. Test the sandboxed variant on a clean account, not just on your dev Mac.
- **Metadata.** Missing privacy policy URL, placeholder screenshots ("Coming soon" in the README is a sign this is not ready) and a name clash are the commonest rejections for a first submission.
- **Minimum OS.** The deployment target is macOS 26.3, so only users on a very recent macOS can install it. This shrinks the audience for sales. Consider whether 26.0 or lower works for the Store build (Phase 2 only; decision below).

## Costs and timeline

| Item | Cost | Notes |
| --- | --- | --- |
| Apple Developer Program | US$99/yr | Needed for everything beyond the free workaround. Renew yearly or distribution stops and the Store listing is removed. |
| Developer ID certificate | included | Valid 5 years; renewable. |
| Notarization | free | Typically a few minutes per submission. |
| GitHub Actions macOS minutes | free (public repo) | No quota for standard runners on public repos. |
| Download hosting | free (GitHub releases repo) to a few dollars/month | Domain for a nicer link about US$10 to 20/yr. |
| Sparkle | free software, 1 to 2 days work | Hosting as above. |
| App Store commission | 30%, or 15% under the Small Business Program | Taken from sales, no listing fee beyond the membership. |
| Xcode Cloud | free allowance included with membership, then paid tiers | Optional. |

Rough timeline (elapsed, assuming evenings and weekends):

- Enrolment: same day to a few days for an Individual. Organization with D-U-N-S can take one to several weeks.
- Phase 0 remaining steps: about 1 hour once enrolled.
- Phase 1: first manual notarized DMG in about half a day. CI workflow and secrets about one more day, mostly debugging notarization and keychain issues. A clean-Mac test before announcing.
- Sparkle: one to two days, ideally for 1.1.
- Phase 2: one to two weeks of work (variant configuration, settings migration split, sandbox testing, listing assets, privacy policy, TestFlight round) plus review, typically one to three days per submission and sometimes more for a first submission. Plan for at least one rejection round.

## Open decisions for the owner

1. **Individual or Organization enrolment.** Individual: fast, your legal name is shown as seller on the Store and in "identified developer" dialogs. Organization (konkord-io as a legal entity): company name shown, needs D-U-N-S and takes longer. Recommendation: Individual now. Apple supports moving an app to an organisation later through app transfer, but check if that matches your plans for selling.
2. **Where to host downloads.** *Decided 2026-11-14:* GitHub Releases on the now-public source repo; `baplet.konkord.io` on Cloudflare Pages (DMG is about 1.7 MB, well under the 25 MiB per-file limit) when the site is built.
3. **One sandboxed app or two variants (Phase 2).** Recommendation: two variants from one codebase (direct build keeps browser profiles, App Store build hides them), with a compile flag, not a fork.
4. **Whether Phase 2 is worth it.** The Store costs 15 to 30% of revenue, removes a feature, needs privacy policy and review upkeep, and a macOS 26.3 floor limits buyers. Recommendation: finish Phase 1 and observe real interest first. Revisit the Store once there are users asking for it or you want paid distribution.
5. **Sparkle timing.** Recommendation: ship 1.0 without it, add in 1.1.
6. **Settings carry-over between variants.** Recommendation: add JSON export and import of settings when you build the App Store variant, rather than silently starting users fresh.
7. **CI for the Store build.** Recommendation: GitHub Actions with `xcodebuild` cloud signing and upload, in a separate workflow. Choose Xcode Cloud instead if you want no secrets for that path.
8. **Release trigger and approval.** Recommendation: `v*` tag push, with tag protection and a `release` Environment requiring your approval before the secrets are exposed.
9. **Minimum macOS version.** Recommendation: check whether the code builds with a lower deployment target (for example 15.0 as the README says) before widening the audience. This is a code question that only you can weigh against features that need macOS 26.
10. **Pricing and name for the Store.** Free, paid upfront, or free with in-app purchase; confirm "Baplet" is available as an App Store name. Recommendation: paid upfront with a small one-time price, decided after Phase 1 feedback.
11. **Whether to refactor `release.sh` into the single implementation** (recommended) or keep CI inline and the script as a manual fallback.
