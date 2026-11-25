//
//  AlertService.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import EventKit
import os
import SwiftUI

/// Namespace providing static methods for presenting alarm alerts.
/// Uses NSPanel for programmatic window control that SwiftUI scenes can't provide.
/// Only one alert is on screen at a time; an alert that goes away without the user choosing
/// an action (closed with its close button, or replaced by another alert) counts as snoozed,
/// so an alarm is never silently lost.
enum AlertService {
    /// The currently displayed alert panel, if any.
    private static var activePanel: AlertPanel?

    /// Key-down monitor for the active alert's shortcuts; stopped when the panel closes.
    private static let keyMonitor = PanelKeyMonitor()

    /// Snoozes the alert on screen with the caller's own snooze action, without touching the
    /// panel. Run when the alert is replaced by another one; nil while no alert is showing.
    private static var snoozeActiveAlert: (() -> Void)?

    /// Notice-level log of alert windows shown, actions taken and windows closed. macOS keeps
    /// these on disk for days, so a stuck alert can be traced afterwards. Meeting titles are
    /// never logged.
    static let log = Logger(subsystem: "io.konkord.baplet", category: "alert")

    /// How long after an alert appears before its single-letter shortcuts respond, so keys
    /// already being typed into another app don't trigger an action by accident.
    private static let shortcutArmDelay: TimeInterval = 1.0

    /// A detected meeting link with its service name and URL.
    struct MeetingLink {
        let serviceName: String
        let url: URL

        /// SF Symbol shown for the link; every supported service uses the video camera.
        var icon: String { "video" }

        /// A Google Meet link used by the test alert and the welcome guide's style previews.
        static let sample = MeetingLink(
            serviceName: "Google Meet",
            url: URL(string: "https://meet.google.com/abc-defg-hij")!
        )
    }

