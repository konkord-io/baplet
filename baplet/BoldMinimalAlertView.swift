//
//  BoldMinimalAlertView.swift
//  baplet
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
            Image("goldfish")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .opacity(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(60)

            VStack(spacing: 28) {
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
                    openButton
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

    /// Snooze split button: click snoozes for 5 min, dropdown arrow shows all durations.
    private var snoozeButton: some View {
        HStack(spacing: 0) {
            Button { props.onSnooze(5) } label: {
                Text("Snooze 5m")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 24)

            Menu {
                ForEach(props.snoozeDurations, id: \.self) { minutes in
                    Button("\(minutes) min") { props.onSnooze(minutes) }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            LinearGradient(
                colors: [Color.blue, Color.indigo],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
    }

    /// Dismiss button: turns off the alarm for this event.
    private var dismissButton: some View {
        Button { props.onDismiss() } label: {
            Text("Dismiss")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.1))
        .clipShape(Capsule())
    }

    /// Open split button: a click joins the meeting (or opens Calendar when there is no link);
    /// with a meeting link, the dropdown offers "Open meeting" and "Open calendar".
    /// Opening in any way stops the alarm.
    private var openButton: some View {
        HStack(spacing: 0) {
            Button { props.openDefault() } label: {
                Text("Open")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let meetingLink = props.meetingLink {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 1, height: 24)

                Menu {
                    Button {
                        props.onOpenMeeting()
                    } label: {
                        Label("Open meeting", systemImage: meetingLink.icon)
                    }
                    Button {
                        props.onOpenInCalendar()
                    } label: {
                        Label("Open calendar", systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.1))
        .clipShape(Capsule())
    }
}
