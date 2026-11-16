//
//  EKEvent+Baplet.swift
//  baplet
//

import EventKit

extension EKEvent {
    /// The title shown in rows, alerts and previews; "No Title" for untitled events, so every
    /// screen labels them the same way.
    var displayTitle: String {
        title ?? "No Title"
    }

    /// Identifies this one occurrence for per-event alarm state (disabled, snoozed, alerting).
    /// Occurrences of a recurring event share `eventIdentifier`, so the start date is added;
    /// otherwise switching off one occurrence would silence the whole series. Nil when EventKit
    /// has no identifier for the event, in which case it gets no alarm controls. Demo events are
    /// never saved and have no identifier, so demo mode uses the title instead.
    var alarmKey: String? {
        guard let startDate, let id = eventIdentifier ?? (DemoMode.isEnabled ? title : nil) else { return nil }
        return EventAlarmKey.make(eventID: id, start: startDate)
    }

    /// The event's start and end time, e.g. "09:30 – 10:00", as shown in event rows.
    var timeRangeText: String {
        EventTimeFormat.range(from: startDate, to: endDate)
    }

    /// Whether the user is attending, declined (their own attendee entry says so) or the
    /// event was cancelled, so declined and cancelled meetings don't alert by default.
    var attendance: EventAttendance {
        EventAttendance(
            isCanceled: status == .canceled,
            ownStatus: attendees?.first(where: \.isCurrentUser)?.participantStatus
        )
    }
}

/// The user's part in an event, deciding whether it alerts by default.
enum EventAttendance: Equatable {
    case attending
    case declined
    case canceled

    /// Derives the attendance from the event's cancellation flag and the user's own
    /// participant status (nil when the event has no attendees or the user isn't among them,
    /// as with one's own private events). Cancellation wins over any response.
    init(isCanceled: Bool, ownStatus: EKParticipantStatus?) {
        if isCanceled {
            self = .canceled
        } else if ownStatus == .declined {
            self = .declined
        } else {
            self = .attending
        }
    }

    /// Whether the row shows the title struck through: the meeting is declined or cancelled.
    var isStruckThrough: Bool {
        self != .attending
    }
}

extension SettingsStore {
    /// Whether this occurrence's alarm is on, applying working hours, its attendance and the
    /// user's per-occurrence choice. False for events without an alarm key.
    func isAlarmEnabled(for event: EKEvent) -> Bool {
        guard let key = event.alarmKey else { return false }
        return isAlarmEnabled(key: key, attendance: event.attendance)
    }

    /// Switches this occurrence's alarm on or off (row checkbox, D key).
    func toggleEventAlarm(for event: EKEvent) {
        guard let key = event.alarmKey else { return }
        toggleEventAlarm(key: key, attendance: event.attendance)
    }
}

/// Builds and reads the per-occurrence keys behind `EKEvent.alarmKey`.
/// Format: `<eventIdentifier>|<start as Unix seconds>`.
enum EventAlarmKey {
    /// Character between the event identifier and the start time. Event identifiers can
    /// contain ":" and "@", so a character they don't use is chosen.
    private static let separator: Character = "|"

    /// Returns the key for the occurrence of `eventID` that starts at `start`.
    static func make(eventID: String, start: Date) -> String {
        "\(eventID)\(separator)\(Int(start.timeIntervalSince1970))"
    }

    /// Returns the start date stored in a key, or nil for a key that isn't in this format,
    /// so callers can tell which stored keys belong to occurrences that have already begun.
    static func startDate(of key: String) -> Date? {
        guard let index = key.lastIndex(of: separator),
              let seconds = Int(key[key.index(after: index)...]) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}

/// The time strings used for events, kept in one place so rows, alerts and previews match.
enum EventTimeFormat {
    /// A clock time in the user's short style, e.g. "09:30" or "9:30 AM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// A start–end range such as "09:30 – 10:00".
    static func range(from start: Date, to end: Date) -> String {
        "\(time(start)) \u{2013} \(time(end))"
    }

    /// The alert's time line, e.g. "Now 09:58 · 10:00 – 10:30", so the user sees how close the
    /// event is next to its time range.
    static func alertLine(now: Date, start: Date, end: Date) -> String {
        "Now \(time(now)) \u{00b7} \(range(from: start, to: end))"
    }
}
