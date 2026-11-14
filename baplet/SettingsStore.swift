//
//  SettingsStore.swift
//  baplet
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

/// What Return does to the selected event in the Today panel; ⌘Return does the other one.
enum TodayReturnAction: String, CaseIterable, Identifiable {
    case joinMeeting
    case openCalendar

    var id: String { rawValue }

    /// Label for the Settings picker and the Today panel's key hints.
    var label: String {
        switch self {
        case .joinMeeting: "Join meeting"
        case .openCalendar: "Open in Calendar"
        }
    }

    /// Short form for the Today panel's key-hint strip.
    var hintLabel: String {
        switch self {
        case .joinMeeting: "join"
        case .openCalendar: "Calendar"
        }
    }

    /// The action ⌘Return performs when this one is on Return.
    var alternate: TodayReturnAction {
        self == .joinMeeting ? .openCalendar : .joinMeeting
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

    /// Whether alarm notifications are temporarily paused.
    var alarmsPaused: Bool {
        didSet { defaults.set(alarmsPaused, forKey: Keys.alarmsPaused) }
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

    /// Bundle identifier of the browser that opens meeting links; nil means the system default.
    var meetingBrowserID: String? {
        didSet { defaults.set(meetingBrowserID, forKey: Keys.meetingBrowserID) }
    }

    /// Profile to open meeting links in, as `BrowserProfile.id` for the chosen browser;
    /// nil means the browser's own default profile.
    var meetingBrowserProfileID: String? {
        didSet { defaults.set(meetingBrowserProfileID, forKey: Keys.meetingBrowserProfileID) }
    }

    /// What Return does in the Today panel (⌘Return does the other action).
    var todayReturnAction: TodayReturnAction {
        didSet { defaults.set(todayReturnAction.rawValue, forKey: Keys.todayReturnAction) }
    }

    /// Whether the user has finished the welcome guide; until then a launch with no
    /// calendars selected opens the guide instead of Settings.
    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabledCalendarIDs = "enabledCalendarIDs"
        static let alertStyle = "alertStyle"
        /// Legacy key kept for migration from older versions.
        static let legacyAlertType = "alertType"
        static let soundEnabled = "soundEnabled"
        static let alarmsPaused = "alarmsPaused"
        static let minutesBefore = "minutesBefore"
        static let daysToShow = "daysToShow"
        static let disabledEventAlarms = "disabledEventAlarms"
        static let meetingBrowserID = "meetingBrowserID"
        static let meetingBrowserProfileID = "meetingBrowserProfileID"
        static let onboardingCompleted = "onboardingCompleted"
        static let todayReturnAction = "todayReturnAction"
        /// Set once settings have been copied out of the old sandbox container.
        static let migratedFromSandboxContainer = "migratedFromSandboxContainer"
    }

    /// Loads all persisted settings from UserDefaults, applying sensible defaults
    /// for values that haven't been set yet.
    init() {
        Self.migrateFromSandboxContainerIfNeeded(into: defaults)

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

        if defaults.object(forKey: Keys.alarmsPaused) != nil {
            self.alarmsPaused = defaults.bool(forKey: Keys.alarmsPaused)
        } else {
            self.alarmsPaused = false
        }

        let storedMinutesBefore = defaults.integer(forKey: Keys.minutesBefore)
        self.minutesBefore = storedMinutesBefore > 0 ? storedMinutesBefore : 5

        let storedDaysToShow = defaults.integer(forKey: Keys.daysToShow)
        self.daysToShow = storedDaysToShow > 0 ? storedDaysToShow : 2

        let storedDisabledAlarms = defaults.stringArray(forKey: Keys.disabledEventAlarms) ?? []
        self.disabledEventAlarms = Set(storedDisabledAlarms)

        self.meetingBrowserID = defaults.string(forKey: Keys.meetingBrowserID)
        self.meetingBrowserProfileID = defaults.string(forKey: Keys.meetingBrowserProfileID)
        self.onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        self.todayReturnAction = defaults.string(forKey: Keys.todayReturnAction)
            .flatMap(TodayReturnAction.init(rawValue:)) ?? .joinMeeting
    }

    /// Copies settings saved while Baplet was sandboxed (before profile support needed the
    /// sandbox off) from the old container into the regular preferences, once. Only keys not
    /// already present are copied, so nothing set since then is overwritten.
    private static func migrateFromSandboxContainerIfNeeded(into defaults: UserDefaults) {
        guard !defaults.bool(forKey: Keys.migratedFromSandboxContainer),
              let bundleID = Bundle.main.bundleIdentifier else { return }
        defer { defaults.set(true, forKey: Keys.migratedFromSandboxContainer) }

        let containerPlist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")
        guard let old = NSDictionary(contentsOf: containerPlist) as? [String: Any] else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
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
