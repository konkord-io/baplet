//
//  BrowserService.swift
//  baplet
//

import AppKit

/// An installed app that can open web links, as offered in the Meetings settings.
struct Browser: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let appURL: URL

    /// Identity for `ForEach` and pickers: the bundle identifier.
    var id: String { bundleID }

    /// How this browser stores profiles and is told to open one, or nil when Baplet cannot
    /// select a profile in it (Safari, Arc and other browsers without a launch flag).
    var profileFamily: BrowserService.ProfileFamily? {
        BrowserService.profileFamily(forBundleID: bundleID)
    }
}

/// A browser profile the user can open meetings in.
/// `id` is what the browser's launch flag needs (Chromium: the profile folder such as
/// "Profile 1"; Firefox: the profile name); `name` is what the user sees.
struct BrowserProfile: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Finds installed browsers and their profiles, and opens meeting links in the browser and
/// profile chosen in Settings. Profile selection relies on reading the browsers' own profile
/// files and passing launch arguments, both of which require Baplet to run unsandboxed.
enum BrowserService {
    /// The profile mechanisms Baplet understands.
    enum ProfileFamily {
        /// Chromium-based browser: profiles listed in a `Local State` JSON file under the given
        /// Application Support folder, opened with `--profile-directory=<folder>`.
        case chromium(supportFolder: String)
        /// Firefox: profiles listed in `profiles.ini`, opened with `-P <name>`.
        case firefox
    }

    /// Application Support folders (relative to `~/Library/Application Support`) of the
    /// Chromium browsers whose profiles Baplet can list, keyed by bundle identifier.
    private static let chromiumSupportFolders: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    /// Bundle identifiers of Firefox builds that share the standard `profiles.ini`.
    private static let firefoxBundleIDs: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
    ]

    /// The user's real `~/Library/Application Support` folder.
    private static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
    }

    /// Returns how profiles work for the given browser, or nil if Baplet can't select one.
    static func profileFamily(forBundleID bundleID: String) -> ProfileFamily? {
        if let folder = chromiumSupportFolders[bundleID] {
            return .chromium(supportFolder: folder)
        }
        if firefoxBundleIDs.contains(bundleID) {
            return .firefox
        }
        return nil
    }

    /// Lists every installed app registered to open `https` links, one entry per bundle
    /// identifier, sorted by name. Baplet itself is excluded.
    static func installedBrowsers() -> [Browser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        var seen = Set<String>()
        var browsers: [Browser] = []
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  seen.insert(bundleID).inserted else { continue }
            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            browsers.append(Browser(bundleID: bundleID, name: name, appURL: appURL))
        }
        return browsers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lists the profiles of the given browser, in the browser's own order where it has one.
    /// Returns an empty list when the browser has no profile support or its file is unreadable.
    static func profiles(for browser: Browser) -> [BrowserProfile] {
        switch browser.profileFamily {
        case .chromium(let folder):
            return chromiumProfiles(supportFolder: folder)
        case .firefox:
            return firefoxProfiles()
        case nil:
            return []
        }
    }

    /// Reads `profile.info_cache` from a Chromium `Local State` file. Profiles are ordered by
    /// `profile.profiles_order` when present, otherwise alphabetically by display name.
    private static func chromiumProfiles(supportFolder: String) -> [BrowserProfile] {
        let file = applicationSupport.appendingPathComponent(supportFolder).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return parseChromiumProfiles(localState: data)
    }

    /// Parses the contents of a Chromium `Local State` file. Split out from the file reading
    /// so it can be tested with fixed data. Returns an empty list for malformed JSON.
    static func parseChromiumProfiles(localState data: Data) -> [BrowserProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }

        let profiles = cache.compactMap { folder, value -> BrowserProfile? in
            let info = value as? [String: Any]
            let name = (info?["name"] as? String) ?? folder
            return BrowserProfile(id: folder, name: name)
        }
        if let order = profile["profiles_order"] as? [String] {
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return profiles.sorted { (rank[$0.id] ?? .max, $0.name) < (rank[$1.id] ?? .max, $1.name) }
        }
        return profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads the `Name=` entry of every `[Profile…]` section in Firefox's `profiles.ini`,
    /// in file order.
    private static func firefoxProfiles() -> [BrowserProfile] {
        let file = applicationSupport.appendingPathComponent("Firefox/profiles.ini")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return parseFirefoxProfiles(profilesIni: text)
    }

    /// Parses the contents of Firefox's `profiles.ini`. Split out from the file reading so it
    /// can be tested with fixed text.
    static func parseFirefoxProfiles(profilesIni text: String) -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []
        var inProfileSection = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inProfileSection = line.hasPrefix("[Profile")
            } else if inProfileSection, line.hasPrefix("Name=") {
                let name = String(line.dropFirst("Name=".count))
                profiles.append(BrowserProfile(id: name, name: name))
            }
        }
        return profiles
    }

    /// Opens a meeting link using the browser and profile chosen in Settings.
    /// Falls back to the system default browser when none is chosen or the chosen one is no
    /// longer installed, and to the browser's default profile when no profile is chosen.
    /// The browser always comes to the front (see `FocusHandoff`).
    static func openMeeting(_ url: URL, settings: SettingsStore) {
        guard let bundleID = settings.meetingBrowserID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            FocusHandoff.prepare(forAppOpening: url)
            NSWorkspace.shared.open(url)
            return
        }

        FocusHandoff.prepare(forBundleID: bundleID)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let profileID = settings.meetingBrowserProfileID,
           let family = profileFamily(forBundleID: bundleID) {
            configuration.arguments = launchArguments(for: family, profileID: profileID, url: url)
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            FocusHandoff.bringToFront(bundleID: bundleID)
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
    }

    /// Command-line arguments that make the browser open `url` in the given profile.
    /// A second instance launched this way hands the request to the already-running browser.
    static func launchArguments(for family: ProfileFamily, profileID: String, url: URL) -> [String] {
        switch family {
        case .chromium:
            ["--profile-directory=\(profileID)", url.absoluteString]
        case .firefox:
            ["-P", profileID, url.absoluteString]
        }
    }
}

/// Hands focus to the app Baplet opens something in. Since macOS 14 an app may only bring
/// another app to the front if it is active itself and explicitly yields to it. Baplet's
/// alert and Today panels never make Baplet active, so without this the browser or Calendar
/// would open behind whatever the user was doing.
enum FocusHandoff {
    /// Activates Baplet (allowed, since the user just clicked or typed in its panel) and yields
    /// activation to the given app, so the app can come forward when it opens.
    static func prepare(forBundleID bundleID: String) {
        NSApp.activate()
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
    }

    /// Same as `prepare(forBundleID:)` for whichever app macOS will use to open `url`.
    static func prepare(forAppOpening url: URL) {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return }
        prepare(forBundleID: bundleID)
    }

    /// Brings the already-running copy of an app forward after a short delay. Used for browser
    /// profile launches, where a second instance passes the link to the running browser and
    /// exits, so the running browser never gets the activation request itself.
    static func bringToFront(bundleID: String, after delay: Duration = .milliseconds(500)) {
        Task {
            try? await Task.sleep(for: delay)
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
        }
    }
}
