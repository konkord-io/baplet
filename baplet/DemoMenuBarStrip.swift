//
//  DemoMenuBarStrip.swift
//  baplet
//

import SwiftUI

/// The demo scene `menubar`: a small desktop with a macOS-like menu bar strip, showing Baplet's
/// icon and countdown between neutral system icons and the clock. Drawn by Baplet itself, so a
/// screenshot of it can never show the owner's real menu bar items.
struct DemoMenuBarStrip: View {
    /// Minutes until the next meeting shown in the countdown (1h23m).
    static let minutesToNextMeeting = 83

    /// Height of the drawn menu bar, matching a menu bar on a screen without a notch.
    private static let barHeight: CGFloat = 26

    /// Size of the scene, also used as the window's content size so no extra space shows.
    static let size = CGSize(width: 640, height: 150)

    var body: some View {
        VStack(spacing: 0) {
            menuBar
            desktop
        }
        .frame(minWidth: Self.size.width, maxWidth: .infinity, minHeight: Self.size.height, maxHeight: .infinity)
    }

    /// The strip: the Apple menu and a few neutral menu titles on the left; neutral status
    /// icons, Baplet's icon with its countdown and the clock on the right.
    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.bold)
            Text("File")
            Text("Edit")
            Text("View")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            baplet
            Image(systemName: "switch.2")
            Text(Self.clockText)
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: Self.barHeight)
        .background(Color.black.opacity(0.35))
    }

    /// Baplet's menu bar item, built from the same template image and countdown format as
    /// `MenuBarLabel`, with the highlight macOS draws behind an item.
    private var baplet: some View {
        HStack(spacing: 2) {
            Image("BapletToolbar")
            Text(MenuBarStatus.countdownText(minutes: Self.minutesToNextMeeting))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
    }

    /// The area under the strip, in the system window background, so the shot matches the
    /// grey of the other screenshots' windows.
    private var desktop: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    /// The clock on the right of the strip, e.g. "Mon 16 Nov 09:55" as macOS shows it, from
    /// the demo clock.
    private static var clockText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM HH:mm"
        return formatter.string(from: AppClock.now())
    }
}
