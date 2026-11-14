//
//  MeetingLinkTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `AlertService.extractMeetingLink`, which finds a conferencing link in an event.
struct MeetingLinkTests {
    /// One sample link per supported service, paired with the service name it must report.
    nonisolated static let supported: [(link: String, service: String)] = [
        ("https://meet.google.com/abc-defg-hij", "Google Meet"),
        ("https://us02web.zoom.us/j/123456789?pwd=abc", "Zoom"),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=x", "Teams"),
        ("https://acme.webex.com/meet/jane", "Webex"),
        ("https://global.gotomeeting.com/join/123456789", "GoTo Meeting"),
        ("https://acme.slack.com/huddle/T123/C456", "Slack Huddle"),
    ]

    /// Checks that each supported service is recognised in the location field and reported
    /// with the right name and unchanged URL, so the alert shows the correct Join button.
    @Test(arguments: supported)
    func detectsSupportedService(link: String, service: String) {
        let event = makeEvent(location: link)
        let found = AlertService.extractMeetingLink(from: event)
        #expect(found?.serviceName == service)
        #expect(found?.url.absoluteString == link)
    }

    /// Checks that ordinary links and plain text give no meeting link, so events without a
    /// call do not get a Join button.
    @Test(arguments: [
        "https://example.com/j/123456789",
        "https://www.google.com/meet",
        "http://meet.google.com/abc-defg-hij",
        "Conference room 4",
        "",
    ])
    func ignoresNonMeetingText(text: String) {
        #expect(AlertService.extractMeetingLink(from: makeEvent(location: text)) == nil)
        #expect(AlertService.extractMeetingLink(from: makeEvent(notes: text)) == nil)
    }

    /// Checks that an event with no url, location or notes gives nil.
    @Test
    func emptyEventHasNoLink() {
        #expect(AlertService.extractMeetingLink(from: makeEvent()) == nil)
    }

    /// Checks the field order url, then location, then notes, because the url field is the
    /// most deliberate place to put a link and notes the least.
    @Test
    func fieldPrecedence() {
        let zoom = "https://us02web.zoom.us/j/111111111"
        let meet = "https://meet.google.com/aaa-bbbb-ccc"
        let teams = "https://teams.microsoft.com/l/meetup-join/abc"

        let all = makeEvent(url: URL(string: zoom), location: meet, notes: teams)
        #expect(AlertService.extractMeetingLink(from: all)?.serviceName == "Zoom")

        let locationAndNotes = makeEvent(location: meet, notes: teams)
        #expect(AlertService.extractMeetingLink(from: locationAndNotes)?.serviceName == "Google Meet")

        let notesOnly = makeEvent(notes: teams)
        #expect(AlertService.extractMeetingLink(from: notesOnly)?.serviceName == "Teams")
    }

    /// Checks that a field without a link is skipped so a later field can still match.
    @Test
    func fallsThroughEmptyFields() {
        let event = makeEvent(
            url: URL(string: "https://example.com/agenda"),
            location: "Room 2",
            notes: "Join: https://meet.google.com/abc-defg-hij"
        )
        #expect(AlertService.extractMeetingLink(from: event)?.serviceName == "Google Meet")
    }

    /// Checks that a link inside HTML-ish notes is extracted without the surrounding markup,
    /// since calendar invites often wrap links in anchor tags.
    @Test
    func extractsLinkFromHTMLNotes() {
        let notes = """
        <p>Hello,</p><a href="https://meet.google.com/abc-defg-hij">Join the call</a><br>See you
        """
        let found = AlertService.extractMeetingLink(from: makeEvent(notes: notes))
        #expect(found?.url.absoluteString == "https://meet.google.com/abc-defg-hij")

        let plain = "Agenda below\nhttps://us02web.zoom.us/j/222222222?pwd=xyz<br>Thanks"
        let zoom = AlertService.extractMeetingLink(from: makeEvent(notes: plain))
        #expect(zoom?.url.absoluteString == "https://us02web.zoom.us/j/222222222?pwd=xyz")
    }
}
