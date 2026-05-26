//
//  SettingsStore.swift
//  calkitty
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import Foundation

/// The visual style of alert to display when an alarm triggers.
/// This controls the visual presentation; sound is controlled separately via `soundEnabled`.
enum AlertStyle: String, CaseIterable, Identifiable {
    case popupDialog
    case fullScreenGlassmorphic
    case fullScreenBoldMinimal
    case fullScreenWarmPlayful

    var id: String { rawValue }

    /// Human-readable label for display in the settings UI.
    var label: String {
        switch self {
        case .popupDialog: "Popup Dialog"
        case .fullScreenGlassmorphic: "Glassmorphic"
        case .fullScreenBoldMinimal: "Bold & Minimal"
        case .fullScreenWarmPlayful: "Warm & Playful"
        }
    }

    /// Whether this style uses a full-screen overlay panel.
    var isFullScreen: Bool {
        self != .popupDialog
    }

    /// Migrates legacy AlertType raw values to the new AlertStyle.
    /// "sound" and "popupDialog" both map to popupDialog;
    /// "fullScreenOverlay" maps to fullScreenGlassmorphic.
    static func migrated(from rawValue: String) -> AlertStyle {
        switch rawValue {
        case "sound": .popupDialog
        case "fullScreenOverlay": .fullScreenGlassmorphic
        default: AlertStyle(rawValue: rawValue) ?? .popupDialog
        }
    }
}

/// Observable settings store that persists user preferences to UserDefaults.
/// Manages calendar selection, alert configuration, and per-event alarm opt-outs.
@Observable
final class SettingsStore {
    /// Which calendars the user has enabled for display and alarms.
    var enabledCalendarIDs: Set<String> {
        didSet { defaults.set(Array(enabledCalendarIDs), forKey: Keys.enabledCalendarIDs) }
    }

    /// The visual style of alert to show when an alarm fires.
    var alertStyle: AlertStyle {
        didSet { defaults.set(alertStyle.rawValue, forKey: Keys.alertStyle) }
    }

    /// Whether to play a sound when an alarm fires.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// How many minutes before an event's start time to trigger the alarm.
    var minutesBefore: Int {
        didSet { defaults.set(minutesBefore, forKey: Keys.minutesBefore) }
    }

    /// How many days of events to display in the menu bar popover.
    var daysToShow: Int {
        didSet { defaults.set(daysToShow, forKey: Keys.daysToShow) }
    }

    /// Event identifiers for which the user has disabled alarms via context menu.
    var disabledEventAlarms: Set<String> {
        didSet { defaults.set(Array(disabledEventAlarms), forKey: Keys.disabledEventAlarms) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabledCalendarIDs = "enabledCalendarIDs"
        static let alertStyle = "alertStyle"
        /// Legacy key kept for migration from older versions.
        static let legacyAlertType = "alertType"
        static let soundEnabled = "soundEnabled"
        static let minutesBefore = "minutesBefore"
        static let daysToShow = "daysToShow"
        static let disabledEventAlarms = "disabledEventAlarms"
    }

    /// Loads all persisted settings from UserDefaults, applying sensible defaults
    /// for values that haven't been set yet.
    init() {
        let storedCalendarIDs = defaults.stringArray(forKey: Keys.enabledCalendarIDs) ?? []
        self.enabledCalendarIDs = Set(storedCalendarIDs)

        if let storedStyle = defaults.string(forKey: Keys.alertStyle) {
            self.alertStyle = AlertStyle(rawValue: storedStyle) ?? .popupDialog
        } else if let legacyValue = defaults.string(forKey: Keys.legacyAlertType) {
            let migrated = AlertStyle.migrated(from: legacyValue)
            self.alertStyle = migrated
            defaults.set(migrated.rawValue, forKey: Keys.alertStyle)
            defaults.removeObject(forKey: Keys.legacyAlertType)
        } else {
            self.alertStyle = .popupDialog
        }

        // Defaults to true when the key has never been set (object is nil).
        if defaults.object(forKey: Keys.soundEnabled) != nil {
            self.soundEnabled = defaults.bool(forKey: Keys.soundEnabled)
        } else {
            self.soundEnabled = true
        }

        let storedMinutesBefore = defaults.integer(forKey: Keys.minutesBefore)
        self.minutesBefore = storedMinutesBefore > 0 ? storedMinutesBefore : 5

        let storedDaysToShow = defaults.integer(forKey: Keys.daysToShow)
        self.daysToShow = storedDaysToShow > 0 ? storedDaysToShow : 2

        let storedDisabledAlarms = defaults.stringArray(forKey: Keys.disabledEventAlarms) ?? []
        self.disabledEventAlarms = Set(storedDisabledAlarms)
    }

    /// Toggles the alarm enabled state for a specific event by its identifier.
    func toggleEventAlarm(eventID: String) {
        if disabledEventAlarms.contains(eventID) {
            disabledEventAlarms.remove(eventID)
        } else {
            disabledEventAlarms.insert(eventID)
        }
    }

    /// Returns whether the alarm is enabled for a specific event.
    func isAlarmEnabled(eventID: String) -> Bool {
        !disabledEventAlarms.contains(eventID)
    }

    /// Toggles whether a calendar is included in the enabled set.
    func toggleCalendar(calendarID: String) {
        if enabledCalendarIDs.contains(calendarID) {
            enabledCalendarIDs.remove(calendarID)
        } else {
            enabledCalendarIDs.insert(calendarID)
        }
    }

    /// Returns whether a calendar is currently enabled for display and alarms.
    func isCalendarEnabled(calendarID: String) -> Bool {
        enabledCalendarIDs.contains(calendarID)
    }
}
