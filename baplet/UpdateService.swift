//
//  UpdateService.swift
//  baplet
//

import AppKit
import Foundation

/// A release version such as `0.2.0`, compared numerically component by component.
/// Missing trailing components count as zero, so `1.2` equals `1.2.0`.
nonisolated struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    /// The numeric components, most significant first (major, minor, patch, …).
    let components: [Int]

    /// Parses a version string, accepting a leading `v` (as in Git tags like `v0.2.0`) and
    /// ignoring any pre-release or build suffix after `-` or `+`.
    /// Returns nil when a component isn't a plain non-negative number, so a malformed tag is
    /// never mistaken for a newer release.
    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" || text.first == "V" {
            text = text.dropFirst()
        }
        if let suffixStart = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = text[..<suffixStart]
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in
            part.allSatisfy(\.isASCII) ? Int(part) : nil
        }
        guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        components = numbers
    }

    /// The version as dotted numbers without the `v` prefix, as shown to users.
    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// Both versions' components padded with zeros to the same length, so versions of
    /// different lengths compare by value.
    private static func padded(_ lhs: AppVersion, _ rhs: AppVersion) -> ([Int], [Int]) {
        let length = max(lhs.components.count, rhs.components.count)
        let pad = { (components: [Int]) in components + Array(repeating: 0, count: length - components.count) }
        return (pad(lhs.components), pad(rhs.components))
    }

    /// Equal when every component matches after zero padding (`1.0` == `1.0.0`).
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (left, right) = padded(lhs, rhs)
        return left == right
    }

    /// Orders versions by their first differing component after zero padding.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (left, right) = padded(lhs, rhs)
        return left.lexicographicallyPrecedes(right)
    }
}

/// The parts of GitHub's "latest release" API response that the updater uses.
nonisolated struct GitHubRelease: Decodable, Sendable {
    /// One file attached to a release.
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int
        /// GitHub's checksum of the file, in the form `sha256:<hex>`; absent on old releases.
        let digest: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

/// Reads GitHub's asset digest format.
nonisolated enum ReleaseDigest {
    /// Returns the lowercase hex SHA-256 from a digest like `sha256:<64 hex chars>`, or nil
    /// when the digest is missing, uses another algorithm or is malformed, so the installer
    /// can refuse instead of trusting an unverifiable download.
    static func sha256Hex(from digest: String?) -> String? {
        guard let digest else { return nil }
        let prefix = "sha256:"
        guard digest.lowercased().hasPrefix(prefix) else { return nil }
        let hex = digest.dropFirst(prefix.count).lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return String(hex)
    }
}

/// A newer (or the latest) published release, reduced to what the update UI and installer need.
nonisolated struct UpdateRelease: Equatable, Sendable {
    /// Name of the release asset the updater downloads; `release.yml` uploads it under this
    /// fixed name next to the versioned DMG.
    static let dmgAssetName = "Baplet.dmg"

    let version: AppVersion
    let title: String
    let notes: String
    let pageURL: URL
    let dmgURL: URL?
    let dmgSize: Int?
    let sha256: String?

    /// Builds the release from GitHub's response, picking the asset named exactly
    /// `Baplet.dmg`. Throws when the tag isn't a version, since nothing can be compared then.
    init(_ release: GitHubRelease) throws {
        guard let version = AppVersion(release.tagName) else {
            throw UpdateError.invalidVersion(release.tagName)
        }
        let dmg = release.assets.first { $0.name == Self.dmgAssetName }
        self.version = version
        self.title = release.name ?? "Baplet \(version)"
        self.notes = release.body ?? ""
        self.pageURL = release.htmlURL
        self.dmgURL = dmg?.browserDownloadURL
        self.dmgSize = dmg?.size
        self.sha256 = ReleaseDigest.sha256Hex(from: dmg?.digest)
    }

    /// Decodes GitHub's "latest release" JSON into an `UpdateRelease`.
    /// Split out from the network call so the decoding can be tested with a fixture.
    static func decode(from data: Data) throws -> UpdateRelease {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.unreadableResponse
        }
        return try UpdateRelease(release)
    }

    /// Where Download Manually goes: the DMG itself, or the release page when the release
    /// has no `Baplet.dmg`.
    var manualDownloadURL: URL {
        dmgURL ?? pageURL
    }
}

