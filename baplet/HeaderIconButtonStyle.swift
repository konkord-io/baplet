//
//  HeaderIconButtonStyle.swift
//  baplet
//

import AppKit
import SwiftUI

/// Icon-only button style for the menu window header: a rounded highlight on hover and a
/// slightly stronger one while pressed, matching macOS toolbar and Control Center buttons,
/// with a `hoverLabel` naming the button.
struct HeaderIconButtonStyle: ButtonStyle {
    /// Text of the hover label, also used as the button's accessibility label.
    let help: String

    /// Builds the styled button; hover state lives in `HeaderIconButton` because a
    /// `ButtonStyle` itself cannot hold `@State`.
    func makeBody(configuration: Configuration) -> some View {
        HeaderIconButton(configuration: configuration, help: help)
    }
}

/// The view behind `HeaderIconButtonStyle`, tracking whether the pointer is over the button.
private struct HeaderIconButton: View {
    let configuration: ButtonStyleConfiguration
    let help: String
    @State private var isHovering = false

    /// Draws the label inside a fixed hit area with the hover/press highlight behind it and
    /// the hover label below it. The menu window is never key, so the cursor is otherwise
    /// left to whichever app is underneath; setting the arrow on hover keeps stray resize
    /// cursors away.
    var body: some View {
        configuration.label
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(backgroundOpacity))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .hoverLabel(help, suppressed: configuration.isPressed)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                    NSCursor.arrow.set()
                case .ended:
                    isHovering = false
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// Highlight strength: none at rest, subtle on hover, stronger while pressed.
    private var backgroundOpacity: Double {
        if configuration.isPressed { return 0.18 }
        return isHovering ? 0.10 : 0
    }
}

extension ButtonStyle where Self == HeaderIconButtonStyle {
    /// Shorthand so call sites can write `.buttonStyle(.headerIcon(help: "…"))`.
    static func headerIcon(help: String) -> HeaderIconButtonStyle {
        HeaderIconButtonStyle(help: help)
    }
}
