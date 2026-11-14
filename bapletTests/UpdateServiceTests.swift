//
//  UpdateServiceTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for the pure parts of the updater: version comparison, release decoding, digest
/// parsing, the in-place install decision and the automatic-check schedule.
struct UpdateServiceTests {
    /// A trimmed copy of GitHub's `releases/latest` response for v0.2.0, with the fixed-name
    /// and the versioned DMG assets.
    static let releaseJSON = """
        {
          "url": "https://api.github.com/repos/konkord-io/baplet/releases/1",
          "html_url": "https://github.com/konkord-io/baplet/releases/tag/v0.2.0",
          "tag_name": "v0.2.0",
          "name": "Baplet 0.2.0",
          "draft": false,
          "prerelease": false,
          "body": "## What's new\\n\\n- In-app updates",
          "assets": [
            {
              "name": "Baplet-0.2.0.dmg",
              "size": 1945582,
              "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
              "browser_download_url": "https://github.com/konkord-io/baplet/releases/download/v0.2.0/Baplet-0.2.0.dmg"
            },
            {
              "name": "Baplet.dmg",
              "size": 1945583,
              "digest": "sha256:D2AC3FDD67D40CDF1B47E552159030BC15D8B1D89B6B7D95DBBE0EAF59FD1198",
              "browser_download_url": "https://github.com/konkord-io/baplet/releases/download/v0.2.0/Baplet.dmg"
            }
          ]
        }
        """

    /// Checks parsing with and without the leading `v`, suffixes, and rejected strings.
    @Test(arguments: [
        ("v0.2.0", [0, 2, 0]),
        ("0.2.0", [0, 2, 0]),
        ("V1.10", [1, 10]),
        ("2", [2]),
        ("1.2.3-beta.1", [1, 2, 3]),
        (" 1.0.0 ", [1, 0, 0]),
    ])
    func parsesVersions(input: String, components: [Int]) {
        #expect(AppVersion(input)?.components == components)
    }

    /// Checks that strings that aren't plain dotted numbers don't parse.
    @Test(arguments: ["", "v", "latest", "1..2", "1.x.0", "1.-2", "1.2."])
    func rejectsInvalidVersions(input: String) {
        #expect(AppVersion(input) == nil)
    }

    /// Checks ordering is numeric per component, ignores the `v` and pads shorter versions.
    @Test(arguments: [
        ("0.1.0", "0.2.0"),
        ("v0.1.0", "0.1.1"),
        ("0.9.0", "0.10.0"),
        ("1.2", "1.2.1"),
        ("1.9.9", "v2"),
        ("0.1.0", "1.0"),
    ])
    func olderIsLess(older: String, newer: String) throws {
        let old = try #require(AppVersion(older))
        let new = try #require(AppVersion(newer))
        #expect(old < new)
        #expect(!(new < old))
        #expect(old != new)
    }

    /// Checks versions of different lengths or prefixes that mean the same are equal.
    @Test(arguments: [("1.0", "1.0.0"), ("v0.1.0", "0.1"), ("2", "2.0.0")])
    func equalVersions(lhs: String, rhs: String) throws {
        let left = try #require(AppVersion(lhs))
        let right = try #require(AppVersion(rhs))
        #expect(left == right)
        #expect(!(left < right) && !(right < left))
    }

    /// Checks the fixture decodes and that the fixed-name `Baplet.dmg` asset is chosen.
    @Test
    func decodesRelease() throws {
        let release = try UpdateRelease.decode(from: Data(Self.releaseJSON.utf8))
        #expect(release.version == AppVersion("0.2.0"))
        #expect(release.title == "Baplet 0.2.0")
        #expect(release.notes == "## What's new\n\n- In-app updates")
        #expect(release.pageURL.absoluteString == "https://github.com/konkord-io/baplet/releases/tag/v0.2.0")
        #expect(release.dmgURL?.absoluteString == "https://github.com/konkord-io/baplet/releases/download/v0.2.0/Baplet.dmg")
        #expect(release.dmgSize == 1945583)
        #expect(release.sha256 == "d2ac3fdd67d40cdf1b47e552159030bc15d8b1d89b6b7d95dbbe0eaf59fd1198")
        #expect(release.manualDownloadURL == release.dmgURL)
    }

    /// Checks a release without `Baplet.dmg` decodes with no DMG and falls back to its page.
    @Test
    func decodesReleaseWithoutDMG() throws {
        let json = """
            {"tag_name": "v0.3.0", "name": null, "body": null,
             "html_url": "https://github.com/konkord-io/baplet/releases/tag/v0.3.0", "assets": []}
            """
        let release = try UpdateRelease.decode(from: Data(json.utf8))
        #expect(release.version == AppVersion("0.3.0"))
        #expect(release.title == "Baplet 0.3.0")
        #expect(release.notes.isEmpty)
        #expect(release.dmgURL == nil)
        #expect(release.sha256 == nil)
        #expect(release.manualDownloadURL == release.pageURL)
    }