/// Why Baplet can't replace itself in place, with the explanation shown in the update dialog.
nonisolated enum InstallBlocker: Equatable, Sendable {
    case debugBuild
    case translocated
    case mountedVolume
    case folderNotWritable(String)

    /// Decides whether the app at `appPath` may be replaced in place. Pure, so every case
    /// can be tested without moving real bundles.
    /// Debug builds are refused so a development build is never swapped for a release; a
    /// translocated app runs from a random read-only copy, and one under `/Volumes` most
    /// likely runs straight from the DMG, so replacing either would not update the real
    /// install; an unwritable folder would make the swap fail halfway.
    static func check(appPath: String, isParentWritable: Bool, isDebugBuild: Bool) -> InstallBlocker? {
        if isDebugBuild {
            return .debugBuild
        }
        if appPath.contains("/AppTranslocation/") {
            return .translocated
        }
        if appPath.hasPrefix("/Volumes/") {
            return .mountedVolume
        }
        if !isParentWritable {
            let folder = (appPath as NSString).deletingLastPathComponent
            return .folderNotWritable(folder)
        }
        return nil
    }

    /// Checks the running app's own bundle with `check(appPath:isParentWritable:isDebugBuild:)`.
    static func forRunningApp() -> InstallBlocker? {
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent().path
        return check(
            appPath: appURL.path,
            isParentWritable: FileManager.default.isWritableFile(atPath: parent),
            isDebugBuild: UpdateService.isDebugBuild
        )
    }

    /// The sentence shown in the update dialog explaining why Install & Restart is off.
    var explanation: String {
        switch self {
        case .debugBuild:
            "This is a development build, so it can't update itself. Download the DMG to install the release."
        case .translocated:
            "macOS is running Baplet from a temporary location because it hasn't been moved out of its download folder. Download the DMG and drag Baplet to Applications."
        case .mountedVolume:
            "Baplet is running from a disk image or external volume. Download the DMG and drag Baplet to Applications."
        case .folderNotWritable(let folder):
            "Baplet can't write to \(folder), so it can't replace itself. Download the DMG and install it by hand."
        }
    }
}

/// Errors from checking for and installing updates, each with a message the UI can show.
nonisolated enum UpdateError: LocalizedError, Equatable {
    case network(String)
    case httpStatus(Int)
    case noRelease
    case unreadableResponse
    case invalidVersion(String)
    case missingDigest
    case checksumMismatch
    case diskImage(String)
    case unexpectedBundle(String)
    case staging(String)

    /// A readable sentence for the status line or update dialog.
    var errorDescription: String? {
        switch self {
        case .network(let message):
            "Couldn't reach GitHub: \(message)"
        case .httpStatus(403), .httpStatus(429):
            "GitHub is limiting requests right now. Try again later."
        case .httpStatus(let code):
            "GitHub answered with an error (HTTP \(code))."
        case .noRelease:
            "No published release was found."
        case .unreadableResponse:
            "GitHub's answer couldn't be read."
        case .invalidVersion(let tag):
            "The latest release has an unexpected version (\(tag))."
        case .missingDigest:
            "This release has no checksum, so Baplet can't verify the download. Download it manually instead."
        case .checksumMismatch:
            "The download doesn't match the release's checksum, so it wasn't installed. Download it manually instead."
        case .diskImage(let message):
            "The disk image couldn't be opened: \(message)"
        case .unexpectedBundle(let message):
            "The disk image doesn't contain the expected app: \(message)"
        case .staging(let message):
            "The update couldn't be prepared: \(message)"
        }
    }
}

/// Checks GitHub Releases for a newer Baplet, keeps the result for the menu row, Settings and
/// the update dialog, runs the automatic daily check, and drives Install & Restart.
@Observable
final class UpdateService {
    /// What the last update check found, shown as the status line in Settings → About.
    enum CheckStatus: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(String)
        case failed(String)

