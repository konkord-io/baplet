//
//  AlarmManager.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import EventKit
import Foundation
import os

/// Represents the current state of the menu bar icon.
enum MenuBarStatus: Equatable {
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
        case .upcoming(let minutes): Self.countdownText(minutes: minutes)
        case .active: "NOW"
        }
    }

    /// A countdown in minutes as the menu bar shows it: "3m" under an hour, then "1h34m",
    /// or "2h" on the hour.
    static func countdownText(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h\(rest)m"
    }

    /// Works out the menu bar status from the fetched events. Only timed events whose alarm is
    /// on (`isAlarmEnabled`, which also applies working hours) count, so the menu bar matches
    /// what will alert. During such a meeting it shows NOW, unless the next one starts within
    /// the alert lead time, which then gets the countdown. Otherwise it counts down to the next
    /// meeting today once it is within `countdownMinutes` (nil: any time today), and is idle
    /// when nothing qualifies. Pure, so the rules can be tested without a clock or EventKit.
    static func compute(
        events: [EKEvent],
        now: Date,
        isPaused: Bool,
        alertLeadMinutes: Int,
        countdownMinutes: Int?,
        isAlarmEnabled: (EKEvent) -> Bool,
        calendar: Calendar = .current
    ) -> MenuBarStatus {
        if isPaused { return .paused }

        let relevant = events.filter { !$0.isAllDay && isAlarmEnabled($0) }
        let isRunning = relevant.contains { $0.startDate <= now && now < $0.endDate }
        let next = relevant
            .filter { $0.startDate > now && calendar.isDate($0.startDate, inSameDayAs: now) }
            .min { $0.startDate < $1.startDate }
        let secondsToNext = next.map { $0.startDate.timeIntervalSince(now) }
        let minutesToNext = secondsToNext.map { max(1, Int(ceil($0 / 60))) }

        if isRunning {
            if let secondsToNext, let minutesToNext, secondsToNext <= Double(alertLeadMinutes) * 60 {
                return .upcoming(minutesLeft: minutesToNext)
            }
            return .active
        }
        guard let secondsToNext, let minutesToNext else { return .idle }
        if let countdownMinutes, secondsToNext > Double(countdownMinutes) * 60 {
            return .idle
        }
        return .upcoming(minutesLeft: minutesToNext)
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

        FocusStatus.shared.onChange = { [weak self] in self?.recheckNow() }
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

    /// Closes stray alert windows, re-fetches events, forgets state of ended events (closing
    /// their alert), updates the menu bar icon and, unless alarms are paused or a Focus holds
    /// them back (`FocusStatus`), either replays the open alert's sound (when `replaySound`,
    /// i.e. on a timer tick) or shows the alert of the first due event when none is open.
    private func checkAlarms(replaySound: Bool) {
        guard let calendarService, let settingsStore else { return }

        calendarService.fetchEvents(for: settingsStore)
        let events = calendarService.events
        let now = AppClock.now()

        AlertService.closeStrayPanels()
        cleanupStaleEntries(events: events, now: now)
        settingsStore.pruneDisabledEventAlarms(keeping: Set(events.compactMap(\.alarmKey)), now: now)
        updateMenuBarStatus(events: events, now: now, settingsStore: settingsStore)

        guard !settingsStore.alarmsPaused,
              !FocusStatus.shared.holdsAlerts(settingEnabled: settingsStore.holdAlertsDuringFocus) else { return }

        if activeAlarmKey != nil {
            if replaySound, settingsStore.soundEnabled {
                AlertService.playAlarmSound(settings: settingsStore)
            }
            return
        }

        if let next = events.first(where: { isDue($0, now: now, settingsStore: settingsStore) }) {
            fireAlarm(for: next, settingsStore: settingsStore)
        }
    }

    /// Whether the event's alarm should be on screen now: a timed event whose alarm is
    /// enabled (which rules out declined and cancelled meetings by default) and not snoozed, between its alarm time (start minus the lead time) and its end.
    private func isDue(_ event: EKEvent, now: Date, settingsStore: SettingsStore) -> Bool {
        guard !event.isAllDay,
              let key = event.alarmKey,
              settingsStore.isAlarmEnabled(for: event) else { return false }
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
        let attendance = event.attendance
        snoozedAlarms.removeValue(forKey: key)

        if settingsStore.soundEnabled {
            AlertService.playAlarmSound(settings: settingsStore)
        }

        let meetingLink = AlertService.extractMeetingLink(from: event)
        let overlapping = overlappingEvents(with: event, settingsStore: settingsStore)
        let overlappingKeys = overlapping.compactMap(\.alarmKey)
        let end = event.endDate ?? AppClock.now()
        AlertService.show(
            style: settingsStore.alertStyle,
            props: AlertProps(
                title: event.displayTitle,
                time: EventTimeFormat.alertLine(now: AppClock.now(), start: event.startDate, end: event.endDate),
                location: event.location,
                calendarName: event.calendar?.title ?? "",
                meetingLink: meetingLink,
                onDismiss: { [weak self] in self?.dismiss(key: key, attendance: attendance) },
                onSnooze: { [weak self] minutes in self?.snooze(key: key, minutes: minutes) },
                onOpenMeeting: { [weak self] in
                    self?.hold(keys: overlappingKeys, until: end)
                    if let meetingLink {
                        BrowserService.openMeeting(meetingLink.url, settings: settingsStore)
                    }
                },
                onOpenInCalendar: { [weak self] in
                    self?.hold(keys: overlappingKeys, until: end)
                    AlertService.openEventInCalendar(event)
                },
                overlapping: overlapping.map { other in
                    OverlappingMeeting(
                        id: other.alarmKey ?? other.displayTitle,
                        title: other.displayTitle,
                        timeRange: other.timeRangeText,
                        calendarColor: other.calendar?.cgColor
                    )
                }
            )
        )
        activeAlarmKey = key
    }

    /// The fetched meetings that overlap `event` in time and would alert themselves (timed,
    /// alarm on, so declined, cancelled and quiet meetings are left out), sorted by start.
    private func overlappingEvents(with event: EKEvent, settingsStore: SettingsStore) -> [EKEvent] {
        guard let calendarService, let key = event.alarmKey, let start = event.startDate, let end = event.endDate else { return [] }
        let candidates = calendarService.events.filter { !$0.isAllDay && settingsStore.isAlarmEnabled(for: $0) }
        let slots = candidates.compactMap { other -> MeetingOverlap.Slot? in
            guard let otherKey = other.alarmKey, let otherStart = other.startDate, let otherEnd = other.endDate else { return nil }
            return MeetingOverlap.Slot(key: otherKey, start: otherStart, end: otherEnd)
        }
        let overlappingKeys = MeetingOverlap.overlapping(MeetingOverlap.Slot(key: key, start: start, end: end), in: slots).map(\.key)
        return overlappingKeys.compactMap { overlapKey in candidates.first { $0.alarmKey == overlapKey } }
    }

    /// Holds the alerts of the given occurrences until `date` (the end of the meeting the user
    /// just joined), through the snooze list: one still running then alerts, one over by then
    /// never does. A longer existing snooze is kept.
    private func hold(keys: [String], until date: Date) {
        guard !keys.isEmpty else { return }
        for key in keys {
            snoozedAlarms[key] = max(snoozedAlarms[key] ?? date, date)
        }
        AlertService.log.notice("Held \(keys.count, privacy: .public) overlapping meeting(s) until the joined one ends")
    }

    /// Stops the alarm of one occurrence for good by switching it off in settings, then shows
    /// the next due alert. `attendance` picks the stored set the switch-off goes into.
    private func dismiss(key: String, attendance: EventAttendance) {
        snoozedAlarms.removeValue(forKey: key)
        if activeAlarmKey == key {
            activeAlarmKey = nil
        }
        settingsStore?.disableEventAlarm(key: key, attendance: attendance)
        showNextDueAlarmSoon()
    }

    /// Schedules an alarm to re-fire after the specified number of minutes, then shows the
    /// next due alert.
    private func snooze(key: String, minutes: Int) {
        snoozedAlarms[key] = AppClock.now().addingTimeInterval(Double(minutes) * 60)
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

    /// Updates the menu bar status from the fetched events with the current settings; the
    /// rules live in `MenuBarStatus.compute`.
    private func updateMenuBarStatus(events: [EKEvent], now: Date, settingsStore: SettingsStore) {
        menuBarStatus = MenuBarStatus.compute(
            events: events,
            now: now,
            isPaused: settingsStore.alarmsPaused,
            alertLeadMinutes: settingsStore.minutesBefore,
            countdownMinutes: settingsStore.countdownRange.minutesAhead(alertLeadMinutes: settingsStore.minutesBefore),
            isAlarmEnabled: { event in settingsStore.isAlarmEnabled(for: event) }
        )
    }

    /// Forgets snoozes and the active alert of events that have ended or are no longer
    /// fetched, to prevent unbounded growth and let the next due alert take over. The alert
    /// window of such an event is closed too; if the event comes back while still running,
    /// the next check shows it again.
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
            AlertService.closeActiveAlert(reason: "meeting ended")
        }
    }
}
