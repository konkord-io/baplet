//
//  CalendarService.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import EventKit
import SwiftUI

/// Observable service that wraps EKEventStore to provide calendar data.
/// Handles authorization, fetching calendars/sources, loading events,
/// and observing external calendar changes.
@Observable
final class CalendarService {
    /// Current EventKit authorization status for calendar access.
    var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    /// All calendar sources available on the system (iCloud, Google, Local, etc.).
    var sources: [EKSource] = []

    /// All calendars across all sources.
    var calendars: [EKCalendar] = []

    /// Events fetched for the current time window from the enabled calendars; empty when no
    /// calendar is enabled.
    var events: [EKEvent] = []

    private let store = EKEventStore()
    private var changeObserver: (any NSObjectProtocol)?

    /// Last-used filter parameters, retained so notification-driven refreshes
    /// can reapply the same calendar/day filters without external input.
    private var lastEnabledCalendarIDs: Set<String> = []
    private var lastDaysToShow: Int = SettingsStore.defaultDaysToShow

    /// Registers an observer for EKEventStoreChanged notifications so the event list
    /// refreshes automatically when calendars or events change externally.
    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refresh(enabledCalendarIDs: self.lastEnabledCalendarIDs, daysToShow: self.lastDaysToShow)
        }
    }

    /// Removes the EKEventStoreChanged observer so NotificationCenter stops calling into a
    /// released service.
    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    /// Requests full calendar access from the user using the modern async API.
    /// Updates `authorizationStatus` and, when granted, loads the calendar list; callers fetch
    /// events afterwards with their own calendar selection.
    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                loadCalendars()
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    /// Loads all sources and calendars from the event store into the observed properties.
    func loadCalendars() {
        sources = store.sources.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Fetches events for the calendars and number of days chosen in Settings. The one entry
    /// point the app uses, so every caller applies the same selection.
    func fetchEvents(for settings: SettingsStore) {
        fetchEvents(enabledCalendarIDs: settings.enabledCalendarIDs, daysToShow: settings.daysToShow)
    }

    /// Reloads calendars and re-fetches events for the selection chosen in Settings, picking
    /// up calendars added or removed since launch.
    func refresh(for settings: SettingsStore) {
        refresh(enabledCalendarIDs: settings.enabledCalendarIDs, daysToShow: settings.daysToShow)
    }

    /// Fetches events from now through the end of the specified number of days.
    /// Only events from calendars in `enabledCalendarIDs` are included.
    /// When the set is empty, no events are returned.
    private func fetchEvents(enabledCalendarIDs: Set<String>, daysToShow: Int) {
        lastEnabledCalendarIDs = enabledCalendarIDs
        lastDaysToShow = daysToShow

        let now = Date()
        let calendar = Calendar.current
        guard let lastDay = calendar.date(byAdding: .day, value: daysToShow, to: now) else {
            events = []
            return
        }
        events = events(from: now, to: calendar.startOfDay(for: lastDay), inCalendars: enabledCalendarIDs)
    }

    /// Reloads calendars and re-fetches events with the given filter. Used after external
    /// calendar changes and by the menu's refresh button.
    private func refresh(enabledCalendarIDs: Set<String>, daysToShow: Int) {
        store.refreshSourcesIfNecessary()
        loadCalendars()
        fetchEvents(enabledCalendarIDs: enabledCalendarIDs, daysToShow: daysToShow)
    }

    /// Returns up to `limit` timed and all-day events from now through the next `days` days in
    /// the given calendars, without changing the published event list. Used by the welcome
    /// guide's Test button to preview what the selected calendars contain.
    func upcomingEvents(in calendarIDs: Set<String>, days: Int = 7, limit: Int = 5) -> [EKEvent] {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }
        return Array(events(from: now, to: end, inCalendars: calendarIDs).prefix(limit))
    }

    /// Returns all of today's events (midnight to midnight, including ones already over) from
    /// the given calendars: all-day events first, then by start time. Used by the Today panel.
    func todaysEvents(enabledCalendarIDs: Set<String>) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end, inCalendars: enabledCalendarIDs).sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startDate < $1.startDate
        }
    }

    /// The shared EventKit query: events overlapping `start`–`end` in the given calendars,
    /// sorted by start time. Empty when none of the IDs match a known calendar, because an
    /// EventKit predicate with no calendars would search every calendar instead.
    private func events(from start: Date, to end: Date, inCalendars calendarIDs: Set<String>) -> [EKEvent] {
        let selected = calendars.filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// Groups the current events by calendar day, returning tuples of (day start date, events).
    /// Days are labeled "Today", "Tomorrow", or a date string in the UI layer.
    func eventsByDay() -> [(day: Date, events: [EKEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }
        return grouped.sorted { $0.key < $1.key }.map { (day: $0.key, events: $0.value) }
    }

    /// Returns all calendars belonging to a given source.
    func calendars(for source: EKSource) -> [EKCalendar] {
        calendars.filter { $0.source == source }
    }

    /// Identifiers of every calendar, for the "Select All" buttons in Settings and the
    /// welcome guide.
    var allCalendarIDs: Set<String> {
        Set(calendars.map(\.calendarIdentifier))
    }
}
