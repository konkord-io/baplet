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
///
/// Keyboard: ↑/↓ move the selection (starting on the current or next meeting), Return runs the
/// action chosen in Settings → Shortcuts, ⌘Return the other one, D toggles the alarm.
@MainActor
enum TodayPanel {
    /// The panel while it is on screen.
    private static var panel: TodayPanelWindow?

    /// Local key-down monitor for the panel's keys; removed when the panel closes.
    private static var keyMonitor: Any?

    /// Shows the panel, or closes it if it is already showing (so one shortcut does both).
    static func toggle(calendarService: CalendarService, settingsStore: SettingsStore) {
        if panel != nil {
            close()
        } else {
            show(calendarService: calendarService, settingsStore: settingsStore)
        }
    }

    /// Builds the panel around `TodayView`, sizes it to its content, centres it, gives it
    /// keyboard focus and starts listening for its keys. The panel keeps a (hidden) title bar
    /// for its rounded corners and shadow, so the hosting view ignores the safe area that bar
    /// would otherwise reserve at the top.
    static func show(calendarService: CalendarService, settingsStore: SettingsStore) {
        close()

        let model = TodayListModel(
            events: calendarService.todaysEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs)
        )

        let panel = TodayPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
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

        let rootView = TodayView(model: model, onEventOpened: { close() })
            .environment(calendarService)
            .environment(settingsStore)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        installKeyHandling(model: model, settingsStore: settingsStore)
    }

    /// Closes the panel if it is showing and stops listening for its keys.
    static func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        guard let panel else { return }
        self.panel = nil
        panel.onDismiss = nil
        panel.close()
    }

    /// Handles the panel's keys before the list sees them (so arrows never just scroll):
    /// ↑/↓ select, Return / ⌘Return open, D toggles the alarm. Other keys pass through, and
    /// Escape reaches the panel's `cancelOperation`.
    private static func installKeyHandling(model: TodayListModel, settingsStore: SettingsStore) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === panel else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

            switch event.keyCode {
            case 125:
                model.move(by: 1)
                return nil
            case 126:
                model.move(by: -1)
                return nil
            case 36, 76:
                guard let selected = model.selectedEvent else { return nil }
                let action = modifiers == .command
                    ? settingsStore.todayReturnAction.alternate
                    : settingsStore.todayReturnAction
                perform(action, on: selected, settingsStore: settingsStore)
                return nil
            default:
                break
            }

            if modifiers.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "d" {
                if let selected = model.selectedEvent, !selected.isAllDay {
                    settingsStore.toggleEventAlarm(eventID: selected.eventIdentifier)
                }
                return nil
            }
            return event
        }
    }

    /// Joins the event's meeting (falling back to Calendar when it has no link) or opens it in
    /// Calendar, then closes the panel.
    private static func perform(_ action: TodayReturnAction, on event: EKEvent, settingsStore: SettingsStore) {
        if action == .joinMeeting, let link = AlertService.extractMeetingLink(from: event) {
            BrowserService.openMeeting(link.url, settings: settingsStore)
        } else {
            AlertService.openEventInCalendar(
                title: event.title ?? "No Title",
                startDate: event.startDate,
                endDate: event.endDate,
                uid: event.calendarItemExternalIdentifier
            )
        }
        close()
    }
}

/// The Today list's events and which one is selected. Shared by the view (highlight, scroll)
/// and the panel's key handling (arrows, Return, D).
@MainActor
@Observable
final class TodayListModel {
    let events: [EKEvent]
    var selectedIndex: Int?

    /// Where the mouse pointer was when the selection last followed it. Rows only take the
    /// selection on hover once the pointer has really moved, so arrow-key scrolling under a
    /// resting pointer (or opening the panel under it) doesn't steal the selection.
    private var lastPointerLocation = NSEvent.mouseLocation

    /// Starts with the meeting happening now, or the next one; all-day events are skipped.
    /// When every meeting has ended, the last one is selected.
    init(events: [EKEvent]) {
        self.events = events
        let now = Date()
        let timed = events.indices.filter { !events[$0].isAllDay }
        self.selectedIndex = timed.first { events[$0].endDate > now } ?? timed.last ?? events.indices.first
    }

    /// The selected event, if any.
    var selectedEvent: EKEvent? {
        selectedIndex.map { events[$0] }
    }

    /// Selects the row under the pointer, but only if the pointer has moved since last time.
    func pointerEntered(row index: Int) {
        let location = NSEvent.mouseLocation
        guard location != lastPointerLocation else { return }
        lastPointerLocation = location
        selectedIndex = index
    }

    /// Moves the selection up or down, stopping at the first and last event.
    func move(by offset: Int) {
        guard !events.isEmpty else { return }
        let current = selectedIndex ?? (offset > 0 ? -1 : events.count)
        selectedIndex = min(max(current + offset, 0), events.count - 1)
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

/// The Today panel's content: a header with the date and the Baplet logo, today's events from the selected
/// calendars (ended ones faded, the selected one highlighted and kept in view), and a strip
/// of key hints. An empty day says so.
private struct TodayView: View {
    @Environment(SettingsStore.self) private var settingsStore

    let model: TodayListModel

    /// Called after the user joins a meeting or opens an event in Calendar by mouse.
    let onEventOpened: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(.secondary)
                Spacer()
                Image("baplet")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            if model.events.isEmpty {
                Text("Nothing on your calendar today.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                eventList
                Divider()
                keyHints
            }
        }
        .frame(width: 420)
    }

    /// The scrollable rows; the selection scrolls into view whenever it changes.
    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.events.enumerated()), id: \.offset) { index, event in
                        CalendarEventRow(
                            event: event,
                            onOpened: onEventOpened,
                            isSelected: model.selectedIndex == index,
                            onHoverChange: { hovering in
                                if hovering { model.pointerEntered(row: index) }
                            }
                        )
                        .opacity(event.endDate < .now ? 0.45 : 1)
                        .id(index)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 440)
            .onAppear {
                if let index = model.selectedIndex { proxy.scrollTo(index, anchor: .center) }
            }
            .onChange(of: model.selectedIndex) { _, index in
                if let index {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index) }
                }
            }
        }
    }

    /// One line of keyboard hints; the Return labels follow the Settings choice.
    private var keyHints: some View {
        HStack(spacing: 12) {
            hint("↑↓", "select")
            hint("↩", settingsStore.todayReturnAction.hintLabel)
            hint("⌘↩", settingsStore.todayReturnAction.alternate.hintLabel)
            hint("D", "switch alarm")
            hint("esc", "close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// A key glyph in a small rounded box followed by what it does.
    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            Text(action)
        }
    }
}
