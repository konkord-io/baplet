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
enum TodayPanel {
    /// The panel while it is on screen.
    private static var panel: TodayPanelWindow?

    /// Key-down monitor for the panel's keys; stopped when the panel closes.
    private static let keyMonitor = PanelKeyMonitor()

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
        installKeyHandling(for: panel, model: model, settingsStore: settingsStore)
    }

    /// Closes the panel if it is showing and stops listening for its keys.
    static func close() {
        keyMonitor.stop()
        guard let panel else { return }
        self.panel = nil
        panel.onDismiss = nil
        panel.close()
    }

    /// Handles the panel's keys before the list sees them (so arrows never just scroll):
    /// ↑/↓ select, Return / ⌘Return open, D toggles the alarm. Other keys pass through, and
    /// Escape reaches the panel's `cancelOperation`.
    private static func installKeyHandling(for panel: TodayPanelWindow, model: TodayListModel, settingsStore: SettingsStore) {
        keyMonitor.start(for: panel) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

            switch event.keyCode {
            case KeyCode.downArrow:
                model.move(by: 1)
                return nil
            case KeyCode.upArrow:
                model.move(by: -1)
                return nil
            case KeyCode.returnKey, KeyCode.keypadEnter:
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
                if let selected = model.selectedEvent, !selected.isAllDay, let key = selected.alarmKey {
                    settingsStore.toggleEventAlarm(key: key)
                }
                return nil
            }
            return event
        }
    }

    /// Performs the Return action on the event, then closes the panel.
    private static func perform(_ action: TodayReturnAction, on event: EKEvent, settingsStore: SettingsStore) {
        action.perform(on: event, settingsStore: settingsStore)
        close()
    }
}

/// The Today list's events and which one is selected. Shared by the view (highlight, scroll)
/// and the panel's key handling (arrows, Return, D).
@Observable
final class TodayListModel {
    /// Today's events that haven't ended, in display order, captured when the panel opened.
    let events: [EKEvent]

    /// Index into `events` of the highlighted row, or nil when the list is empty.
    var selectedIndex: Int?

    /// Where the mouse pointer was when the selection last followed it. Rows only take the
    /// selection on hover once the pointer has really moved, so arrow-key scrolling under a
    /// resting pointer (or opening the panel under it) doesn't steal the selection.
    private var lastPointerLocation = NSEvent.mouseLocation

    /// Drops events that have already ended, so the panel lists the same meetings as the menu,
    /// and starts with the first timed event (the one happening now, or the next); all-day
    /// events are only selected when nothing else is left. `now` defaults to the current time;
    /// tests pass a fixed one.
    init(events: [EKEvent], now: Date = AppClock.now()) {
        let remaining = events.filter { $0.endDate > now }
        self.events = remaining
        self.selectedIndex = remaining.indices.first { !remaining[$0].isAllDay } ?? remaining.indices.first
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
    /// Called when the panel should close (Escape or lost focus); cleared before Baplet
    /// closes the panel itself so it doesn't fire twice.
    var onDismiss: (() -> Void)?

    /// Lets the non-activating panel take key focus so it receives the list's keys.
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
                Text(AppClock.now().formatted(.dateTime.weekday(.wide).day().month(.wide)))
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
                VStack(spacing: 8) {
                    Image("fish_muscles")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 140)
                        .accessibilityHidden(true)
                    Text("No more meetings today")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                eventList
                if hasQuietMeetings {
                    quietMeetingsNote
                }
                Divider()
                keyHints
            }
        }
        .frame(width: 420)
    }

    /// True when working hours are on and some listed meeting starts outside them with its
    /// alarm still off, so it won't alert unless the user switches it on.
    private var hasQuietMeetings: Bool {
        guard settingsStore.workingHours.isEnabled else { return false }
        return model.events.contains { event in
            guard !event.isAllDay, let key = event.alarmKey else { return false }
            return settingsStore.isOutsideWorkingHours(key: key) && !settingsStore.isAlarmEnabled(key: key)
        }
    }

    /// Small note under the list explaining why some meetings are unchecked.
    private var quietMeetingsNote: some View {
        Label {
            Text("Meetings outside your working hours (\(settingsStore.workingHours.timeRangeText())) won't alert. Press D or tick the box to alert anyway.")
        } icon: {
            Image(systemName: "moon.zzz")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

extension TodayReturnAction {
    /// Joins the event's meeting (falling back to Calendar when it has no link) or opens it in
    /// Calendar. Shared by the Today panel and the menu's keyboard handling.
    func perform(on event: EKEvent, settingsStore: SettingsStore) {
        if self == .joinMeeting, let link = AlertService.extractMeetingLink(from: event) {
            BrowserService.openMeeting(link.url, settings: settingsStore)
        } else {
            AlertService.openEventInCalendar(event)
        }
    }
}
