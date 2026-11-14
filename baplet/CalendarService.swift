//
//  CalendarService.swift
//  calkitty
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

    /// Events fetched for the current time window, optionally filtered by enabled calendars.
    var events: [EKEvent] = []

    private let store = EKEventStore()
    private var changeObserver: (any NSObjectProtocol)?

    /// Last-used filter parameters, retained so notification-driven refreshes
    /// can reapply the same calendar/day filters without external input.
    private var lastEnabledCalendarIDs: Set<String> = []
    private var lastDaysToShow: Int = 2

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

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    /// Requests full calendar access from the user using the modern async API.
    /// Updates `authorizationStatus` after the request completes.
    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                loadCalendars()
                fetchEvents()
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    /// Loads all sources and calendars from the event store into published properties.
    func loadCalendars() {
        sources = store.sources.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Fetches events from now through the end of the specified number of days.
    /// Only events from calendars in `enabledCalendarIDs` are included.
    /// When the set is empty, no events are returned.
    func fetchEvents(enabledCalendarIDs: Set<String> = [], daysToShow: Int = 2) {
        lastEnabledCalendarIDs = enabledCalendarIDs
        lastDaysToShow = daysToShow

        guard !enabledCalendarIDs.isEmpty else {
            events = []
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysToShow, to: now)!)

        let filtered = calendars.filter { enabledCalendarIDs.contains($0.calendarIdentifier) }
        guard !filtered.isEmpty else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: filtered)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
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

    /// Reloads calendars and re-fetches events. Call after external calendar changes.
    func refresh(enabledCalendarIDs: Set<String> = [], daysToShow: Int = 2) {
        store.refreshSourcesIfNecessary()
        loadCalendars()
        fetchEvents(enabledCalendarIDs: enabledCalendarIDs, daysToShow: daysToShow)
    }

    /// Returns all calendars belonging to a given source.
    func calendars(for source: EKSource) -> [EKCalendar] {
        calendars.filter { $0.source == source }
    }
}
