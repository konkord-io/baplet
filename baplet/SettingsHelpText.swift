//
//  SettingsHelpText.swift
//  baplet
//

import AppKit
import SwiftUI

/// Short grey explanation shown at the top of a settings tab or welcome guide step. The text is Markdown, so it can
/// contain links; links into System Settings go through `openSystemSettings` so they land on
/// the right pane.
struct SettingsHelpText: View {
    let text: LocalizedStringKey

    /// Creates the help text from a string literal, parsed as Markdown.
    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "x-apple.systempreferences" else { return .systemAction }
                Self.openSystemSettings(url)
                return .handled
            })
    }

    /// Opens a System Settings pane URL. A running System Settings ignores the pane in the URL
    /// and shows General instead, so it is quit first (waiting up to 3 s for it to exit).
    private static func openSystemSettings(_ url: URL) {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            NSWorkspace.shared.open(url)
            return
        }
        running.terminate()
        Task {
            for _ in 0..<30 where !running.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
            NSWorkspace.shared.open(url)
        }
    }
}
