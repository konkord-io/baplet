//
//  AlertService.swift
//  calkitty
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
            .appendingPathComponent("calkitty-event.ics")
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

    /// Shows a floating popup dialog panel with event details and dismiss/snooze actions.
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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "CalKitty"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()

        let rootView = AlertPopupView(
            title: title,
            time: time,
            location: location,
            calendarName: calendarName,
            meetingLink: meetingLink,
            onDismiss: {
                closeActivePanel()
                onDismiss()
            },
            onSnooze: { minutes in
                closeActivePanel()
                onSnooze(minutes)
            },
            onOpenInCalendar: {
                closeActivePanel()
                onDismiss()
                onOpenInCalendar()
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        let size = hostingView.fittingSize
        panel.setContentSize(size)
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
    }

    /// Shows a full-screen overlay panel styled according to the given AlertStyle.
    /// Creates a borderless NSPanel at screenSaver level covering the entire screen
    /// and hosts a FullScreenAlertRouter that picks the correct visual style.
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

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)

        let props = FullScreenAlertProps(
            title: title,
            time: time,
            location: location,
            calendarName: calendarName,
            meetingLink: meetingLink,
            onDismiss: {
                closeActivePanel()
                onDismiss()
            },
            onSnooze: { minutes in
                closeActivePanel()
                onSnooze(minutes)
            },
            onOpenInCalendar: {
                closeActivePanel()
                onDismiss()
                onOpenInCalendar()
            }
        )

        let hostingView = NSHostingView(rootView: FullScreenAlertRouter(
            style: style,
            props: props
        ))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.makeKeyAndOrderFront(nil)

        activePanel = panel
    }

    /// Closes and releases the currently active alert panel, if one exists.
    static func closeActivePanel() {
        activePanel?.close()
        activePanel = nil
    }
}
