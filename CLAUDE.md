# Baplet

macOS menu bar app (SwiftUI, `MenuBarExtra`) that fires alarm alerts before calendar events, read via EventKit. Agent-only app (`LSUIElement`), hardened runtime with the calendar entitlement, deliberately **not sandboxed**: choosing a browser profile for meeting links needs to read other browsers' profile files and pass launch arguments, and the sandbox blocks both.

## Build

`make` opens an interactive menu; `make run | run-logs | test | build | stop | clean | xcode | reset` run the same tasks directly (`reset` has its own menu: `reset-welcome`, `reset-settings`, `reset-calendar`, `reset-all`; add `FORCE=1` to skip the confirmation) (builds go to `build/DerivedData`, git-ignored). Prefer these over hand-written xcodebuild lines. The raw commands below are what the Makefile wraps.

`xcode-select` points at CommandLineTools on this machine, so prefix with `DEVELOPER_DIR`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project baplet.xcodeproj -scheme baplet -configuration Debug build
```

Unit tests (Swift Testing, target `bapletTests`, hosted by the app, which skips its startup under tests via `AppEnvironment.isRunningTests`) run with:

```sh
pkill -x Baplet; DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project baplet.xcodeproj -scheme baplet -destination 'platform=macOS'
```

CI (`.github/workflows/ci.yml`) runs `make test ADHOC=1 VERBOSE=1` on every PR and push to main (`macos-26`, Xcode 26.6). Pushing a `v*` tag runs `release.yml`, which tests, builds `make dmg` (ad-hoc signed, not notarized) and creates a **draft** GitHub Release; publishing it stays manual. `ADHOC=1` signs without a certificate, and `VERBOSE=1` shows full xcodebuild output. The tests they cover pure logic only (meeting links, browser profiles, Today selection, alarm keys, settings migrations). Check UI changes by running the app (`/run`). Launch the built app with `open` (add `--stdout`/`--stderr <file>` to capture `NSLog`); executing the binary directly makes the terminal the TCC-responsible process, so calendar status comes back as the terminal's. The app's prefs live in `~/Library/Preferences/io.konkord.baplet.plist`; read them by path (`defaults read ~/Library/Preferences/io.konkord.baplet.plist`), because `defaults read io.konkord.baplet` resolves to the old sandbox container while it exists. Settings from the sandboxed era sit in `~/Library/Containers/io.konkord.baplet/`; `SettingsStore` copies them over once on first launch. After editing a plist by hand, `killall -u $USER cfprefsd` or the app keeps reading cached values. Release pipeline: `scripts/release.sh` (archive → Developer ID export → DMG → notarize → staple).

## Architecture

Three `@Observable` singletons are created in `BapletApp.swift` and injected with `.environment(...)` into both scenes (the menu bar window and the `settings` window):

- `CalendarService`: EventKit access, calendar list, event fetching.
- `SettingsStore`: user preferences persisted to `UserDefaults`; owns legacy-key migrations (keep them when renaming keys).
- `AlarmManager`: 30 s `Timer` loop that decides when to fire, tracks dismiss/snooze, and computes `MenuBarStatus` (menu bar icon + countdown). One alert at a time: other due events wait, and the next one is shown as soon as the open alert is dismissed, snoozed or opened.

Per-event alarm state (disabled, snoozed, alerting) is keyed per occurrence by `EKEvent.alarmKey` (`eventIdentifier|start`, in `EKEvent+Baplet.swift`), because occurrences of a recurring event share `eventIdentifier`. Use `alarmKey`, `displayTitle` and `EventTimeFormat` rather than reading those fields directly.

Startup (access request, event load, `AlarmManager.start`, and when no calendars are selected opening the welcome guide `OnboardingView` until it has been finished once, Settings after that) lives in `MenuBarLabel`'s `.task`: the label renders at launch, while the `MenuBarExtra` window content is built lazily on first click. `MenuBarLabel` also re-fetches events whenever the calendar selection or `daysToShow` changes, so views that change them only set the value. Fetch through `CalendarService.fetchEvents(for:)`.

`BrowserService` lists browsers that open `https` links, reads Chromium (`Local State`) and Firefox (`profiles.ini`) profiles, and opens meeting links in the browser/profile chosen in Settings → Meetings. Every meeting link goes through `BrowserService.openMeeting`.

`TodayPanel` is a Spotlight-like floating panel of today's events (reusing `CalendarEventRow`), opened from the menu header or the global shortcut `KeyboardShortcuts.Name.showToday`. That shortcut comes from the KeyboardShortcuts package (pinned to an exact version; `Package.resolved` is committed), is registered in `MenuBarLabel.startUp` and has no default. The panel's keys (↑↓, Return/⌘Return per `SettingsStore.todayReturnAction`, D) are handled by a `PanelKeyMonitor` in `TodayPanel`, with the selection in `TodayListModel`.

`AlertService` is an enum that does the AppKit work SwiftUI can't: `NSPanel` alerts (floating popup, or borderless full screen) via `AlertService.show(style:props:)`, sound, meeting-link extraction, opening events in Calendar (`openEventInCalendar(_:)`), and the O/D/S/Return keyboard shortcuts. It holds the one alert on screen; an alert closed with its close button or replaced by another (e.g. Test Alert) is snoozed for `AlertProps.defaultSnoozeMinutes`, never dropped. The full-screen panel sits at `.popUpMenu - 1`: any higher and SwiftUI `Menu` dropdowns open behind it.

Alert views: `AlertPopupView` and every full-screen style take `AlertProps`; `FullScreenAlertRouter` picks the full-screen view for the chosen `AlertStyle`. A new style = new `AlertStyle` case + view + router branch.

## Website and README

`site/` is the public site `baplet.konkord.io`, deployed by `.github/workflows/pages.yml` when `site/` changes on main. Its Download button and the README's download link point at `releases/latest/download/Baplet.dmg`, so the version follows releases automatically. Everything else on the site is hand-written and drifts unless kept in step.

- **Same PR rule:** a change users can notice also updates `site/index.html` and the README in the same PR. That covers a feature added, removed or renamed; the macOS requirement; install steps; and signing or notarization status.
- **Session-start check:** at the start of a session, before other work, compare the site with reality and report any drift to the user (don't fix it silently):
  1. The latest release: `gh release view --repo konkord-io/baplet --json tagName,publishedAt`. Note when there is none, since the Download button then 404s.
  2. "macOS 26.3 or later" on the site and README against `MACOSX_DEPLOYMENT_TARGET` in `project.pbxproj`.
  3. The "not signed by Apple yet" notice and install steps against how `release.yml` signs. Once Developer ID + notarization is in, they must go.
  4. The four feature tiles against the features merged since the site last changed (`git log --oneline -- site/` against `git log --oneline main`).

## Conventions

- The Xcode project uses a file-system-synchronized group: files added under `baplet/` join the target automatically, so `project.pbxproj` needs no edit.
- Every function gets a `///` doc comment explaining what it does and why; code itself carries no inline comments.
- Deployment target is macOS 26.3 (README's "macOS 15.0+" is stale).
- Bundle ID `io.konkord.baplet`, team `H2MCB54VDW`. Changing the bundle ID resets users' `UserDefaults` and calendar permission.
- `design/` holds the untouched original artwork (logo SVG/PNG, menu bar PDF, alert image). The asset catalog has working copies (some downscaled). Keep every original and every image asset, even ones the code no longer references. When swapping an image, only change the references.
- Adding a third-party dependency means adding its entry (name, license, URL, full license text) to `OpenSourcePackage.all` in `OpenSourcePackages.swift`. The About tab credits it from there and shows its "Open Source" section only when that list is non-empty.
- Baplet is MIT licensed. `LICENSE` at the repo root and `OpenSourcePackage.baplet.licenseText` (shown in About) must stay identical.
