//
//  AlertService.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import EventKit
import SwiftUI

/// Namespace providing static methods for presenting alarm alerts.
/// Uses NSPanel for programmatic window control that SwiftUI scenes can't provide.
enum AlertService {
    /// Strong reference to the currently displayed alert panel, if any.
    private static var activePanel: NSPanel?

    /// Local key-down monitor for the active alert's shortcuts; removed when the panel closes.
    private static var keyMonitor: Any?

    /// How long after an alert appears before its single-letter shortcuts respond, so keys
    /// already being typed into another app don't trigger an action by accident.
    private static let shortcutArmDelay: TimeInterval = 1.0

    /// A detected meeting link with its service name, icon, and URL.
    struct MeetingLink {
        let serviceName: String
        let icon: String
        let url: URL
    }

    /// Supported conferencing platforms with their URL patterns, display names, and SF Symbols.
    private static let meetingPatterns: [(pattern: NSRegularExpression, name: String, icon: String)] = [
        (try! NSRegularExpression(pattern: #"https://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+[^\s<\"]*"#), "Google Meet", "video"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9.-]*zoom\.us/j/\d+[^\s<\"]*"#), "Zoom", "video"),
        (try! NSRegularExpression(pattern: #"https://teams\.microsoft\.com/l/meetup-join/[^\s<\"]+"#), "Teams", "video"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9]+\.webex\.com/[^\s<\"]+"#), "Webex", "video"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9.-]*goto(meeting|webinar)\.com/join/\d+"#), "GoTo Meeting", "video"),
        (try! NSRegularExpression(pattern: #"https://[a-z0-9]+\.slack\.com/[^\s<\"]*huddle[^\s<\"]*"#), "Slack Huddle", "video"),
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
                    return MeetingLink(serviceName: entry.name, icon: entry.icon, url: url)
                }
            }
        }
        return nil
    }

    /// Plays the system "Ping" sound as the alarm notification audio.
    static func playAlarmSound() {
        NSSound(named: "Ping")?.play()
    }

    /// Opens a calendar event in Apple Calendar by creating a temporary .ics file with the event's UID.
    /// Calendar.app recognizes the existing event and shows its detail/info view.
    static func openEventInCalendar(
        title: String,
        startDate: Date,
        endDate: Date,
        uid: String
    ) {
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
        UID:\(uid)
        DTSTART:\(dtStart)
        DTEND:\(dtEnd)
        SUMMARY:\(title)
        END:VEVENT
        END:VCALENDAR
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("baplet-event.ics")
        do {
            try ics.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)
        } catch {
            // Fall back to just opening Calendar.app
            if let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.open(calendarURL)
            }
        }
    }

    /// Shows a floating popup dialog panel with event details and snooze/dismiss/open actions.
    /// Creates an NSPanel with .titled and .closable style, floating above other windows.
    static func showPopupAlert(
        title: String,
        time: String,
        location: String?,
        calendarName: String,
        meetingLink: MeetingLink? = nil,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping (Int) -> Void,
        onOpenInCalendar: @escaping () -> Void
    ) {
        closeActivePanel()

        let panel = AlertPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Baplet"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()

        let actions = PanelActions(
            meetingLink: meetingLink,
            onDismiss: onDismiss,
            onSnooze: onSnooze,
            onOpenInCalendar: onOpenInCalendar
        )
        let rootView = AlertPopupView(
            title: title,
            time: time,
            location: location,
            calendarName: calendarName,
            meetingLink: meetingLink,
            onDismiss: actions.dismiss,
            onSnooze: actions.snooze,
            onOpenMeeting: actions.openMeeting,
            onOpenInCalendar: actions.openInCalendar
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        let size = hostingView.fittingSize
        panel.setContentSize(size)
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
        installKeyShortcuts(actions)
    }

    /// Shows a full-screen overlay panel styled according to the given AlertStyle.
    /// Creates a borderless NSPanel covering the entire screen and hosts a
    /// FullScreenAlertRouter that picks the correct visual style. The panel sits one level
    /// below pop-up menus: high enough to cover the Dock, menu bar and other windows, yet low
    /// enough that the Snooze and Open dropdown menus appear on top of it.
    static func showFullScreenAlert(
        style: AlertStyle,
        title: String,
        time: String,
        location: String?,
        calendarName: String,
        meetingLink: MeetingLink? = nil,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping (Int) -> Void,
        onOpenInCalendar: @escaping () -> Void
    ) {
        closeActivePanel()

        guard let screen = NSScreen.main else { return }

        let panel = AlertPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)

        let actions = PanelActions(
            meetingLink: meetingLink,
            onDismiss: onDismiss,
            onSnooze: onSnooze,
            onOpenInCalendar: onOpenInCalendar
        )
        let props = FullScreenAlertProps(
            title: title,
            time: time,
            location: location,
            calendarName: calendarName,
            meetingLink: meetingLink,
            onDismiss: actions.dismiss,
            onSnooze: actions.snooze,
            onOpenMeeting: actions.openMeeting,
            onOpenInCalendar: actions.openInCalendar
        )

        let hostingView = NSHostingView(rootView: FullScreenAlertRouter(
            style: style,
            props: props
        ))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
        installKeyShortcuts(actions)
    }

    /// Closes and releases the currently active alert panel, if one exists,
    /// and removes its keyboard shortcut monitor.
    static func closeActivePanel() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        activePanel?.close()
        activePanel = nil
    }

