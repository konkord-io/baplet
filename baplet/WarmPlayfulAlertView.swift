//
//  WarmPlayfulAlertView.swift
//  baplet
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
            Image("baplet")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

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
                openButton
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

    /// Snooze split button: click snoozes for 5 min, dropdown arrow shows all durations.
    private var snoozeButton: some View {
        HStack(spacing: 0) {
            Button { props.onSnooze(5) } label: {
                Text("Snooze 5m")
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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

    /// Dismiss button: turns off the alarm for this event.
    private var dismissButton: some View {
        Button { props.onDismiss() } label: {
            Text("Dismiss")
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Open split button: a click joins the meeting (or opens Calendar when there is no link);
    /// with a meeting link, the dropdown offers "Open meeting" and "Open calendar".
    /// Opening in any way stops the alarm.
    private var openButton: some View {
        HStack(spacing: 0) {
            Button { props.openDefault() } label: {
                Text("Open")
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 20)
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
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
