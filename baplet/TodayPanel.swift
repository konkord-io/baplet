//
//  TodayPanel.swift
//  baplet
//

import AppKit
import EventKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Global shortcut that toggles the Today panel. Unset until the user records one in
    /// Settings → Shortcuts or the welcome guide.
    static let showToday = Self("showToday")
}

/// Explanation of the Today shortcut, shared by Settings → Shortcuts and the welcome guide.
enum TodayShortcutHelp {
    static let text: LocalizedStringKey = "Pick a key combination that shows today's events from any app. Press it again, or Escape, to close the list. If macOS already uses the combination, Baplet warns you before saving it. Clashes with other apps' shortcuts can't be detected, so choose something unusual, such as ⌃⌥⌘T."
}

/// A Spotlight-like floating panel listing all of today's events, with the same rows as the
/// menu (join meeting, alarm checkbox, click to open in Calendar). It opens centred without
/// switching apps, and closes on Escape, on clicking elsewhere, when an event or meeting is
/// opened, or when its shortcut is pressed again.
@MainActor
enum TodayPanel {
    /// The panel while it is on screen.
    private static var panel: TodayPanelWindow?

    /// Shows the panel, or closes it if it is already showing (so one shortcut does both).
    static func toggle(calendarService: CalendarService, settingsStore: SettingsStore) {
        if panel != nil {
            close()
        } else {
            show(calendarService: calendarService, settingsStore: settingsStore)
        }
    }

    /// Builds the panel around `TodayView`, sizes it to its content, centres it and gives it
    /// keyboard focus. The panel keeps a (hidden) title bar for its rounded corners and shadow,
    /// so the hosting view ignores the safe area that bar would otherwise reserve at the top.
    static func show(calendarService: CalendarService, settingsStore: SettingsStore) {
        close()

        let panel = TodayPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.onDismiss = { close() }

        let rootView = TodayView(onEventOpened: { close() })
            .environment(calendarService)
            .environment(settingsStore)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
    }

    /// Closes the panel if it is showing.
    static func close() {
        guard let panel else { return }
        self.panel = nil
        panel.onDismiss = nil
        panel.close()
    }
}

/// Panel that can take keyboard focus without activating Baplet, and reports when it should
/// go away: Escape pressed, or focus moved to another window or app.
private final class TodayPanelWindow: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }

    /// Escape closes the panel.
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// Clicking anywhere outside the panel closes it.
    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}

/// The Today panel's content: a header with the date, then today's events from the selected
/// calendars. Events that have ended are faded; an empty day says so.
private struct TodayView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore

    /// Called after the user joins a meeting or opens an event in Calendar.
    let onEventOpened: () -> Void

    var body: some View {
        let events = calendarService.todaysEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs)

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            if events.isEmpty {
                Text("Nothing on your calendar today.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events, id: \.calendarItemIdentifier) { event in
                            CalendarEventRow(event: event, onOpened: onEventOpened)
                                .opacity(event.endDate < .now ? 0.45 : 1)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 440)
            }
        }
        .frame(width: 400)
    }
}
