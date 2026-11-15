//
//  HoverLabel.swift
//  baplet
//

import SwiftUI

extension View {
    /// Shows `text` in a small tooltip-like label under the view after the pointer rests on it,
    /// and uses it as the accessibility label. Used instead of `.help` because AppKit tooltips
    /// in the `MenuBarExtra` window stay silent until the first click inside the menu.
    /// `suppressed` hides the label, for example while a button is pressed.
    func hoverLabel(_ text: String, suppressed: Bool = false) -> some View {
        modifier(HoverLabelModifier(text: text, suppressed: suppressed))
    }
}

/// Tracks the pointer over its view and shows a `HoverLabelCard` below it after a delay close
/// to the system tooltip delay, aligned to the view's trailing edge so labels near the right
/// edge of a window stay inside it.
private struct HoverLabelModifier: ViewModifier {
    let text: String
    let suppressed: Bool
    @State private var isHovering = false
    @State private var showsLabel = false
    @State private var showTask: Task<Void, Never>?

    /// How long the pointer has to rest on the view before the label appears.
    private static let delay: Duration = .milliseconds(600)

    /// Gap between the bottom of the view and the top of the label.
    private static let gap: CGFloat = 4

    /// Adds the label as an overlay hanging below the view, plus the hover tracking.
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                GeometryReader { proxy in
                    if showsLabel {
                        HoverLabelCard(text: text)
                            .frame(width: proxy.size.width, alignment: .trailing)
                            .offset(y: proxy.size.height + Self.gap)
                            .transition(.opacity)
                    }
                }
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering { schedule() } else { hide() }
            }
            .onChange(of: suppressed) { _, isSuppressed in
                if isSuppressed { hide() }
            }
            .onDisappear { hide() }
            .accessibilityLabel(text)
            .animation(.easeOut(duration: 0.12), value: showsLabel)
    }

    /// Starts the delay after which the label appears, replacing any pending one.
    private func schedule() {
        showTask?.cancel()
        showTask = Task { @MainActor in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, isHovering, !suppressed else { return }
            showsLabel = true
        }
    }

    /// Cancels a pending label and hides one that is showing.
    private func hide() {
        showTask?.cancel()
        showTask = nil
        showsLabel = false
    }
}

/// Small tooltip-like card, styled after the macOS tooltip.
private struct HoverLabelCard: View {
    let text: String

    /// Draws the text on a small rounded material card that never takes mouse events.
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))
            )
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .allowsHitTesting(false)
    }
}
