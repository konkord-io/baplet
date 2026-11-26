//
//  GlassmorphicAlertView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import SwiftUI

/// Full-screen alert with a frosted glass card centered on a dark backdrop.
/// Features gradient accent buttons, soft shadows, and a spring entrance animation.
struct GlassmorphicAlertView: View {
    let props: AlertProps

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Image("goldfish")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)

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
                OverlapNotice(meetings: props.overlapping, onDarkBackground: true)
            }

            HStack(spacing: 16) {
                snoozeButton
                dismissButton
                openButton
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

    /// Snooze split button: click snoozes for the default time, dropdown arrow shows all durations.
    private var snoozeButton: some View {
        HStack(spacing: 0) {
            Button { props.onSnooze(AlertProps.defaultSnoozeMinutes) } label: {
                Text("Snooze \(AlertProps.defaultSnoozeMinutes)m")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 20)

            Menu {
                ForEach(AlertProps.snoozeDurations, id: \.self) { minutes in
                    Button("\(minutes) min") { props.onSnooze(minutes) }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Dismiss button: turns off the alarm for this event.
    private var dismissButton: some View {
        Button { props.onDismiss() } label: {
            Text("Dismiss")
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Open split button: a click joins the meeting (or opens Calendar when there is no link);
    /// with a meeting link, the dropdown offers "Open meeting" and "Open calendar".
    /// Opening in any way stops the alarm.
    private var openButton: some View {
        HStack(spacing: 0) {
            Button { props.openDefault() } label: {
                Text("Open")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let meetingLink = props.meetingLink {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 1, height: 20)

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
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