    /// Checks unreadable JSON and a non-version tag throw readable errors.
    @Test
    func rejectsBadResponses() {
        #expect(throws: UpdateError.unreadableResponse) {
            try UpdateRelease.decode(from: Data("{\"message\": \"Not Found\"}".utf8))
        }
        let badTag = """
            {"tag_name": "nightly", "html_url": "https://example.com", "assets": []}
            """
        #expect(throws: UpdateError.invalidVersion("nightly")) {
            try UpdateRelease.decode(from: Data(badTag.utf8))
        }
    }

    /// Checks digest parsing accepts `sha256:<64 hex>` in any case and rejects the rest.
    @Test
    func parsesDigests() {
        let hex = String(repeating: "ab", count: 32)
        #expect(ReleaseDigest.sha256Hex(from: "sha256:\(hex)") == hex)
        #expect(ReleaseDigest.sha256Hex(from: "SHA256:\(hex.uppercased())") == hex)
        #expect(ReleaseDigest.sha256Hex(from: nil) == nil)
        #expect(ReleaseDigest.sha256Hex(from: hex) == nil)
        #expect(ReleaseDigest.sha256Hex(from: "sha512:\(hex)") == nil)
        #expect(ReleaseDigest.sha256Hex(from: "sha256:\(hex.dropLast())") == nil)
        #expect(ReleaseDigest.sha256Hex(from: "sha256:\(hex.dropLast())g") == nil)
    }

    /// Checks the in-place install decision for normal, translocated, mounted, unwritable
    /// and Debug-build cases.
    @Test
    func installBlockers() {
        #expect(InstallBlocker.check(appPath: "/Applications/Baplet.app", isParentWritable: true, isDebugBuild: false) == nil)
        #expect(InstallBlocker.check(appPath: "/Users/me/Applications/Baplet.app", isParentWritable: true, isDebugBuild: false) == nil)
        #expect(InstallBlocker.check(
            appPath: "/private/var/folders/xy/abc/T/AppTranslocation/1234-5678/d/Baplet.app",
            isParentWritable: false,
            isDebugBuild: false
        ) == .translocated)
        #expect(InstallBlocker.check(appPath: "/Volumes/Baplet 0.1.0/Baplet.app", isParentWritable: false, isDebugBuild: false) == .mountedVolume)
        #expect(InstallBlocker.check(appPath: "/Applications/Baplet.app", isParentWritable: false, isDebugBuild: false) == .folderNotWritable("/Applications"))
        #expect(InstallBlocker.check(appPath: "/Applications/Baplet.app", isParentWritable: true, isDebugBuild: true) == .debugBuild)
    }

    /// Checks the downloaded bundle must be Baplet at exactly the release's version.
    @Test
    func checksStagedBundle() throws {
        let version = try #require(AppVersion("0.2.0"))
        let good: [String: Any] = ["CFBundleIdentifier": "io.konkord.baplet", "CFBundleShortVersionString": "0.2.0"]
        #expect(throws: Never.self) { try UpdateInstaller.checkBundle(info: good, expectedVersion: version) }
        let foreign: [String: Any] = ["CFBundleIdentifier": "com.example.other", "CFBundleShortVersionString": "0.2.0"]
        #expect(throws: UpdateError.self) { try UpdateInstaller.checkBundle(info: foreign, expectedVersion: version) }
        let older: [String: Any] = ["CFBundleIdentifier": "io.konkord.baplet", "CFBundleShortVersionString": "0.1.0"]
        #expect(throws: UpdateError.self) { try UpdateInstaller.checkBundle(info: older, expectedVersion: version) }
        #expect(throws: UpdateError.self) { try UpdateInstaller.checkBundle(info: nil, expectedVersion: version) }
    }

    /// Checks the automatic check runs only when enabled and the last check is over a day old.
    @Test
    func automaticCheckSchedule() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = UpdateService.automaticCheckInterval
        #expect(UpdateService.isAutomaticCheckDue(enabled: true, lastCheck: nil, now: now))
        #expect(UpdateService.isAutomaticCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-day - 1), now: now))
        #expect(!UpdateService.isAutomaticCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-day + 60), now: now))
        #expect(!UpdateService.isAutomaticCheckDue(enabled: false, lastCheck: nil, now: now))
    }

    /// Checks headings, bullets, numbered items, code fences and joined paragraphs.
    @Test
    func parsesReleaseNotes() {
        let markdown = "## Installing\r\n\r\n1. Open the DMG\r\n- **Bold** item\r\n\r\nFirst line\r\nsecond line\r\n```\r\nxattr -dr x\r\n```"
        #expect(ReleaseNotesBlock.parse(markdown) == [
            .heading("Installing"),
            .listItem(marker: "1.", text: "Open the DMG"),
            .listItem(marker: "•", text: "**Bold** item"),
            .paragraph("First line second line"),
            .code("xattr -dr x"),
        ])
    }
}
