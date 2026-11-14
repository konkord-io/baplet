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

    /// Identity for `ForEach` and pickers: the stored raw value.
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

    /// Identity for `ForEach` and pickers: the stored raw value.
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

    /// How many days of events to display in the menu bar window.
    var daysToShow: Int {
        didSet { defaults.set(daysToShow, forKey: Keys.daysToShow) }
    }

    /// `EKEvent.alarmKey`s of the event occurrences whose alarm the user switched off (row
    /// checkbox, Today panel D key, or Dismiss on an alert). Keys of ended events are pruned.
    var disabledEventAlarms: Set<String> {
        didSet { defaults.set(Array(disabledEventAlarms), forKey: Keys.disabledEventAlarms) }
    }

    /// Lead time used until the user picks one, in minutes.
    static let defaultMinutesBefore = 5

    /// Days of events shown until the user picks a number.
    static let defaultDaysToShow = 2

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

    private let defaults: UserDefaults

    private enum Keys {
        static let enabledCalendarIDs = "enabledCalendarIDs"
        static let alertStyle = "alertStyle"
        /// Legacy key kept for migration from older versions.
        static let legacyAlertType = "alertType"
        static let soundEnabled = "soundEnabled"
        static let alarmsPaused = "alarmsPaused"
        static let minutesBefore = "minutesBefore"
        static let daysToShow = "daysToShow"
        static let disabledEventAlarms = "disabledEventAlarmKeys"
        /// Legacy key holding bare event identifiers, which silenced every occurrence of a
        /// recurring event. Dropped on launch, since the old entries can't be mapped to one
        /// occurrence.
        static let legacyDisabledEventAlarms = "disabledEventAlarms"
        static let meetingBrowserID = "meetingBrowserID"
        static let meetingBrowserProfileID = "meetingBrowserProfileID"
        static let onboardingCompleted = "onboardingCompleted"
        static let todayReturnAction = "todayReturnAction"
        /// Set once settings have been copied out of the old sandbox container.
        static let migratedFromSandboxContainer = "migratedFromSandboxContainer"
    }

    /// Loads all persisted settings from the given UserDefaults (the app's own by default;
    /// tests pass a throwaway suite), applying sensible defaults for values that haven't been
    /// set yet. `sandboxContainerPlist` is the old sandbox container's preferences file to
    /// migrate from; tests pass a temporary or missing file so the real container is never read.
    init(defaults: UserDefaults = .standard, sandboxContainerPlist: URL? = SettingsStore.defaultSandboxContainerPlist) {
        self.defaults = defaults
        Self.migrateFromSandboxContainerIfNeeded(into: defaults, containerPlist: sandboxContainerPlist)

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

        self.soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        self.alarmsPaused = defaults.bool(forKey: Keys.alarmsPaused)

        let storedMinutesBefore = defaults.integer(forKey: Keys.minutesBefore)
        self.minutesBefore = storedMinutesBefore > 0 ? storedMinutesBefore : Self.defaultMinutesBefore

        let storedDaysToShow = defaults.integer(forKey: Keys.daysToShow)
        self.daysToShow = storedDaysToShow > 0 ? storedDaysToShow : Self.defaultDaysToShow

        defaults.removeObject(forKey: Keys.legacyDisabledEventAlarms)
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
    private static func migrateFromSandboxContainerIfNeeded(into defaults: UserDefaults, containerPlist: URL?) {
        guard !defaults.bool(forKey: Keys.migratedFromSandboxContainer) else { return }
        defer { defaults.set(true, forKey: Keys.migratedFromSandboxContainer) }

        guard let containerPlist,
              let old = NSDictionary(contentsOf: containerPlist) as? [String: Any] else { return }
        copyMissingKeys(from: old, into: defaults)
    }

    /// The preferences file of the app's old sandbox container, or nil when the bundle has no
    /// identifier.
    static var defaultSandboxContainerPlist: URL? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")
    }

    /// Copies each entry of `old` into `defaults` unless the key already has a value there.
    /// Split out from the container lookup so the merge rule can be tested without the file.
    static func copyMissingKeys(from old: [String: Any], into defaults: UserDefaults) {
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    /// Switches the alarm of one event occurrence (by `EKEvent.alarmKey`) on or off.
    func toggleEventAlarm(key: String) {
        if disabledEventAlarms.contains(key) {
            disabledEventAlarms.remove(key)
        } else {
            disabledEventAlarms.insert(key)
        }
    }

    /// Switches the alarm of one event occurrence off; used when its alert is dismissed.
    func disableEventAlarm(key: String) {
        disabledEventAlarms.insert(key)
    }

    /// Returns whether the alarm is enabled for one event occurrence.
    func isAlarmEnabled(key: String) -> Bool {
        !disabledEventAlarms.contains(key)
    }

    /// Forgets switched-off alarms of occurrences that have ended, so the stored set doesn't
    /// grow forever. A key counts as ended when its occurrence started before `now` and it is
    /// not among `liveKeys`, the keys of the currently fetched events (which include events
    /// still running). Only writes when something was removed.
    func pruneDisabledEventAlarms(keeping liveKeys: Set<String>, now: Date) {
        let kept = disabledEventAlarms.filter { key in
            guard let start = EventAlarmKey.startDate(of: key) else { return false }
            return start >= now || liveKeys.contains(key)
        }
        if kept.count != disabledEventAlarms.count {
            disabledEventAlarms = kept
        }
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
