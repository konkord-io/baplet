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

    /// Which sound alerts play when sound is on.
    var alertSound: AlertSound {
        didSet { defaults.set(alertSound.rawValue, forKey: Keys.alertSound) }
    }

    /// Volume of alert sounds from 0 to 1, relative to the Mac's own volume.
    var alertVolume: Double {
        didSet { defaults.set(alertVolume, forKey: Keys.alertVolume) }
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

    /// `EKEvent.alarmKey`s of occurrences that are quiet by default (outside working hours,
    /// declined or cancelled; see `isQuietByDefault`) whose alarm the user switched on. Keys of
    /// ended events are pruned. The name predates declined and cancelled events; it is kept so
    /// the stored key stays the same.
    var enabledOutsideHoursAlarms: Set<String> {
        didSet { defaults.set(Array(enabledOutsideHoursAlarms), forKey: Keys.enabledOutsideHoursAlarms) }
    }

    /// Whether meetings the user declined alert like any other. Off by default: a declined
    /// meeting stays quiet unless switched on per occurrence.
    var alertForDeclinedMeetings: Bool {
        didSet { defaults.set(alertForDeclinedMeetings, forKey: Keys.alertForDeclinedMeetings) }
    }

    /// When Baplet alerts by default; off until the user turns it on.
    var workingHours: WorkingHours {
        didSet {
            defaults.set(workingHours.isEnabled, forKey: Keys.workingHoursEnabled)
            defaults.set(workingHours.startMinutes, forKey: Keys.workingHoursStart)
            defaults.set(workingHours.endMinutes, forKey: Keys.workingHoursEnd)
            defaults.set(workingHours.weekdays.sorted(), forKey: Keys.workingHoursWeekdays)
        }
    }

    /// How long before a meeting the menu bar starts counting down to it.
    var countdownRange: CountdownRange {
        didSet { defaults.set(countdownRange.rawValue, forKey: Keys.countdownRange) }
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

    /// Whether Baplet checks GitHub for a new version once a day on its own.
    var checkForUpdatesAutomatically: Bool {
        didSet { defaults.set(checkForUpdatesAutomatically, forKey: Keys.checkForUpdatesAutomatically) }
    }

    /// When the last successful update check finished; nil before the first one.
    /// The automatic check waits until this is more than a day old.
    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Keys.lastUpdateCheck) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabledCalendarIDs = "enabledCalendarIDs"
        static let alertStyle = "alertStyle"
        /// Legacy key kept for migration from older versions.
        static let legacyAlertType = "alertType"
        static let soundEnabled = "soundEnabled"
        static let alertSound = "alertSound"
        static let alertVolume = "alertVolume"
        static let alarmsPaused = "alarmsPaused"
        static let minutesBefore = "minutesBefore"
        static let daysToShow = "daysToShow"
        static let disabledEventAlarms = "disabledEventAlarmKeys"
        static let enabledOutsideHoursAlarms = "enabledOutsideHoursAlarmKeys"
        static let alertForDeclinedMeetings = "alertForDeclinedMeetings"
        static let workingHoursEnabled = "workingHoursEnabled"
        static let workingHoursStart = "workingHoursStartMinutes"
        static let workingHoursEnd = "workingHoursEndMinutes"
        static let workingHoursWeekdays = "workingHoursWeekdays"
        static let countdownRange = "countdownRange"
        /// Legacy key holding bare event identifiers, which silenced every occurrence of a
        /// recurring event. Dropped on launch, since the old entries can't be mapped to one
        /// occurrence.
        static let legacyDisabledEventAlarms = "disabledEventAlarms"
        static let meetingBrowserID = "meetingBrowserID"
        static let meetingBrowserProfileID = "meetingBrowserProfileID"
        static let onboardingCompleted = "onboardingCompleted"
        static let todayReturnAction = "todayReturnAction"
        static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
        static let lastUpdateCheck = "lastUpdateCheck"
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
        self.alertSound = defaults.string(forKey: Keys.alertSound).flatMap(AlertSound.init(rawValue:)) ?? AlertSound.defaultSound
        self.alertVolume = defaults.object(forKey: Keys.alertVolume) as? Double ?? 1
        self.alarmsPaused = defaults.bool(forKey: Keys.alarmsPaused)

        let storedMinutesBefore = defaults.integer(forKey: Keys.minutesBefore)
        self.minutesBefore = storedMinutesBefore > 0 ? storedMinutesBefore : Self.defaultMinutesBefore

        let storedDaysToShow = defaults.integer(forKey: Keys.daysToShow)
        self.daysToShow = storedDaysToShow > 0 ? storedDaysToShow : Self.defaultDaysToShow

        defaults.removeObject(forKey: Keys.legacyDisabledEventAlarms)
        let storedDisabledAlarms = defaults.stringArray(forKey: Keys.disabledEventAlarms) ?? []
        self.disabledEventAlarms = Set(storedDisabledAlarms)
        self.enabledOutsideHoursAlarms = Set(defaults.stringArray(forKey: Keys.enabledOutsideHoursAlarms) ?? [])
        self.alertForDeclinedMeetings = defaults.bool(forKey: Keys.alertForDeclinedMeetings)

        let standard = WorkingHours.standard
        self.workingHours = WorkingHours(
            isEnabled: defaults.bool(forKey: Keys.workingHoursEnabled),
            startMinutes: defaults.object(forKey: Keys.workingHoursStart) as? Int ?? standard.startMinutes,
            endMinutes: defaults.object(forKey: Keys.workingHoursEnd) as? Int ?? standard.endMinutes,
            weekdays: (defaults.array(forKey: Keys.workingHoursWeekdays) as? [Int]).map(Set.init) ?? standard.weekdays
        )
        self.countdownRange = defaults.string(forKey: Keys.countdownRange)
            .flatMap(CountdownRange.init(rawValue:)) ?? .allDay

        self.meetingBrowserID = defaults.string(forKey: Keys.meetingBrowserID)
        self.meetingBrowserProfileID = defaults.string(forKey: Keys.meetingBrowserProfileID)
        self.onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        self.todayReturnAction = defaults.string(forKey: Keys.todayReturnAction)
            .flatMap(TodayReturnAction.init(rawValue:)) ?? .joinMeeting
        self.checkForUpdatesAutomatically = defaults.object(forKey: Keys.checkForUpdatesAutomatically) as? Bool ?? true
        self.lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
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

    /// Switches the alarm of one event occurrence (by `EKEvent.alarmKey`) on or off. Occurrences
    /// that are quiet by default (`isQuietByDefault`) are off unless switched on; all others
    /// are on unless switched off. `attendance` is the occurrence's `EKEvent.attendance`.
    func toggleEventAlarm(key: String, attendance: EventAttendance = .attending) {
        if isQuietByDefault(key: key, attendance: attendance) {
            enabledOutsideHoursAlarms.formSymmetricDifference([key])
        } else {
            disabledEventAlarms.formSymmetricDifference([key])
        }
    }

    /// Switches the alarm of one event occurrence off; used when its alert is dismissed.
    func disableEventAlarm(key: String, attendance: EventAttendance = .attending) {
        if isQuietByDefault(key: key, attendance: attendance) {
            enabledOutsideHoursAlarms.remove(key)
        } else {
            disabledEventAlarms.insert(key)
        }
    }

    /// Returns whether the alarm is enabled for one event occurrence: occurrences that are
    /// quiet by default only when switched on, all others unless switched off.
    func isAlarmEnabled(key: String, attendance: EventAttendance = .attending) -> Bool {
        if isQuietByDefault(key: key, attendance: attendance) {
            return enabledOutsideHoursAlarms.contains(key)
        }
        return !disabledEventAlarms.contains(key)
    }

    /// Whether an occurrence stays silent unless the user switches its alarm on: it starts
    /// outside working hours, was cancelled, or was declined while `alertForDeclinedMeetings`
    /// is off. Cancelled meetings ignore that setting, since they aren't happening.
    func isQuietByDefault(key: String, attendance: EventAttendance) -> Bool {
        switch attendance {
        case .canceled: true
        case .declined: !alertForDeclinedMeetings || isOutsideWorkingHours(key: key)
        case .attending: isOutsideWorkingHours(key: key)
        }
    }

    /// Whether the occurrence behind `key` starts outside working hours, read from the start
    /// time stored in the key. Keys without one (demo events) count as inside.
    func isOutsideWorkingHours(key: String) -> Bool {
        guard let start = EventAlarmKey.startDate(of: key) else { return false }
        return !workingHours.contains(start)
    }

    /// Forgets switched-off (and, outside working hours, switched-on) alarms of occurrences
    /// that have ended, so the stored sets don't grow forever. A key counts as ended when its
    /// occurrence started before `now` and it is not among `liveKeys`, the keys of the
    /// currently fetched events (which include events still running). Only writes when
    /// something was removed.
    func pruneDisabledEventAlarms(keeping liveKeys: Set<String>, now: Date) {
        let isLive: (String) -> Bool = { key in
            guard let start = EventAlarmKey.startDate(of: key) else { return false }
            return start >= now || liveKeys.contains(key)
        }
        let keptDisabled = disabledEventAlarms.filter(isLive)
        if keptDisabled.count != disabledEventAlarms.count {
            disabledEventAlarms = keptDisabled
        }
        let keptEnabled = enabledOutsideHoursAlarms.filter(isLive)
        if keptEnabled.count != enabledOutsideHoursAlarms.count {
            enabledOutsideHoursAlarms = keptEnabled
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
