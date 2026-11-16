//
//  FocusStatus.swift
//  baplet
//

import AppIntents
import Foundation

/// The Focus filter users attach to a Focus in System Settings → Focus → Focus Filters. macOS
/// runs `perform()` when that Focus turns on (with the values the user chose) and off (with the
/// defaults), and `current` returns the active values, so Baplet also knows about a Focus that
/// was already on at launch. Works without a paid developer account; a Debug build's filter
/// only shows up when no other installed copy shares its bundle ID.
struct BapletFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Baplet alerts"
    static let description: IntentDescription? = "Hold back Baplet's meeting alerts while this Focus is on."

    @Parameter(title: "Hold back alerts", default: false)
    var holdAlerts: Bool

    /// How the filter is summarised in the Focus settings.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: holdAlerts ? "Hold back alerts" : "Show alerts")
    }

    /// Called by macOS when the Focus this filter belongs to turns on or off; hands the value
    /// to `FocusStatus`, which lets `AlarmManager` hold or release alerts.
    func perform() async throws -> some IntentResult {
        let holdAlerts = holdAlerts
        await MainActor.run { FocusStatus.shared.update(filterHoldsAlerts: holdAlerts) }
        return .result()
    }
}

/// Whether a Focus with Baplet's filter is asking to hold back alerts. Shared, because macOS
/// calls the filter outside SwiftUI; the menu reads it and `AlarmManager` re-checks on change.
@MainActor
@Observable
final class FocusStatus {
    static let shared = FocusStatus()

    /// True while a Focus whose Baplet filter has "Hold back alerts" on is active.
    private(set) var filterHoldsAlerts = false

    /// Called after `filterHoldsAlerts` changes, so a held alert shows as soon as Focus ends.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Stores the filter value from `BapletFocusFilter.perform()` or the launch read, and
    /// notifies `onChange` when it differs from before.
    func update(filterHoldsAlerts: Bool) {
        guard filterHoldsAlerts != self.filterHoldsAlerts else { return }
        self.filterHoldsAlerts = filterHoldsAlerts
        onChange?()
    }

    /// Reads the filter value macOS reports at launch, so a Focus already on counts. Errors
    /// leave the state at "not holding", the safe side for an alarm app.
    func loadCurrent() async {
        guard let current = try? await BapletFocusFilter.current else { return }
        update(filterHoldsAlerts: current.holdAlerts)
    }

    /// Whether alerts are held now: the user turned on "Hold back alerts during Focus" and a
    /// Focus with Baplet's filter asks for it. Both are needed, so the setting is a master switch.
    func holdsAlerts(settingEnabled: Bool) -> Bool {
        Self.holdsAlerts(settingEnabled: settingEnabled, filterHoldsAlerts: filterHoldsAlerts)
    }

    /// The rule behind `holdsAlerts(settingEnabled:)`, separate so it can be tested.
    nonisolated static func holdsAlerts(settingEnabled: Bool, filterHoldsAlerts: Bool) -> Bool {
        settingEnabled && filterHoldsAlerts
    }
}
