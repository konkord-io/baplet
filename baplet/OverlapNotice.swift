//
//  OverlapNotice.swift
//  baplet
//

import SwiftUI

/// The warning in an alert that other meetings overlap this one: a heading, what happens to
/// them if the user joins this meeting, and up to `maxRows` of them with calendar colour,
/// title and time, then "+N more". Shown by the popup and every full-screen style; renders
/// nothing when there are no overlapping meetings.
struct OverlapNotice: View {
    let meetings: [OverlappingMeeting]

    /// True on the full-screen styles' dark backgrounds, where text is drawn in white.
    var onDarkBackground = false

    /// Most meetings listed by name; the rest are counted.
    static let maxRows = 3

    var body: some View {
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(heading, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("If you join this one, they alert when it ends.")
                    .font(.caption)
                    .foregroundStyle(secondary)
                ForEach(meetings.prefix(Self.maxRows)) { meeting in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(meeting.calendarColor.map { Color(cgColor: $0) } ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(meeting.title)
                            .lineLimit(1)
                        Text(meeting.timeRange)
                            .foregroundStyle(secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(primary)
                }
                if meetings.count > Self.maxRows {
                    Text("+\(meetings.count - Self.maxRows) more")
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// "Overlaps with 1 other meeting" or "… N other meetings".
    private var heading: String {
        meetings.count == 1 ? "Overlaps with 1 other meeting" : "Overlaps with \(meetings.count) other meetings"
    }

    /// Text colour of the meeting titles for the background the notice sits on.
    private var primary: Color {
        onDarkBackground ? .white.opacity(0.85) : .primary
    }

    /// Colour of the explanation and times for the background the notice sits on.
    private var secondary: Color {
        onDarkBackground ? .white.opacity(0.55) : .secondary
    }
}
