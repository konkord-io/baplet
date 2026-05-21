//
//  WarmPlayfulAlertView.swift
//  calkitty
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import AppKit
import SwiftUI

/// Full-screen alert with a warm purple gradient background, rounded card, and playful styling.
/// Features coral/pink chunky buttons, a large hero cat image, and a bouncy spring entrance.
struct WarmPlayfulAlertView: View {
    let props: FullScreenAlertProps

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Image("calkitty")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            Text("Upcoming Event")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))

            VStack(spacing: 10) {
                Text(props.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(props.time)
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 0.95))

                if let location = props.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(props.calendarName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: 16) {
                snoozeButton
                dismissButton
            }
            .padding(.top, 8)
        }
        .padding(36)
        .frame(maxWidth: 480)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.12, blue: 0.35),
                    Color(red: 0.18, green: 0.08, blue: 0.28),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.purple.opacity(0.4), radius: 30, y: 8)
        .scaleEffect(appeared ? 1.0 : 0.9)
        .opacity(appeared ? 1.0 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.3, green: 0.15, blue: 0.45),
                    Color(red: 0.2, green: 0.08, blue: 0.35),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    /// Snooze button with a coral-to-pink gradient and an orange glow shadow.
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
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(minWidth: 120, minHeight: 48)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.4, blue: 0.35),
                        Color(red: 0.95, green: 0.3, blue: 0.5),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.orange.opacity(0.4), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// Dismiss button with a semi-transparent white rounded background.
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
            .fontWeight(.bold)
            .foregroundStyle(.white.opacity(0.85))
            .frame(minWidth: 120, minHeight: 48)
            .background(.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
