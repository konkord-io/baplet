//
//  DemoMode.swift
//  baplet
//

import AppKit
import SwiftUI

/// Demo mode for the scripted website screenshots (`make screenshots`). Launched with
/// `-BapletDemo YES`, the app keeps its settings in a separate suite, serves fake calendars and
/// events, and skips calendar access, the welcome guide, the global shortcut and the alarm
/// timer, so it never touches the user's real data. `-BapletDemoScene <name>` opens one view for
/// capture and `-BapletDemoAppearance light|dark` forces the appearance.
enum DemoMode {
    /// True when the app was launched with `-BapletDemo YES` (read from the argument domain).
    static let isEnabled = UserDefaults.standard.bool(forKey: "BapletDemo")

    /// The scene requested with `-BapletDemoScene`, if demo mode is on.
    static let scene: Scene? = isEnabled
        ? UserDefaults.standard.string(forKey: "BapletDemoScene").flatMap(Scene.init(rawValue:))
        : nil

    /// The appearance requested with `-BapletDemoAppearance`, if demo mode is on.
    static var appearance: NSAppearance? {
        guard isEnabled else { return nil }
        switch UserDefaults.standard.string(forKey: "BapletDemoAppearance") {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    /// Preferences suite used instead of the real settings while demo mode is on.
    static let suiteName = "io.konkord.baplet.demo"

    /// The views that can be opened for capture.
    enum Scene: String {
        case menu, today
        case alertPopup = "alert-popup"
        case alertGlass = "alert-glass"
        case alertBold = "alert-bold"
        case alertWarm = "alert-warm"
        case settingsCalendars = "settings-calendars"
        case settingsAlerts = "settings-alerts"
        case settingsMeetings = "settings-meetings"
        case settingsShortcuts = "settings-shortcuts"
        case settingsAbout = "settings-about"
        case welcomeTheme = "welcome-theme"

        /// The alert style this scene shows, or nil for scenes that aren't an alert.
        var alertStyle: AlertStyle? {
            switch self {
            case .alertPopup: .popupDialog
            case .alertGlass: .fullScreenGlassmorphic
            case .alertBold: .fullScreenBoldMinimal
            case .alertWarm: .fullScreenWarmPlayful
            default: nil
            }
        }

        /// The Settings sidebar pane (a `SettingsPane` raw value) this scene opens, or nil.
        var settingsPane: String? {
            switch self {
            case .settingsCalendars: "calendars"
            case .settingsAlerts: "alerts"
            case .settingsMeetings: "meetings"
            case .settingsShortcuts: "shortcuts"
            case .settingsAbout: "about"
            default: nil
            }
        }
    }

    /// The settings store for the app: the demo suite (cleared and filled with sample choices)
    /// in demo mode, the real preferences otherwise.
    static func makeSettingsStore() -> SettingsStore {
        guard isEnabled, let defaults = UserDefaults(suiteName: suiteName) else { return SettingsStore() }
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults, sandboxContainerPlist: nil)
        store.alertStyle = scene?.alertStyle ?? .fullScreenGlassmorphic
        store.onboardingCompleted = true
        return store
    }

    /// Applies the requested appearance, then opens the requested scene. Run once from the
    /// menu bar label's startup instead of the normal startup.
    @MainActor
    static func start(
        calendarService: CalendarService,
        settingsStore: SettingsStore,
        openWindow: OpenWindowAction
    ) {
        NSApp.appearance = appearance
        calendarService.loadCalendars()
        settingsStore.enabledCalendarIDs = calendarService.allCalendarIDs
        calendarService.fetchEvents(for: settingsStore)
        guard let scene else { return }

        NSApp.activate(ignoringOtherApps: true)
        showBackdrop()
        defer { raiseSceneAboveBackdrop() }
        if let style = scene.alertStyle {
            showAlert(style: style)
        } else if scene.settingsPane != nil {
            openWindow.openSettings()
        } else if scene == .welcomeTheme {
            openWindow.openWelcome()
        } else if scene == .today {
            TodayPanel.show(calendarService: calendarService, settingsStore: settingsStore)
        } else if scene == .menu {
            showMenuWindow(calendarService: calendarService, settingsStore: settingsStore)
        }
    }

    /// The plain backdrop behind the captured scene, kept alive while the demo runs.
    private static var backdrop: NSWindow?

    /// The backdrop's window level: above other apps' windows and panels, the Dock and the
    /// menu bar, but below the full-screen alert panel.
    private static let backdropLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    /// Covers the main screen with an opaque, click-through, neutral dark window. Baplet's
    /// frosted windows and the semi-transparent full-screen alerts show whatever lies behind
    /// them, so without this, screenshots could reveal the owner's apps, Dock, menu bar or
    /// wallpaper. Nothing but this backdrop is ever behind a captured scene.
    private static func showBackdrop() {
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        window.isOpaque = true
        window.ignoresMouseEvents = true
        window.level = backdropLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        backdrop = window
    }

    /// Lifts the scene's windows (which SwiftUI may open a moment later) above the backdrop,
    /// leaving windows that already sit higher, like the full-screen alert, where they are.
    private static func raiseSceneAboveBackdrop() {
        let sceneLevel = NSWindow.Level(rawValue: backdropLevel.rawValue + 1)
        for delay in [0.1, 0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows where window !== backdrop && window.isVisible
                    && window.level.rawValue < sceneLevel.rawValue
                    && !String(describing: type(of: window)).contains("StatusBar") {
                    window.level = sceneLevel
                    window.orderFrontRegardless()
                }
            }
        }
    }

    /// Hosts the menu bar window's content in an ordinary window, since a `MenuBarExtra`
    /// can't be opened programmatically.
    @MainActor
    private static func showMenuWindow(calendarService: CalendarService, settingsStore: SettingsStore) {
        let content = MenuBarContentView()
            .environment(calendarService)
            .environment(settingsStore)
            .environment(AlarmManager())
            .ignoresSafeArea()
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows the sample stand-up as an alert in the given style.
    @MainActor
    private static func showAlert(style: AlertStyle) {
        let start = DemoData.standUpStart
        AlertService.show(
            style: style,
            props: AlertProps(
                title: DemoData.standUpTitle,
                time: EventTimeFormat.alertLine(now: AppClock.now(), start: start, end: start.addingTimeInterval(15 * 60)),
                location: "Meeting room 2",
                calendarName: "Work",
                meetingLink: .sample,
                onDismiss: {},
                onSnooze: { _ in },
                onOpenMeeting: {},
                onOpenInCalendar: {}
            )
        )
    }
}
