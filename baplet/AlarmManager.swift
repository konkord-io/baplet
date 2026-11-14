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
        case .idle: nil
        case .upcoming(let minutes): "\(minutes)m"
        case .active: "NOW"
        case .paused: nil
        }
    }
}

/// Observable alarm manager that checks events on a 30-second interval
/// and triggers the appropriate alert when an event is approaching.
@Observable
final class AlarmManager {
    /// Current status for the menu bar icon, updated on every timer tick.
    var menuBarStatus: MenuBarStatus = .idle

    /// Event identifiers for alarms the user has explicitly dismissed.
    private var dismissedAlarms: Set<String> = []

    /// Event identifiers for alarms that currently have a visual alert showing.
    /// Sound is replayed every tick while the alert remains open.
    private var activeAlerts: Set<String> = []

    /// Event identifiers mapped to the time when the snooze expires.
    private var snoozedAlarms: [String: Date] = [:]

    /// The repeating timer that drives alarm checks.
    private var timer: Timer?

    /// Reference to the calendar service for accessing events.
    private weak var calendarService: CalendarService?

    /// Reference to the settings store for alarm configuration.
    private weak var settingsStore: SettingsStore?

    /// Starts the alarm check timer on the main run loop.
    /// Should be called once during app startup after calendar data is loaded.
    func start(calendarService: CalendarService, settingsStore: SettingsStore) {
        self.calendarService = calendarService
        self.settingsStore = settingsStore

        checkAlarms()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkAlarms()
        }
    }

    /// Forces an immediate alarm check cycle, updating the menu bar icon right away.
    func recheckNow() {
        checkAlarms()
    }

    /// Stops the alarm check timer. Call when the app is shutting down.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Iterates over current events and fires an alarm if an event's start time
    /// minus the configured lead time has passed, and the alarm hasn't been
    /// fired, snoozed, or disabled.
    private func checkAlarms() {
        guard let calendarService, let settingsStore else { return }

        calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
        let now = Date()

        cleanupStaleEntries(events: calendarService.events, now: now)
        dismissedAlarms = dismissedAlarms.filter { !settingsStore.isAlarmEnabled(eventID: $0) }
        updateMenuBarStatus(events: calendarService.events, now: now, settingsStore: settingsStore)

        guard !settingsStore.alarmsPaused else { return }

        for event in calendarService.events {
            guard !event.isAllDay else { continue }

            let eventID = event.eventIdentifier ?? ""
            guard !eventID.isEmpty else { continue }

            guard settingsStore.isAlarmEnabled(eventID: eventID) else { continue }
            guard !dismissedAlarms.contains(eventID) else { continue }

            if let snoozeExpiry = snoozedAlarms[eventID] {
                guard now >= snoozeExpiry else { continue }
                snoozedAlarms.removeValue(forKey: eventID)
            }

            let alarmTime = event.startDate.addingTimeInterval(
                -Double(settingsStore.minutesBefore) * 60
            )
            guard now >= alarmTime, now < event.endDate else { continue }

            if activeAlerts.contains(eventID) {
                if settingsStore.soundEnabled {
                    AlertService.playAlarmSound()
                }
            } else {
                fireAlarm(for: event, settingsStore: settingsStore)
            }
            break
        }
    }

    /// Presents the configured alert style for the given event and marks it as actively alerting.
    /// Sound is played only when `soundEnabled` is true.
    private func fireAlarm(for event: EKEvent, settingsStore: SettingsStore) {
        let eventID = event.eventIdentifier ?? ""
        activeAlerts.insert(eventID)

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let nowString = formatter.string(from: Date())
        let timeString = "Now \(nowString) \u{00b7} \(formatter.string(from: event.startDate)) \u{2013} \(formatter.string(from: event.endDate))"
        let meetingLink = AlertService.extractMeetingLink(from: event)

        if settingsStore.soundEnabled {
            AlertService.playAlarmSound()
        }

        let style = settingsStore.alertStyle

        let openInCalendar = {
            AlertService.openEventInCalendar(
                title: event.title ?? "No Title",
                startDate: event.startDate,
                endDate: event.endDate,
                uid: event.calendarItemExternalIdentifier
            )
        }

        switch style {
        case .popupDialog:
            AlertService.showPopupAlert(
                title: event.title ?? "No Title",
                time: timeString,
                location: event.location,
                calendarName: event.calendar.title,
                meetingLink: meetingLink,
                onDismiss: { [weak self] in self?.dismiss(eventID: eventID) },
                onSnooze: { [weak self] minutes in self?.snooze(eventID: eventID, minutes: minutes) },
                onOpenInCalendar: openInCalendar,
                openMeetingURL: { url in BrowserService.openMeeting(url, settings: settingsStore) }
            )

        case .fullScreenGlassmorphic, .fullScreenBoldMinimal, .fullScreenWarmPlayful:
            AlertService.showFullScreenAlert(
                style: style,
                title: event.title ?? "No Title",
                time: timeString,
                location: event.location,
                calendarName: event.calendar.title,
                meetingLink: meetingLink,
                onDismiss: { [weak self] in self?.dismiss(eventID: eventID) },
                onSnooze: { [weak self] minutes in self?.snooze(eventID: eventID, minutes: minutes) },
                onOpenInCalendar: openInCalendar,
                openMeetingURL: { url in BrowserService.openMeeting(url, settings: settingsStore) }
            )
        }
    }

    /// Marks an alarm as permanently dismissed and disables it in settings.
    func dismiss(eventID: String) {
        activeAlerts.remove(eventID)
        dismissedAlarms.insert(eventID)
        snoozedAlarms.removeValue(forKey: eventID)
        if let settingsStore, settingsStore.isAlarmEnabled(eventID: eventID) {
            settingsStore.toggleEventAlarm(eventID: eventID)
        }
    }

    /// Schedules an alarm to re-fire after the specified number of minutes.
    func snooze(eventID: String, minutes: Int) {
        activeAlerts.remove(eventID)
        let snoozeExpiry = Date().addingTimeInterval(Double(minutes) * 60)
        snoozedAlarms[eventID] = snoozeExpiry
    }

    /// Updates the menu bar icon status based on the nearest upcoming non-all-day event.
    /// Shows bell.slash when paused, "NOW" during an active event, a countdown for
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

    /// Removes tracking entries for events that have already ended
    /// to prevent unbounded memory growth.
    private func cleanupStaleEntries(events: [EKEvent], now: Date) {
        let activeIDs = Set(events.compactMap(\.eventIdentifier))

        let isStillRelevant: (String) -> Bool = { id in
            if let event = events.first(where: { $0.eventIdentifier == id }) {
                return event.endDate > now
            }
            return activeIDs.contains(id)
        }

        dismissedAlarms = dismissedAlarms.filter(isStillRelevant)
        activeAlerts = activeAlerts.filter(isStillRelevant)
        snoozedAlarms = snoozedAlarms.filter { id, _ in isStillRelevant(id) }
    }
}