    /// Listens for the alert's keyboard shortcuts while its panel is key:
    /// O or Return opens (meeting if there is a link, otherwise Calendar), D dismisses and
    /// S snoozes for 5 minutes. Keys pressed within `shortcutArmDelay` of the alert appearing
    /// are swallowed and ignored; any other key passes through untouched.
    private static func installKeyShortcuts(_ actions: PanelActions) {
        let armedAt = Date().addingTimeInterval(shortcutArmDelay)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === activePanel,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
                return event
            }
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard isReturn || ["o", "d", "s"].contains(key) else { return event }
            guard Date() >= armedAt else { return nil }

            if isReturn || key == "o" {
                actions.openDefault()
            } else if key == "d" {
                actions.dismiss()
            } else {
                actions.snooze(5)
            }
            return nil
        }
    }

    /// The four alert actions, each wrapped to close the panel first. Opening in any way
    /// also dismisses, so the alarm stops once the user has gone to the meeting or event.
    private struct PanelActions {
        let dismiss: () -> Void
        let snooze: (Int) -> Void
        let openMeeting: () -> Void
        let openInCalendar: () -> Void
        let openDefault: () -> Void

        /// Builds the wrapped actions from the caller's dismiss/snooze/Calendar callbacks
        /// and the event's meeting link, if any.
        init(
            meetingLink: MeetingLink?,
            onDismiss: @escaping () -> Void,
            onSnooze: @escaping (Int) -> Void,
            onOpenInCalendar: @escaping () -> Void
        ) {
            let openMeeting = {
                closeActivePanel()
                onDismiss()
                if let meetingLink {
                    NSWorkspace.shared.open(meetingLink.url)
                }
            }
            let openInCalendar = {
                closeActivePanel()
                onDismiss()
                onOpenInCalendar()
            }
            self.dismiss = {
                closeActivePanel()
                onDismiss()
            }
            self.snooze = { minutes in
                closeActivePanel()
                onSnooze(minutes)
            }
            self.openMeeting = openMeeting
            self.openInCalendar = openInCalendar
            self.openDefault = meetingLink != nil ? openMeeting : openInCalendar
        }
    }
}

/// Alert panel that can become the key window even when borderless, so the full-screen
/// styles receive keyboard shortcuts. As a non-activating panel it takes key focus without
/// activating Baplet or pulling the user out of their current app.
private final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
