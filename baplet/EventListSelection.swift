//
//  EventListSelection.swift
//  baplet
//

import AppKit
import Observation

/// Keyboard selection for the menu's event list. It is keyed by `EKEvent.alarmKey` rather than
/// by index because the menu's events are re-fetched while it is open. Nothing is selected
/// until the first arrow key or pointer move, so mouse users never see an unexpected highlight.
@Observable
final class EventListSelection {
    /// Alarm key of the highlighted row, or nil when nothing is selected.
    var selectedKey: String?

    /// Where the mouse pointer was when the selection last followed it. Rows only take the
    /// selection on hover once the pointer has really moved, so arrow-key scrolling under a
    /// resting pointer doesn't steal the selection.
    @ObservationIgnored private var lastPointerLocation = NSEvent.mouseLocation

    /// Moves the selection up or down through `keys` (the rows in display order), stopping at
    /// the first and last row. With nothing selected, or when the selected event has gone
    /// from the list, either arrow selects the first row: the meeting happening now or the next.
    func move(by offset: Int, in keys: [String]) {
        guard !keys.isEmpty else {
            selectedKey = nil
            return
        }
        guard let selectedKey, let current = keys.firstIndex(of: selectedKey) else {
            self.selectedKey = keys[0]
            return
        }
        self.selectedKey = keys[min(max(current + offset, 0), keys.count - 1)]
    }

    /// Selects the row under the pointer, but only if the pointer has moved since last time.
    func pointerEntered(key: String) {
        let location = NSEvent.mouseLocation
        guard location != lastPointerLocation else { return }
        lastPointerLocation = location
        selectedKey = key
    }

    /// Clears the selection, so the menu opens without a highlight next time.
    func reset() {
        selectedKey = nil
        lastPointerLocation = NSEvent.mouseLocation
    }
}