    /// Supported conferencing platforms with their URL patterns and display names.
    private static let meetingPatterns: [(pattern: NSRegularExpression, name: String)] = [
        (try! NSRegularExpression(pattern: #"https://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+[^\s<\"]*"#), "Google Meet"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9.-]*zoom\.us/j/\d+[^\s<\"]*"#), "Zoom"),
        (try! NSRegularExpression(pattern: #"https://teams\.microsoft\.com/l/meetup-join/[^\s<\"]+"#), "Teams"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9]+\.webex\.com/[^\s<\"]+"#), "Webex"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9.-]*goto(meeting|webinar)\.com/join/\d+"#), "GoTo Meeting"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9]+\.slack\.com/[^\s<\"]*huddle[^\s<\"]*"#), "Slack Huddle"),
    ]

    /// Extracts a meeting URL from an EKEvent by searching its URL, location, and notes fields
    /// against all supported conferencing platforms. Returns the first match found.
    static func extractMeetingLink(from event: EKEvent) -> MeetingLink? {
        let fields: [String?] = [
            event.url?.absoluteString,
            event.location,
            event.notes,
        ]
        for field in fields {
            guard let text = field else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for entry in meetingPatterns {
                if let match = entry.pattern.firstMatch(in: text, range: range),
                   let matchRange = Range(match.range, in: text),
                   let url = URL(string: String(text[matchRange])) {
                    return MeetingLink(serviceName: entry.name, url: url)
                }
            }
        }
        return nil
    }

    /// Plays the alert sound and volume chosen in Settings (Ping at full volume by default).
    static func playAlarmSound(settings: SettingsStore) {
        AlertSoundPlayer.play(settings: settings)
    }

    /// Opens a calendar event in Apple Calendar by creating a temporary .ics file with the event's UID.
    /// Calendar.app recognizes the existing event and shows its detail/info view. When the event
    /// has no external UID yet or the file can't be written, Calendar is simply opened.
    static func openEventInCalendar(_ event: EKEvent) {
        guard let uid = event.calendarItemExternalIdentifier,
              let startDate = event.startDate,
              let endDate = event.endDate else {
            openCalendarApp()
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        formatter.timeZone = TimeZone(identifier: "UTC")

        let dtStart = formatter.string(from: startDate)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        let dtEnd = formatter.string(from: endDate)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")

        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:\(icsEscaped(uid))
        DTSTART:\(dtStart)
        DTEND:\(dtEnd)
        SUMMARY:\(icsEscaped(event.displayTitle))
        END:VEVENT
        END:VCALENDAR
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("baplet-event.ics")
        do {
            try ics.write(to: tempURL, atomically: true, encoding: .utf8)
            FocusHandoff.prepare(forAppOpening: tempURL)
            NSWorkspace.shared.open(tempURL)
        } catch {
            openCalendarApp()
        }
    }

    /// Opens Apple Calendar without a specific event; the fallback when an event can't be
    /// handed over as an .ics file.
    private static func openCalendarApp() {
        guard let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        FocusHandoff.prepare(forBundleID: "com.apple.iCal")
        NSWorkspace.shared.open(calendarURL)
    }

    /// Escapes a value for an iCalendar text field (RFC 5545 §3.3.11), so titles containing
    /// backslashes, commas, semicolons or line breaks still produce a valid file.
    private static func icsEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    /// Shows an alert in the given style: a floating popup dialog, or a full-screen overlay.
    /// An alert already on screen is closed and snoozed first, so it comes back later instead
    /// of being lost. The panel's actions close the panel before running the caller's own
    /// action, and opening the meeting or the event also dismisses the alarm. Closing the
    /// popup with its close button snoozes it.
    static func show(style: AlertStyle, props: AlertProps) {
        let replacedAlertSnooze = snoozeActiveAlert
        closeActivePanel()
        replacedAlertSnooze?()
        closeStrayPanels()

        let owner = PanelOwner()
        let panelProps = closingPanelFirst(props, owner: owner)
        let panel = style.isFullScreen
            ? makeFullScreenPanel(style: style, props: panelProps)
            : makePopupPanel(props: panelProps)
        owner.panel = panel

        panel.onUserClose = { panelProps.onSnooze(AlertProps.defaultSnoozeMinutes) }
        panel.makeKeyAndOrderFront(nil)
        log.notice("Alert shown: style=\(style.rawValue, privacy: .public) key=\(panel.isKeyWindow, privacy: .public) screen=\(panel.screen?.localizedName ?? "none", privacy: .public)")
        activePanel = panel
        snoozeActiveAlert = { props.onSnooze(AlertProps.defaultSnoozeMinutes) }
        installKeyShortcuts(for: panel, props: panelProps)
    }

    /// Builds the popup dialog: a titled, closable floating panel sized to its content and
    /// centred on screen.
    private static func makePopupPanel(props: AlertProps) -> AlertPanel {
        let panel = AlertPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Baplet"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: AlertPopupView(props: props))
        hostingView.sizingOptions = []
        panel.setContentSize(hostingView.fittingSize)
        panel.contentView = hostingView
        panel.center()
        return panel
    }

    /// Builds a borderless panel covering the main screen that hosts a FullScreenAlertRouter
    /// for the chosen style. The panel sits one level below pop-up menus: high enough to cover
    /// the Dock, menu bar and other windows, yet low enough that the Snooze and Open dropdown
    /// menus appear on top of it.
    private static func makeFullScreenPanel(style: AlertStyle, props: AlertProps) -> AlertPanel {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let panel = AlertPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)

        let hostingView = NSHostingView(rootView: FullScreenAlertRouter(style: style, props: props))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        return panel
    }

    /// Returns a copy of `props` whose actions first close the alert's own panel (held by
    /// `owner`), so its buttons always close the window they are in, even if Baplet has lost
    /// track of it. Opening the meeting or the event also dismisses, so the alarm stops once
    /// the user has gone there.
    private static func closingPanelFirst(_ props: AlertProps, owner: PanelOwner) -> AlertProps {
        AlertProps(
            title: props.title,
            time: props.time,
            location: props.location,
            calendarName: props.calendarName,
            meetingLink: props.meetingLink,
            onDismiss: {
                log.notice("Alert action: dismiss")
                close(owner.panel)
                props.onDismiss()
            },
            onSnooze: { minutes in
                log.notice("Alert action: snooze \(minutes, privacy: .public) min")
                close(owner.panel)
                props.onSnooze(minutes)
            },
            onOpenMeeting: {
                log.notice("Alert action: open meeting")
                close(owner.panel)
                props.onDismiss()
                props.onOpenMeeting()
            },
            onOpenInCalendar: {
                log.notice("Alert action: open in Calendar")
                close(owner.panel)
                props.onDismiss()
                props.onOpenInCalendar()
            }
        )
    }

    /// Closes the given alert panel: through `closeActivePanel` when it is the active one,
    /// otherwise directly, so a panel Baplet no longer tracks still goes away. Runs none of
    /// the alert's actions.
    private static func close(_ panel: AlertPanel?) {
        guard let panel, panel !== activePanel else {
            closeActivePanel()
            return
        }
        log.notice("Closing untracked alert panel")
        panel.onUserClose = nil
        panel.close()
    }

    /// Closes the alert on screen without running any of its actions. Used when its meeting
    /// has ended, so a forgotten full-screen alert can't stay up indefinitely.
    static func closeActiveAlert(reason: String) {
        guard activePanel != nil else { return }
        log.notice("Alert closed by Baplet: \(reason, privacy: .public)")
        closeActivePanel()
    }

    /// Closes every visible alert panel other than the active one. There should never be
    /// any; this is a safety net run before each new alert and on every alarm check, so a
    /// leftover full-screen panel can't block the screen.
    static func closeStrayPanels() {
        for case let panel as AlertPanel in NSApp.windows where panel !== activePanel && panel.isVisible {
            log.error("Closing stray alert panel")
            panel.onUserClose = nil
            panel.close()
        }
    }

    /// Closes and releases the currently active alert panel, if one exists, and stops its
    /// keyboard shortcuts. Runs none of the alert's actions.
    private static func closeActivePanel() {
        keyMonitor.stop()
        snoozeActiveAlert = nil
        guard let panel = activePanel else { return }
        activePanel = nil
        panel.onUserClose = nil
        if panel.isVisible {
            panel.close()
        }
        log.notice("Alert closed")
    }

    /// Listens for the alert's keyboard shortcuts while its panel is key:
    /// O or Return opens (meeting if there is a link, otherwise Calendar), D dismisses, and
    /// S or Escape snoozes for the default time; Escape is the way out when clicks don't land. Keys pressed within `shortcutArmDelay` of the alert
    /// appearing are swallowed and ignored; any other key passes through untouched.
    private static func installKeyShortcuts(for panel: AlertPanel, props: AlertProps) {
        let armedAt = Date().addingTimeInterval(shortcutArmDelay)
        keyMonitor.start(for: panel) { event in
            guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
                return event
            }
            let isReturn = event.isReturnKey
            let isEscape = event.keyCode == KeyCode.escape
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard isReturn || isEscape || ["o", "d", "s"].contains(key) else { return event }
            guard Date() >= armedAt else { return nil }
            log.notice("Alert key: \(isEscape ? "escape" : isReturn ? "return" : key, privacy: .public)")

            if isReturn || key == "o" {
                props.openDefault()
            } else if key == "d" {
                props.onDismiss()
            } else {
                props.onSnooze(AlertProps.defaultSnoozeMinutes)
            }
            return nil
        }
    }
}

/// Weak reference from an alert's actions to the panel they belong to, filled in once the
/// panel exists (its view needs the actions first).
private final class PanelOwner {
    weak var panel: AlertPanel?
}

/// Alert panel that can become the key window even when borderless, so the full-screen
/// styles receive keyboard shortcuts. As a non-activating panel it takes key focus without
/// activating Baplet or pulling the user out of their current app.
private final class AlertPanel: NSPanel {
    /// Runs after the user closes the panel themselves (the popup's close button), so the
    /// alert can be snoozed instead of vanishing with its alarm still active. Cleared before
    /// Baplet closes the panel itself.
    var onUserClose: (() -> Void)?

    /// Lets the borderless full-screen panel take key focus for the keyboard shortcuts.
    override var canBecomeKey: Bool { true }

    /// Closes the panel, then runs `onUserClose` once if it is still set.
    override func close() {
        let handler = onUserClose
        onUserClose = nil
        super.close()
        handler?()
    }
}

extension AlertService {
    /// Fires a sample alert in the currently selected style, with a mock event and Google Meet
    /// link, so the user can preview it from Settings or the welcome guide. Its own actions
    /// do nothing except joining the sample meeting; a real alert it replaces is snoozed.
    static func showTestAlert(settings settingsStore: SettingsStore) {
        let now = AppClock.now()
        let mockEnd = now.addingTimeInterval(30 * 60)

        if settingsStore.soundEnabled {
            playAlarmSound(settings: settingsStore)
        }

        show(
            style: settingsStore.alertStyle,
            props: AlertProps(
                title: "Test Event",
                time: EventTimeFormat.alertLine(now: now, start: now, end: mockEnd),
                location: "Conference Room A",
                calendarName: "Work",
                meetingLink: .sample,
                onDismiss: {},
                onSnooze: { _ in },
                onOpenMeeting: { BrowserService.openMeeting(MeetingLink.sample.url, settings: settingsStore) },
                onOpenInCalendar: {}
            )
        )
    }
}
