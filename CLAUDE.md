# Baplet

macOS menu bar app (SwiftUI, `MenuBarExtra`) that fires alarm alerts before calendar events, read via EventKit. Agent-only app (`LSUIElement`), sandboxed, calendar entitlement only.

## Build

`xcode-select` points at CommandLineTools on this machine, so prefix with `DEVELOPER_DIR`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project baplet.xcodeproj -scheme baplet -configuration Debug build
```

No test target exists. Verify changes by building, then running the app (`/run`). Release pipeline: `scripts/release.sh` (archive → Developer ID export → DMG → notarize → staple).

## Architecture

Three `@Observable` singletons are created in `BapletApp.swift` and injected with `.environment(...)` into both scenes (the menu bar window and the `settings` window):

- `CalendarService`: EventKit access, calendar list, event fetching.
- `SettingsStore`: user preferences persisted to `UserDefaults`; owns legacy-key migrations (keep them when renaming keys).
- `AlarmManager`: 30 s `Timer` loop that decides when to fire, tracks dismiss/snooze, and computes `MenuBarStatus` (menu bar icon + countdown).

`AlertService` is a stateless enum that does the AppKit work SwiftUI can't: `NSPanel` alerts (floating popup, or borderless `.screenSaver`-level full screen), sound, meeting-link extraction, opening events in Calendar.

Full-screen alert styles: `FullScreenAlertRouter` picks the view for the chosen `AlertStyle`, each view takes `FullScreenAlertProps`. A new style = new `AlertStyle` case + view + router branch.

## Conventions

- The Xcode project uses a file-system-synchronized group: files added under `baplet/` join the target automatically, so `project.pbxproj` needs no edit.
- Every function gets a `///` doc comment explaining what it does and why; code itself carries no inline comments.
- Deployment target is macOS 26.3 (README's "macOS 15.0+" is stale).
- Bundle ID `io.konkord.baplet`, team `H2MCB54VDW`. Changing the bundle ID resets users' `UserDefaults` and calendar permission.
