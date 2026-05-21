//
//  GlassmorphicAlertView.swift
//  calkitty
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import AppKit
import SwiftUI

/// Full-screen alert with a frosted glass card centered on a dark backdrop.
/// Features gradient accent buttons, soft shadows, and a spring entrance animation.
struct GlassmorphicAlertView: View {
    let props: FullScreenAlertProps

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Image("calkitty")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)

            Text("Upcoming Event")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1.5)

            VStack(spacing: 10) {
                Text(props.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(props.time)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))

                if let location = props.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.65))
                }

                Text(props.calendarName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 16) {
                snoozeButton
                dismissButton
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 40, y: 10)
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    /// Snooze button with a blue-to-purple gradient background.
    /// Click opens a dropdown with all snooze durations.
    private var snoozeButton: some View {
        Menu {
            ForEach(props.snoozeDurations, id: \.self) { minutes in
                Button("\(minutes) min") { props.onSnooze(minutes) }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Snooze")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(minWidth: 120, minHeight: 44)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Dismiss button with a glass-like semi-transparent background.
    /// Click opens a dropdown with dismiss, join meeting, and open-in-Calendar options.
    private var dismissButton: some View {
        Menu {
            Button("Dismiss") {
                props.onDismiss()
            }

            if let meetingLink = props.meetingLink {
                Button {
                    props.onDismiss()
                    NSWorkspace.shared.open(meetingLink.url)
                } label: {
                    Label("Dismiss and join \(meetingLink.serviceName)", systemImage: meetingLink.icon)
                }
            }

            Button {
                props.onOpenInCalendar()
            } label: {
                Label("Dismiss and open in Calendar", systemImage: "calendar")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Dismiss")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.9))
            .frame(minWidth: 120, minHeight: 44)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
