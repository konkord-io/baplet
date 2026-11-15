//
//  SettingsStoreTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `SettingsStore`, each running against its own throwaway UserDefaults suite.
struct SettingsStoreTests {
    /// A container preferences path that does not exist, so tests never read the real one.
    let missingPlist = URL(fileURLWithPath: "/nonexistent/baplet-tests.plist")

    /// Runs `body` with a fresh, empty UserDefaults suite and removes the suite afterwards,
    /// so tests never share state or touch the app's real preferences.
    func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "bapletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// Checks every setting's default on an empty store.
    @Test
    func defaultsOnEmptyStore() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(store.enabledCalendarIDs.isEmpty)
            #expect(store.alertStyle == .popupDialog)
            #expect(store.soundEnabled)
            #expect(!store.alarmsPaused)
            #expect(store.minutesBefore == SettingsStore.defaultMinutesBefore)
            #expect(store.daysToShow == SettingsStore.defaultDaysToShow)
            #expect(store.disabledEventAlarms.isEmpty)
            #expect(store.meetingBrowserID == nil)
            #expect(store.meetingBrowserProfileID == nil)
            #expect(!store.onboardingCompleted)
            #expect(store.todayReturnAction == .joinMeeting)
            #expect(store.checkForUpdatesAutomatically)
            #expect(store.lastUpdateCheck == nil)
        }
    }

    /// Checks that changes persist and are read back by a new store on the same defaults.
    @Test
    func valuesPersist() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            store.minutesBefore = 10
            store.alertStyle = .fullScreenBoldMinimal
            store.toggleCalendar(calendarID: "cal-1")
            let reloaded = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(reloaded.minutesBefore == 10)
            #expect(reloaded.alertStyle == .fullScreenBoldMinimal)
            #expect(reloaded.enabledCalendarIDs == ["cal-1"])
        }
    }

    /// Checks the legacy `alertType` values map to the new styles, that the new key is
    /// written and the old one removed.
    @Test(arguments: [
        ("sound", AlertStyle.popupDialog),
        ("popupDialog", .popupDialog),
        ("fullScreenOverlay", .fullScreenGlassmorphic),
    ])
    func legacyAlertTypeMigration(legacy: String, expected: AlertStyle) {
        withDefaults { defaults in
            defaults.set(legacy, forKey: "alertType")
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(store.alertStyle == expected)
            #expect(defaults.string(forKey: "alertStyle") == expected.rawValue)
            #expect(defaults.object(forKey: "alertType") == nil)
        }
    }

    /// Checks that a stored `alertStyle` wins over a leftover legacy `alertType`.
    @Test
    func alertStyleBeatsLegacyType() {
        withDefaults { defaults in
            defaults.set("fullScreenWarmPlayful", forKey: "alertStyle")
            defaults.set("sound", forKey: "alertType")
            #expect(SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist).alertStyle == .fullScreenWarmPlayful)
        }
    }

    /// Checks that the sandbox merge copies only keys missing from the target and leaves
    /// existing values untouched.
    @Test
    func sandboxMigrationCopiesOnlyMissingKeys() {
        withDefaults { defaults in
            defaults.set(15, forKey: "minutesBefore")
            let old: [String: Any] = ["minutesBefore": 3, "daysToShow": 7, "soundEnabled": false]
            SettingsStore.copyMissingKeys(from: old, into: defaults)
            #expect(defaults.integer(forKey: "minutesBefore") == 15)
            #expect(defaults.integer(forKey: "daysToShow") == 7)
            #expect(defaults.object(forKey: "soundEnabled") as? Bool == false)
        }
    }

    /// Checks the whole migration path with a temporary container plist: missing keys are
    /// imported, existing ones kept, and a second store does not import again.
    @Test
    func sandboxMigrationImportsFromPlist() throws {
        let plist = FileManager.default.temporaryDirectory
            .appendingPathComponent("baplet-tests-\(UUID().uuidString).plist")
        try (["minutesBefore": 3, "daysToShow": 7] as NSDictionary).write(to: plist)
        defer { try? FileManager.default.removeItem(at: plist) }
        withDefaults { defaults in
            defaults.set(15, forKey: "minutesBefore")
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: plist)
            #expect(store.minutesBefore == 15)
            #expect(store.daysToShow == 7)
            defaults.removeObject(forKey: "daysToShow")
            #expect(SettingsStore(defaults: defaults, sandboxContainerPlist: plist).daysToShow
                == SettingsStore.defaultDaysToShow)
        }
    }

    /// Checks that creating a store sets the migration marker, so the container is read once.
    @Test
    func sandboxMigrationSetsMarker() {
        withDefaults { defaults in
            #expect(!defaults.bool(forKey: "migratedFromSandboxContainer"))
            _ = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(defaults.bool(forKey: "migratedFromSandboxContainer"))
        }
    }

    /// Checks that with the marker already set a new store imports nothing, whatever the old
    /// container holds.
    @Test
    func sandboxMigrationRunsOnce() {
        withDefaults { defaults in
            defaults.set(true, forKey: "migratedFromSandboxContainer")
            _ = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            let keys = Set(defaults.dictionaryRepresentation().keys)
            #expect(!keys.contains("daysToShow"))
            #expect(!keys.contains("enabledCalendarIDs"))
        }
    }

    /// Checks that the old-format disabled alarms (bare event ids) are dropped on launch and
    /// not carried into the new key.
    @Test
    func legacyDisabledAlarmsAreDropped() {
        withDefaults { defaults in
            defaults.set(["old-event-id"], forKey: "disabledEventAlarms")
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(store.disabledEventAlarms.isEmpty)
            #expect(defaults.object(forKey: "disabledEventAlarms") == nil)
        }
    }

    /// Checks that new-format disabled keys survive a reload.
    @Test
    func disabledAlarmKeysSurviveReload() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            store.disableEventAlarm(key: "id|1800000000")
            #expect(SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist).disabledEventAlarms == ["id|1800000000"])
        }
    }

    /// Checks that pruning removes keys of ended, no longer fetched occurrences (and
    /// malformed keys), but keeps future ones and ended ones still in the live set.
    @Test
    func pruneRemovesEndedKeepsCurrent() {
        withDefaults { defaults in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let ended = EventAlarmKey.make(eventID: "a", start: now.addingTimeInterval(-7200))
            let running = EventAlarmKey.make(eventID: "b", start: now.addingTimeInterval(-600))
            let future = EventAlarmKey.make(eventID: "c", start: now.addingTimeInterval(3600))
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            store.disabledEventAlarms = [ended, running, future, "garbage"]

            store.pruneDisabledEventAlarms(keeping: [running], now: now)
            #expect(store.disabledEventAlarms == [running, future])
            #expect(Set(defaults.stringArray(forKey: "disabledEventAlarmKeys") ?? []) == [running, future])
        }
    }

    /// A local-time date in November 2026 (the 18th is a Wednesday, the 21st a Saturday),
    /// local because `SettingsStore` reads working hours with the current calendar.
    func localDate(day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// Checks that working hours start off at Mon–Fri 08:00–16:00, the countdown at all day,
    /// and nothing is switched on outside working hours.
    @Test
    func workingHoursAndCountdownDefaults() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(store.workingHours == .standard)
            #expect(!store.workingHours.isEnabled)
            #expect(store.countdownRange == .allDay)
            #expect(store.enabledOutsideHoursAlarms.isEmpty)
        }
    }

    /// Checks that, with working hours on, meetings inside them alert unless switched off and
    /// meetings outside them only when switched on, and that dismissing undoes a switch-on.
    @Test
    func alarmsFollowWorkingHours() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            store.workingHours.isEnabled = true
            let inside = EventAlarmKey.make(eventID: "a", start: localDate(day: 18, hour: 10))
            let outside = EventAlarmKey.make(eventID: "b", start: localDate(day: 21, hour: 10))

            #expect(store.isAlarmEnabled(key: inside))
            #expect(!store.isAlarmEnabled(key: outside))

            store.toggleEventAlarm(key: inside)
            store.toggleEventAlarm(key: outside)
            #expect(!store.isAlarmEnabled(key: inside))
            #expect(store.isAlarmEnabled(key: outside))
            #expect(store.disabledEventAlarms == [inside])
            #expect(store.enabledOutsideHoursAlarms == [outside])

            store.disableEventAlarm(key: outside)
            #expect(!store.isAlarmEnabled(key: outside))
            #expect(store.enabledOutsideHoursAlarms.isEmpty)
        }
    }

    /// Checks that working hours and the countdown choice survive a reload.
    @Test
    func workingHoursSurviveReload() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            store.workingHours = WorkingHours(isEnabled: true, startMinutes: 9 * 60, endMinutes: 17 * 60 + 30, weekdays: [2, 4])
            store.countdownRange = .minutes30
            let reloaded = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            #expect(reloaded.workingHours == store.workingHours)
            #expect(reloaded.countdownRange == .minutes30)
        }
    }

    /// Checks that pruning also forgets switched-on alarms of ended occurrences.
    @Test
    func pruneAlsoForgetsEnabledOutsideHours() {
        withDefaults { defaults in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let ended = EventAlarmKey.make(eventID: "a", start: now.addingTimeInterval(-7200))
            let future = EventAlarmKey.make(eventID: "c", start: now.addingTimeInterval(3600))
            let store = SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist)
            store.enabledOutsideHoursAlarms = [ended, future]
            store.pruneDisabledEventAlarms(keeping: [], now: now)
            #expect(store.enabledOutsideHoursAlarms == [future])
        }
    }

    /// Checks the Return action default and that `alternate` flips between the two actions.
    @Test
    func todayReturnActionAlternate() {
        #expect(TodayReturnAction.joinMeeting.alternate == .openCalendar)
        #expect(TodayReturnAction.openCalendar.alternate == .joinMeeting)
        withDefaults { defaults in
            #expect(SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist).todayReturnAction == .joinMeeting)
            defaults.set("bogus", forKey: "todayReturnAction")
            #expect(SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist).todayReturnAction == .joinMeeting)
            defaults.set("openCalendar", forKey: "todayReturnAction")
            #expect(SettingsStore(defaults: defaults, sandboxContainerPlist: missingPlist).todayReturnAction == .openCalendar)
        }
    }
}
