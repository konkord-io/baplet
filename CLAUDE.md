# Baplet

macOS menu bar app (SwiftUI, `MenuBarExtra`) that fires alarm alerts before calendar events, read via EventKit. Agent-only app (`LSUIElement`), hardened runtime with the calendar entitlement, deliberately **not sandboxed**: choosing a browser profile for meeting links needs to read other browsers' profile files and pass launch arguments, and the sandbox blocks both.

## Build

`xcode-select` points at CommandLineTools on this machine, so prefix with `DEVELOPER_DIR`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project baplet.xcodeproj -scheme baplet -configuration Debug build
```

No test target exists. Verify changes by building, then running the app (`/run`). Launch the built app with `open` (add `--stdout`/`--stderr <file>` to capture `NSLog`); executing the binary directly makes the terminal the TCC-responsible process, so calendar status comes back as the terminal's. The app's prefs live in `~/Library/Preferences/io.konkord.baplet.plist`; read them by path (`defaults read ~/Library/Preferences/io.konkord.baplet.plist`), because `defaults read io.konkord.baplet` resolves to the old sandbox container while it exists. Settings from the sandboxed era sit in `~/Library/Containers/io.konkord.baplet/`; `SettingsStore` copies them over once on first launch. After editing a plist by hand, `killall -u $USER cfprefsd` or the app keeps reading cached values. Release pipeline: `scripts/release.sh` (archive → Developer ID export → DMG → notarize → staple).

## Architecture

Three `@Observable` singletons are created in `BapletApp.swift` and injected with `.environment(...)` into both scenes (the menu bar window and the `settings` window):

- `CalendarService`: EventKit access, calendar list, event fetching.
- `SettingsStore`: user preferences persisted to `UserDefaults`; owns legacy-key migrations (keep them when renaming keys).
- `AlarmManager`: 30 s `Timer` loop that decides when to fire, tracks dismiss/snooze, and computes `MenuBarStatus` (menu bar icon + countdown).

Startup (access request, event load, `AlarmManager.start`, and when no calendars are selected opening the welcome guide `OnboardingView` until it has been finished once, Settings after that) lives in `MenuBarLabel`'s `.task`: the label renders at launch, while the `MenuBarExtra` window content is built lazily on first click.

`BrowserService` lists browsers that open `https` links, reads Chromium (`Local State`) and Firefox (`profiles.ini`) profiles, and opens meeting links in the browser/profile chosen in Settings → Meetings. Every meeting link goes through `BrowserService.openMeeting`.

`AlertService` is a stateless enum that does the AppKit work SwiftUI can't: `NSPanel` alerts (floating popup, or borderless full screen), sound, meeting-link extraction, opening events in Calendar, and the O/D/S/Return keyboard shortcuts. The full-screen panel sits at `.popUpMenu - 1`: any higher and SwiftUI `Menu` dropdowns open behind it.

Full-screen alert styles: `FullScreenAlertRouter` picks the view for the chosen `AlertStyle`, each view takes `FullScreenAlertProps`. A new style = new `AlertStyle` case + view + router branch.

## Conventions

- The Xcode project uses a file-system-synchronized group: files added under `baplet/` join the target automatically, so `project.pbxproj` needs no edit.
- Every function gets a `///` doc comment explaining what it does and why; code itself carries no inline comments.
- Deployment target is macOS 26.3 (README's "macOS 15.0+" is stale).
- Bundle ID `io.konkord.baplet`, team `H2MCB54VDW`. Changing the bundle ID resets users' `UserDefaults` and calendar permission.
- `design/` holds the untouched original artwork (logo SVG/PNG, menu bar PDF, alert image). The asset catalog has working copies (some downscaled). Keep every original and every image asset, even ones the code no longer references. When swapping an image, only change the references.
- Adding a third-party dependency means adding its entry (name, license, URL, full license text) to `OpenSourcePackage.all` in `OpenSourcePackages.swift`. The About tab credits it from there and shows its "Open Source" section only when that list is non-empty.
