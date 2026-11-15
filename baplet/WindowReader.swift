//
//  WindowReader.swift
//  baplet
//

import AppKit
import SwiftUI

/// Invisible view that hands the `NSWindow` it is placed in to `onWindow`, for AppKit work
/// SwiftUI has no API for, such as key monitors on the menu and Settings windows.
struct WindowReader: NSViewRepresentable {
    /// Called on the main thread once the view is in a window, and again if it moves.
    let onWindow: (NSWindow) -> Void

    /// Creates the tracking view.
    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindow = onWindow
        return view
    }

    /// Keeps the callback current when SwiftUI updates the view.
    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindow = onWindow
    }

    /// The AppKit view that notices when it joins a window.
    final class WindowReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        /// Reports the new window after the current layout pass, so SwiftUI state can change.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onWindow?(window)
            }
        }
    }
}
