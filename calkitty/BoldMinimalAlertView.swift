//
//  BoldMinimalAlertView.swift
//  calkitty
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import AppKit
import SwiftUI

/// Full-screen alert with oversized typography floating on a dark backdrop.
/// No card container — content floats directly on the background with a slide-up entrance.
struct BoldMinimalAlertView: View {
    let props: FullScreenAlertProps

    @State private var appeared = false

    var body: some View {
        ZStack {
            Image("calkitty")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .opacity(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(60)

            VStack(spacing: 28) {
                Text("UPCOMING EVENT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(4)

                VStack(spacing: 14) {
                    Text(props.title)
                        .font(.system(size: 52, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 700)

                    Text(props.time)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.7))

                    if let location = props.location, !location.isEmpty {
                        Label(location, systemImage: "location")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(props.calendarName)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.3))
                }

                HStack(spacing: 20) {
                    snoozeButton
                    dismissButton
                }
                .padding(.top, 12)
            }
            .offset(y: appeared ? 0 : 30)
            .opacity(appeared ? 1.0 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    /// Snooze button with a blue-to-indigo gradient in a capsule shape.
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
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(minWidth: 140, minHeight: 48)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Dismiss button with a semi-transparent white capsule background.
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
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.8))
            .frame(minWidth: 140, minHeight: 48)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
