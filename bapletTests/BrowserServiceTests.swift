//
//  BrowserServiceTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `BrowserService` profile parsing, launch arguments and browser classification.
struct BrowserServiceTests {
    /// Encodes a JSON string as the Data a `Local State` file would hold.
    func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    /// Checks that `profiles_order` decides the order, and that profiles missing from it come
    /// last, so the list matches the browser's own profile picker.
    @Test
    func chromiumFollowsProfilesOrder() {
        let json = """
        {"profile": {
          "profiles_order": ["Profile 2", "Default"],
          "info_cache": {
            "Default": {"name": "Alpha"},
            "Profile 2": {"name": "Zed"},
            "Profile 3": {"name": "Extra"}
          }}}
        """
        let profiles = BrowserService.parseChromiumProfiles(localState: data(json))
        #expect(profiles.map(\.id) == ["Profile 2", "Default", "Profile 3"])
        #expect(profiles.map(\.name) == ["Zed", "Alpha", "Extra"])
    }

    /// Checks the alphabetical fallback by display name when there is no `profiles_order`.
    @Test
    func chromiumFallsBackToAlphabetical() {
        let json = """
        {"profile": {"info_cache": {
          "Default": {"name": "Work"},
          "Profile 1": {"name": "alpha"},
          "Profile 2": {"name": "Personal"}
        }}}
        """
        let profiles = BrowserService.parseChromiumProfiles(localState: data(json))
        #expect(profiles.map(\.name) == ["alpha", "Personal", "Work"])
    }

    /// Checks that a profile without a `name` is listed under its folder name.
    @Test
    func chromiumMissingNameUsesFolder() {
        let json = #"{"profile": {"info_cache": {"Profile 7": {}}}}"#
        let profiles = BrowserService.parseChromiumProfiles(localState: data(json))
        #expect(profiles == [BrowserProfile(id: "Profile 7", name: "Profile 7")])
    }

    /// Checks that broken or unexpected JSON gives an empty list instead of crashing.
    @Test(arguments: ["not json", "", "[]", "{}", #"{"profile": {}}"#])
    func chromiumMalformedGivesEmpty(json: String) {
        #expect(BrowserService.parseChromiumProfiles(localState: data(json)).isEmpty)
    }

    /// Checks that only `[Profile…]` sections contribute, in file order, and that `Name=`
    /// lines in `[Install…]` and `[General]` sections are ignored.
    @Test
    func firefoxIgnoresOtherSections() {
        let ini = """
        [General]
        StartWithLastProfile=1
        Name=NotAProfile

        [Install4F96D1932A9F858E]
        Default=Profiles/abc.default-release
        Name=AlsoNot

        [Profile1]
        Name=work
        IsRelative=1
        Path=Profiles/work

        [Profile0]
        Name=default-release
        Default=1
        """
        let profiles = BrowserService.parseFirefoxProfiles(profilesIni: ini)
        #expect(profiles.map(\.name) == ["work", "default-release"])
        #expect(profiles.map(\.id) == ["work", "default-release"])
    }

    /// Checks that an empty `profiles.ini` gives no profiles.
    @Test
    func firefoxEmptyGivesNoProfiles() {
        #expect(BrowserService.parseFirefoxProfiles(profilesIni: "").isEmpty)
    }

    /// Checks the Chromium launch flag and URL order, which the browser needs to pick the
    /// profile.
    @Test
    func chromiumLaunchArguments() throws {
        let url = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let args = BrowserService.launchArguments(
            for: .chromium(supportFolder: "Google/Chrome"), profileID: "Profile 1", url: url)
        #expect(args == ["--profile-directory=Profile 1", "https://meet.google.com/abc-defg-hij"])
    }

    /// Checks the Firefox `-P <name>` launch arguments.
    @Test
    func firefoxLaunchArguments() throws {
        let url = try #require(URL(string: "https://us02web.zoom.us/j/123"))
        let args = BrowserService.launchArguments(for: .firefox, profileID: "work", url: url)
        #expect(args == ["-P", "work", "https://us02web.zoom.us/j/123"])
    }

    /// Checks that known Chromium bundle IDs map to their Application Support folder.
    @Test(arguments: [
        ("com.google.Chrome", "Google/Chrome"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
    ])
    func chromiumFamily(bundleID: String, folder: String) {
        guard case .chromium(let found)? = BrowserService.profileFamily(forBundleID: bundleID) else {
            Issue.record("Expected a Chromium family for \(bundleID)")
            return
        }
        #expect(found == folder)
    }

    /// Checks that Firefox is recognised and that Safari has no profile support.
    @Test
    func firefoxAndSafariFamilies() {
        guard case .firefox? = BrowserService.profileFamily(forBundleID: "org.mozilla.firefox") else {
            Issue.record("Expected the Firefox family")
            return
        }
        #expect(BrowserService.profileFamily(forBundleID: "com.apple.Safari") == nil)
    }
}