        /// The status line text in Settings → About; nil while nothing has been checked.
        var message: String? {
            switch self {
            case .idle: nil
            case .checking: "Checking…"
            case .upToDate(let version): "Baplet is up to date (\(version))"
            case .available(let version): "Baplet \(version) is available"
            case .failed(let message): message
            }
        }
    }

    /// One step of Install & Restart, shown under the progress bar.
    nonisolated enum InstallStep: Equatable, Sendable {
        case downloading(Double)
        case verifying
        case preparing
        case restarting

        /// The step's label in the update dialog.
        var label: String {
            switch self {
            case .downloading: "Downloading…"
            case .verifying: "Verifying download…"
            case .preparing: "Preparing the new version…"
            case .restarting: "Restarting Baplet…"
            }
        }

        /// Download progress from 0 to 1, or nil for steps without measurable progress.
        var fraction: Double? {
            if case .downloading(let fraction) = self { fraction } else { nil }
        }
    }

    /// Where Install & Restart stands.
    enum InstallStatus: Equatable {
        case idle
        case running(InstallStep)
        case failed(String)
    }

    /// GitHub's endpoint for the newest published (non-draft, non-prerelease) release.
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/konkord-io/baplet/releases/latest")!

    /// Minimum time between automatic checks.
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    /// How often the automatic-check loop wakes up to see whether a check is due. Shorter
    /// than a day so a Mac that slept through the due time still checks soon after waking.
    private static let automaticWakeInterval: Duration = .seconds(60 * 60)

    /// True in Debug builds, which skip automatic checks and never install in place.
    nonisolated static let isDebugBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    private(set) var checkStatus: CheckStatus = .idle
    private(set) var installStatus: InstallStatus = .idle

    /// The newer release found by the last successful check; nil when up to date or unknown.
    private(set) var availableUpdate: UpdateRelease?

    /// The running app's version string (`CFBundleShortVersionString`).
    let currentVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private var automaticChecks: Task<Void, Never>?

    /// The running app's version, or 0 when the Info.plist value can't be parsed, so any
    /// release then counts as newer rather than the check failing.
    var currentVersion: AppVersion {
        AppVersion(currentVersionString) ?? AppVersion("0")!
    }

    /// True while Install & Restart is working, so the dialog disables its buttons.
    var isInstalling: Bool {
        if case .running = installStatus { true } else { false }
    }

    /// Why the available update can't be installed in place, or nil when it can.
    /// Covers the app's location and build as well as releases without a DMG or checksum.
    var installRefusal: String? {
        if let blocker = InstallBlocker.forRunningApp() {
            return blocker.explanation
        }
        guard let update = availableUpdate else { return nil }
        if update.dmgURL == nil {
            return "This release has no Baplet.dmg to install. Open the release page to download it."
        }
        if update.sha256 == nil {
            return UpdateError.missingDigest.errorDescription
        }
        return nil
    }

    /// Fetches the latest release and updates `checkStatus` and `availableUpdate`.
    /// Records the time of every successful check in `settings.lastUpdateCheck`, which the
    /// automatic check uses to stay at one check a day. Returns true when a newer version
    /// is available. Errors end up in `checkStatus` as text, never thrown.
    @discardableResult
    func checkNow(settings: SettingsStore) async -> Bool {
        guard checkStatus != .checking else { return false }
        checkStatus = .checking
        do {
            let latest = try await Self.fetchLatestRelease()
            settings.lastUpdateCheck = .now
            if latest.version > currentVersion {
                availableUpdate = latest
                checkStatus = .available(latest.version.description)
                return true
            }
            availableUpdate = nil
            checkStatus = .upToDate(currentVersionString)
            return false
        } catch {
            checkStatus = .failed(error.localizedDescription)
            return false
        }
    }

    /// Loads GitHub's latest release without authentication and turns transport, HTTP and
    /// decoding problems into `UpdateError`s with readable messages.
    private static func fetchLatestRelease() async throws -> UpdateRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw UpdateError.noRelease
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.httpStatus(http.statusCode)
            }
        }
        return try UpdateRelease.decode(from: data)
    }

    /// Whether an automatic check should run now: only when the user left automatic checks
    /// on and the last check is more than `automaticCheckInterval` ago (or never happened).
    static func isAutomaticCheckDue(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) > automaticCheckInterval
    }

    /// Starts the automatic check loop: checks right away if one is due, then wakes hourly
    /// and checks whenever the last check is over a day old. Called from app startup; a
    /// second call does nothing. Skipped in Debug builds so development runs don't hit
    /// GitHub's rate limit.
    func startAutomaticChecks(settings: SettingsStore) {
        guard !Self.isDebugBuild, automaticChecks == nil else { return }
        automaticChecks = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Self.isAutomaticCheckDue(enabled: settings.checkForUpdatesAutomatically, lastCheck: settings.lastUpdateCheck, now: .now) {
                    await self.checkNow(settings: settings)
                }
                try? await Task.sleep(for: Self.automaticWakeInterval)
            }
        }
    }

    /// Opens the DMG (or the release page) in the browser, the fallback whenever an
    /// in-place install isn't possible or has failed.
    func downloadManually() {
        guard let update = availableUpdate else { return }
        NSWorkspace.shared.open(update.manualDownloadURL)
    }

    /// Downloads, verifies and stages the available update, then hands the swap to a
    /// detached helper and quits so the helper can replace and relaunch the app.
    /// Any failure stops the flow, cleans up, and leaves a message in `installStatus`.
    func installAndRestart() async {
        guard !isInstalling, installRefusal == nil,
              let update = availableUpdate, let dmgURL = update.dmgURL, let sha256 = update.sha256 else { return }
        let appURL = Bundle.main.bundleURL
        installStatus = .running(.downloading(0))
        do {
            let staged = try await UpdateInstaller.prepare(
                dmgURL: dmgURL,
                expectedSize: update.dmgSize,
                sha256: sha256,
                version: update.version,
                replacing: appURL,
                progress: { step in
                    Task { @MainActor in self.advance(to: step) }
                }
            )
            installStatus = .running(.restarting)
            try UpdateInstaller.launchReplacement(of: appURL, with: staged, waitingFor: ProcessInfo.processInfo.processIdentifier)
            NSApp.terminate(nil)
        } catch {
            installStatus = .failed(error.localizedDescription)
        }
    }

    /// Moves the dialog's progress to `step`, ignoring download progress that arrives after
    /// the flow has already moved on or stopped.
    private func advance(to step: InstallStep) {
        guard case .running(let current) = installStatus else { return }
        if case .downloading = step, current.fraction == nil { return }
        installStatus = .running(step)
    }
}
