//
//  PanelKeyMonitor.swift
//  baplet
//

import AppKit

/// Virtual key codes the panels react to, named so key handlers read as what they mean.
enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

extension NSEvent {
    /// True for Return and the keypad's Enter, which the panels treat the same.
    var isReturnKey: Bool {
        keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter
    }
}

/// One local key-down monitor that only sees keys typed into a given panel. Used by the alert
/// and Today panels, which handle their own shortcuts before SwiftUI does.
final class PanelKeyMonitor {
    /// The token from `NSEvent.addLocalMonitorForEvents`, while monitoring.
    private var token: Any?

    /// Starts passing key-down events aimed at `window` to `handler`, replacing any earlier
    /// monitor. The handler returns nil to swallow the key or the event to let it through;
    /// keys for other windows always pass through untouched.
    func start(for window: NSWindow, handler: @escaping (NSEvent) -> NSEvent?) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, event.window === window else { return event }
            return handler(event)
        }
    }

    /// Removes the monitor, if one is installed.
    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}
