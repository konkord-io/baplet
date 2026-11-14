//
//  AlarmManager.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import EventKit
import Foundation

/// Represents the current state of the menu bar icon.
enum MenuBarStatus {
    case idle
    case upcoming(minutesLeft: Int)
    case active
    case paused

    /// Whether the menu bar icon is drawn faded; true only while alarms are paused.
    var isDimmed: Bool {
        if case .paused = self { return true }
        return false
    }

    /// Optional text label shown next to the icon, or nil for icon-only.
    var label: String? {
        switch self {
        case .idle, .paused: nil
        case .upcoming(let minutes): "\(minutes)m"
        case .active: "NOW"
        }
    }
}

/// Observable alarm manager that checks events on a 30-second interval
/// and triggers the appropriate alert when an event is approaching.
/// Alarm state is kept per event occurrence (`EKEvent.alarmKey`). Only one alert is shown at
/// a time: other due events wait, and the next one appears as soon as the current alert is
/// dismissed, snoozed or opened.
@Observable
final class AlarmManager {
    /// Current status for the menu bar icon, updated on every timer tick.
    var menuBarStatus: MenuBarStatus = .idle

    /// Alarm key of the event whose alert is on screen; its sound is replayed every tick while
    /// the alert stays open, and no other alert is shown meanwhile.
    private var activeAlarmKey: String?

    /// Alarm keys mapped to the time when their snooze expires.
    private var snoozedAlarms: [String: Date] = [:]

    /// The repeating timer that drives alarm checks.
    private var timer: Timer?

    /// Reference to the calendar service for accessing events.
    private weak var calendarService: CalendarService?

    /// Reference to the settings store for alarm configuration.
    private weak var settingsStore: SettingsStore?

    /// Seconds between alarm checks; also the interval at which an open alert's sound repeats.
    private static let checkInterval: TimeInterval = 30

