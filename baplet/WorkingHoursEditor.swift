//
//  WorkingHoursEditor.swift
//  baplet
//

import SwiftUI

/// Form rows for working hours: an on/off switch, then (while on) the From and To times and
/// the working days. Shared by Settings → Alerts and the welcome guide, so both edit the
/// same `SettingsStore.workingHours` the same way.
struct WorkingHoursEditor: View {
    @Environment(SettingsStore.self) private var settingsStore

    /// Lays out the switch, and while working hours are on the times and the day buttons.
    var body: some View {
        @Bindable var settings = settingsStore

        Toggle("Only alert during working hours", isOn: $settings.workingHours.isEnabled)
        if settingsStore.workingHours.isEnabled {
            DatePicker("From", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
            DatePicker("To", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
            LabeledContent("Days") {
                WeekdayPicker(weekdays: $settings.workingHours.weekdays)
            }
        }
    }

    /// Binds a time picker to one of the window's minutes-after-midnight values, using today's
    /// date only as a carrier for the clock time.
    private func timeBinding(_ keyPath: WritableKeyPath<WorkingHours, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        return Binding(
            get: {
                calendar.date(byAdding: .minute, value: settingsStore.workingHours[keyPath: keyPath], to: day) ?? day
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                settingsStore.workingHours[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// A row of small toggle buttons, one per weekday in the user's week order (Monday first in
/// most of Europe), for picking working days.
private struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    /// Draws one capsule button per day, filled while the day is a working day.
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                let isOn = weekdays.contains(weekday)
                Button {
                    weekdays.formSymmetricDifference([weekday])
                } label: {
                    Text(Self.symbol(for: weekday))
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 22)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(
                            Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    /// Weekday numbers (1 = Sunday) starting from the calendar's first day of the week.
    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// The very short name of a weekday, e.g. "Mo", from the user's locale.
    private static func symbol(for weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return String(symbols[weekday - 1].prefix(2))
    }
}
