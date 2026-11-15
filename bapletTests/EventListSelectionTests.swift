//
//  EventListSelectionTests.swift
//  bapletTests
//

import Testing
@testable import Baplet

/// Tests for `EventListSelection`, the keyboard selection behind the menu's event list.
struct EventListSelectionTests {
    /// Alarm keys of three rows in display order.
    let keys = ["a", "b", "c"]

    /// Checks that nothing is selected until the first arrow key.
    @Test
    func startsWithNothingSelected() {
        #expect(EventListSelection().selectedKey == nil)
    }

    /// Checks that either arrow selects the first row when nothing is selected yet.
    @Test
    func firstArrowSelectsFirstRow() {
        let down = EventListSelection()
        down.move(by: 1, in: keys)
        #expect(down.selectedKey == "a")

        let up = EventListSelection()
        up.move(by: -1, in: keys)
        #expect(up.selectedKey == "a")
    }

    /// Checks that moving stops at both ends instead of wrapping.
    @Test
    func moveStopsAtEnds() {
        let selection = EventListSelection()
        selection.move(by: 1, in: keys)
        selection.move(by: 1, in: keys)
        selection.move(by: 1, in: keys)
        #expect(selection.selectedKey == "c")
        selection.move(by: 1, in: keys)
        #expect(selection.selectedKey == "c")
        selection.move(by: -1, in: keys)
        selection.move(by: -1, in: keys)
        selection.move(by: -1, in: keys)
        #expect(selection.selectedKey == "a")
    }

    /// Checks that the selection follows its event when the list is re-fetched with rows
    /// before it removed, rather than sticking to an index.
    @Test
    func followsEventAcrossRefresh() {
        let selection = EventListSelection()
        selection.selectedKey = "b"
        selection.move(by: 1, in: ["b", "c"])
        #expect(selection.selectedKey == "c")
    }

    /// Checks that an arrow restarts at the first row when the selected event has gone.
    @Test
    func restartsWhenSelectedEventIsGone() {
        let selection = EventListSelection()
        selection.selectedKey = "gone"
        selection.move(by: 1, in: keys)
        #expect(selection.selectedKey == "a")
    }

    /// Checks that an empty list clears the selection, and that `reset` clears it too.
    @Test
    func emptyListAndResetClearSelection() {
        let selection = EventListSelection()
        selection.selectedKey = "a"
        selection.move(by: 1, in: [])
        #expect(selection.selectedKey == nil)

        selection.selectedKey = "b"
        selection.reset()
        #expect(selection.selectedKey == nil)
    }
}
