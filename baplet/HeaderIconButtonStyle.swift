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
            .iconHoverHighlight(isHovering: isHovering, isPressed: configuration.isPressed)
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
    }
}

/// Small icon button style for the controls on an event row (join meeting, alarm checkbox):
/// the same rounded hover/press highlight as the header icons, so it's clear which control
/// the pointer is on. It leaves the cursor to the row.
struct RowIconButtonStyle: ButtonStyle {
    /// Builds the styled button; hover state lives in `RowIconButton` because a
    /// `ButtonStyle` itself cannot hold `@State`.
    func makeBody(configuration: Configuration) -> some View {
        RowIconButton(configuration: configuration)
    }
}

/// The view behind `RowIconButtonStyle`, tracking whether the pointer is over the button.
private struct RowIconButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    /// Draws the label with the hover/press highlight behind it.
    var body: some View {
        configuration.label
            .iconHoverHighlight(isHovering: isHovering, isPressed: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

extension View {
    /// Puts the view in a fixed 26 pt hit area with a rounded highlight behind it: none at
    /// rest, subtle on hover and stronger while pressed, matching macOS toolbar and Control
    /// Center buttons.
    func iconHoverHighlight(isHovering: Bool, isPressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let opacity = isPressed ? 0.30 : (isHovering ? 0.20 : 0)
        return frame(width: 26, height: 26)
            .background(shape.fill(Color.primary.opacity(opacity)))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: opacity)
    }
}

extension ButtonStyle where Self == RowIconButtonStyle {
    /// Shorthand so call sites can write `.buttonStyle(.rowIcon)`.
    static var rowIcon: RowIconButtonStyle { RowIconButtonStyle() }
}

extension ButtonStyle where Self == HeaderIconButtonStyle {
    /// Shorthand so call sites can write `.buttonStyle(.headerIcon(help: "…"))`.
    static func headerIcon(help: String) -> HeaderIconButtonStyle {
        HeaderIconButtonStyle(help: help)
    }
}