    /// Starts the alarm check timer on the main run loop.
    /// Should be called once during app startup after calendar data is loaded.
    func start(calendarService: CalendarService, settingsStore: SettingsStore) {
        self.calendarService = calendarService
        self.settingsStore = settingsStore

        checkAlarms(replaySound: false)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkAlarms(replaySound: true)
        }
    }

    /// Forces an immediate alarm check cycle, updating the menu bar icon right away.
    func recheckNow() {
        checkAlarms(replaySound: false)
    }

    /// Re-fetches events, forgets state of ended events, updates the menu bar icon and, unless
    /// alarms are paused, either replays the open alert's sound (when `replaySound`, i.e. on a
    /// timer tick) or shows the alert of the first due event when none is open.
    private func checkAlarms(replaySound: Bool) {
        guard let calendarService, let settingsStore else { return }

        calendarService.fetchEvents(for: settingsStore)
        let events = calendarService.events
        let now = Date()

        cleanupStaleEntries(events: events, now: now)
        settingsStore.pruneDisabledEventAlarms(keeping: Set(events.compactMap(\.alarmKey)), now: now)
        updateMenuBarStatus(events: events, now: now, settingsStore: settingsStore)

        guard !settingsStore.alarmsPaused else { return }

        if activeAlarmKey != nil {
            if replaySound, settingsStore.soundEnabled {
                AlertService.playAlarmSound()
            }
            return
        }

        if let next = events.first(where: { isDue($0, now: now, settingsStore: settingsStore) }) {
            fireAlarm(for: next, settingsStore: settingsStore)
        }
    }

    /// Whether the event's alarm should be on screen now: a timed event whose alarm is
    /// enabled and not snoozed, between its alarm time (start minus the lead time) and its end.
    private func isDue(_ event: EKEvent, now: Date, settingsStore: SettingsStore) -> Bool {
        guard !event.isAllDay,
              let key = event.alarmKey,
              settingsStore.isAlarmEnabled(key: key) else { return false }
        if let snoozeExpiry = snoozedAlarms[key], now < snoozeExpiry {
            return false
        }
        let alarmTime = event.startDate.addingTimeInterval(-Double(settingsStore.minutesBefore) * 60)
        return now >= alarmTime && now < event.endDate
    }

    /// Presents the configured alert style for the given event and marks it as the active alert.
    /// Sound is played only when `soundEnabled` is true.
    private func fireAlarm(for event: EKEvent, settingsStore: SettingsStore) {
        guard let key = event.alarmKey else { return }
        snoozedAlarms.removeValue(forKey: key)

        if settingsStore.soundEnabled {
            AlertService.playAlarmSound()
        }

        let meetingLink = AlertService.extractMeetingLink(from: event)
        AlertService.show(
            style: settingsStore.alertStyle,
            props: AlertProps(
                title: event.displayTitle,
                time: EventTimeFormat.alertLine(now: Date(), start: event.startDate, end: event.endDate),
                location: event.location,
                calendarName: event.calendar?.title ?? "",
                meetingLink: meetingLink,
                onDismiss: { [weak self] in self?.dismiss(key: key) },
                onSnooze: { [weak self] minutes in self?.snooze(key: key, minutes: minutes) },
                onOpenMeeting: {
                    if let meetingLink {
                        BrowserService.openMeeting(meetingLink.url, settings: settingsStore)
                    }
                },
                onOpenInCalendar: { AlertService.openEventInCalendar(event) }
            )
        )
        activeAlarmKey = key
    }

    /// Stops the alarm of one occurrence for good by switching it off in settings, then shows
    /// the next due alert.
    private func dismiss(key: String) {
        snoozedAlarms.removeValue(forKey: key)
        if activeAlarmKey == key {
            activeAlarmKey = nil
        }
        settingsStore?.disableEventAlarm(key: key)
        showNextDueAlarmSoon()
    }

    /// Schedules an alarm to re-fire after the specified number of minutes, then shows the
    /// next due alert.
    private func snooze(key: String, minutes: Int) {
        snoozedAlarms[key] = Date().addingTimeInterval(Double(minutes) * 60)
        if activeAlarmKey == key {
            activeAlarmKey = nil
        }
        showNextDueAlarmSoon()
    }

    /// Checks again right after the current work finishes, so a waiting alert appears as
    /// soon as the open one is handled instead of on the next tick. Deferred so it never runs
    /// while `AlertService` is still swapping panels.
    private func showNextDueAlarmSoon() {
        Task { [weak self] in
            self?.checkAlarms(replaySound: false)
        }
    }

    /// Updates the menu bar icon status based on the nearest upcoming non-all-day event.
    /// Shows the faded icon when paused, "NOW" during an active event, a countdown for
    /// upcoming events within the lead time, or idle when nothing is imminent.
    private func updateMenuBarStatus(events: [EKEvent], now: Date, settingsStore: SettingsStore) {
        if settingsStore.alarmsPaused {
            menuBarStatus = .paused
            return
        }

        let leadSeconds = Double(settingsStore.minutesBefore) * 60

        for event in events {
            guard !event.isAllDay else { continue }

            if now >= event.startDate, now < event.endDate {
                menuBarStatus = .active
                return
            }

            let timeUntilStart = event.startDate.timeIntervalSince(now)
            if timeUntilStart > 0, timeUntilStart <= leadSeconds {
                let minutesLeft = max(1, Int(ceil(timeUntilStart / 60)))
                menuBarStatus = .upcoming(minutesLeft: minutesLeft)
                return
            }
        }

        menuBarStatus = .idle
    }

    /// Forgets snoozes and the active alert of events that have ended or are no longer
    /// fetched, to prevent unbounded growth and let the next due alert take over.
    private func cleanupStaleEntries(events: [EKEvent], now: Date) {
        var endDates: [String: Date] = [:]
        for event in events {
            if let key = event.alarmKey, let end = event.endDate {
                endDates[key] = end
            }
        }
        let isLive: (String) -> Bool = { key in
            guard let end = endDates[key] else { return false }
            return end > now
        }

        snoozedAlarms = snoozedAlarms.filter { isLive($0.key) }
        if let activeAlarmKey, !isLive(activeAlarmKey) {
            self.activeAlarmKey = nil
        }
    }
}
