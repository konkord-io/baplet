# Baplet

A macOS menu bar app that keeps you on top of your calendar events with customizable alarm alerts.

## Features

- **Menu bar integration** — see upcoming events at a glance with a live countdown icon
- **Multiple calendar support** — select which calendars to monitor from all connected sources
- **Customizable alert styles** — choose between four visual styles:
  - Popup Dialog
  - Glassmorphic (frosted glass card)
  - Bold & Minimal (large typography, no card)
  - Warm & Playful (gradient card with hero image)
- **Smart snooze** — snooze alerts for 1, 3, 5, 10, 15, 20, or 30 minutes
- **Meeting link detection** — automatically detects Google Meet, Zoom, Teams, Webex, GoTo Meeting, and Slack Huddle links
- **Open in Calendar** — jump straight to the event in Apple Calendar
- **Configurable lead time** — set how many minutes before an event to trigger the alarm

## Screenshots

*Coming soon*

## Requirements

- macOS 26.3+
- Xcode 26.6 (to build; CI uses the same version)
- Calendar access permission

## Building

From the repo root, run `make` for a menu of developer tasks (run, run with logs, test, build, stop, clean, open in Xcode), or call one directly, e.g. `make run` or `make test`.

Or in Xcode:

1. Open `baplet.xcodeproj` in Xcode
2. Select the `baplet` scheme
3. Build and run (Cmd+R)

On first launch the app will request calendar access. Grant full access for all features to work.

## Releasing

Every pull request and every push to `main` is built and tested by GitHub Actions (`.github/workflows/ci.yml`). Releases are made by pushing a version tag (`.github/workflows/release.yml`).

### Make a release

1. Make sure `main` is green (the CI check on the last merge passed) and pull it locally.
2. Pick the version, using [semantic versioning](https://semver.org): `1.2.3` → `1.2.4` for fixes, `1.3.0` for new features.
3. Tag and push:
   ```sh
   git tag v1.3.0 && git push origin v1.3.0
   ```
4. In about a minute, CI has:
   - run the tests
   - built `Baplet-1.3.0.dmg`. The tag sets the app version, and the GitHub run number becomes the build number.
   - created a **draft** release with the DMG and install notes. It's not public yet.
5. Open **GitHub → Releases**, check the draft (download and try the DMG, edit the notes), then click **Publish release**.

To build the same DMG locally without releasing: `make dmg VERSION=1.3.0`.

### Fixing a mistake

If the build failed or the draft is wrong, delete the draft and the tag, fix `main`, and tag again:

```sh
gh release delete v1.3.0 --yes
git push origin --delete v1.3.0 && git tag -d v1.3.0
```

Once a release is published, don't reuse its version: ship the fix as the next patch version instead.

### Installing a release (for the people you share it with)

1. Open the DMG and drag **Baplet** to **Applications**.
2. Start Baplet. macOS blocks it the first time, because these builds are not notarized yet.
3. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Baplet and confirm. As an alternative, run once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Baplet.app
   ```
4. Allow calendar access when Baplet asks.

They need to do this again for each new version they download.

### Current limitations and the paid path

Release builds are currently ad-hoc signed, because no Apple Developer Program membership is needed. That means:

|                                    | Now (ad-hoc signed)                         | After enrolling ($99/yr, Developer ID + notarization) |
| ---------------------------------- | ------------------------------------------- | ----------------------------------------------------- |
| First launch of each new version   | "Open Anyway" in Privacy & Security         | Just double-click                                     |
| Calendar permission after updates  | Asked again (the signature changes each build) | Kept                                               |
| Downloads                          | Public GitHub Release, with a security warning on first launch | Public, clean (GitHub Releases or baplet.konkord.io) |
| Auto-updates (Sparkle)             | Not practical                               | Possible                                              |

To move to the paid path, follow `docs/distribution.md`. After enrolling, only the signing step of `release.yml` changes (Developer ID + notarization, the steps `scripts/release.sh` already contains). Tagging and publishing stay the same.

## License

Baplet is released under the [MIT License](LICENSE). © 2026 Jakob Vad Nielsen.
