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

- macOS 15.0+
- Xcode 26+
- Calendar access permission

## Building

1. Open `baplet.xcodeproj` in Xcode
2. Select the `baplet` scheme
3. Build and run (Cmd+R)

On first launch the app will request calendar access. Grant full access for all features to work.

## Sharing the app with friends (no Apple Developer Program needed)

You can share the built app for free without paying the $99/yr Apple Developer Program fee. Your friends just have to bypass Gatekeeper once on first launch.

### Build a shareable `.app`

1. In Xcode: **Product → Archive** → in the Organizer, **Distribute App → Custom → Copy App** → pick a folder. You get a `Baplet.app` signed with your free "Apple Development" cert.
2. Strip quarantine attributes and zip it:
   ```sh
   xattr -cr Baplet.app
   ditto -c -k --keepParent Baplet.app Baplet.zip
   ```
3. Send `Baplet.zip` to your friends (email, Dropbox, GitHub release, etc.).

### What your friends do

1. Unzip and drag `Baplet.app` to `/Applications`.
2. **First launch:** double-click → macOS will say "cannot be opened because the developer cannot be verified."
3. Open **System Settings → Privacy & Security**, scroll to the bottom, click **"Open Anyway"** next to the Baplet message. Confirm.

After that one-time approval the app launches normally forever.

If that's too much friction, your friend can run this single terminal command instead, and the app opens with no warning at all:

```sh
xattr -dr com.apple.quarantine /Applications/Baplet.app
```

### Trade-offs vs the paid path

|                              | Free (Apple Development cert)                  | Paid ($99/yr, Developer ID + notarize) |
| ---------------------------- | ---------------------------------------------- | -------------------------------------- |
| Cost                         | $0                                             | $99/yr                                 |
| Friend's first launch        | Manual Privacy & Security approval             | Just double-click                      |
| Cert lifetime                | ~1 year (Apple Development)                    | 5 years                                |
| Can be hosted publicly       | Yes, but with scary warnings                   | Yes, clean                             |
| Auto-update tools (Sparkle)  | Works, but re-signing breaks updates           | Works cleanly                          |

For sharing with a handful of friends, the free path is fine. For public download links or wider distribution, see `scripts/release.sh` for the paid notarized-DMG pipeline.

## License

Baplet is released under the [MIT License](LICENSE). © 2026 Jakob Vad Nielsen.
