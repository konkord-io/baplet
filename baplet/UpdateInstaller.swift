//
//  UpdateInstaller.swift
//  baplet
//

import CryptoKit
import Darwin
import Foundation

/// A verified copy of the new Baplet.app, waiting next to the running app for the swap.
nonisolated struct StagedUpdate: Sendable {
    /// Temporary folder on the running app's volume; the helper deletes it when done.
    let directory: URL
    /// The new app bundle inside `directory`.
    let app: URL
}

/// The file and process work behind Install & Restart: download, checksum, mount, check,
/// stage and the detached helper that swaps the bundles after Baplet quits.
/// Runs off the main actor so hashing and `hdiutil` never block the UI.
nonisolated enum UpdateInstaller {
    /// The bundle identifier the downloaded app must have before it may replace this one.
    static let bundleIdentifier = "io.konkord.baplet"

    /// Name of the app bundle at the root of the release DMG.
    static let appName = "Baplet.app"

    /// Downloads the DMG to a fresh temporary folder, verifies its SHA-256, mounts it, checks
    /// the app inside and copies it to a staging folder on the running app's volume, so the
    /// final swap is a quick rename. The download folder is removed afterwards whatever
    /// happens; `progress` reports each step as it starts.
    @concurrent
    static func prepare(
        dmgURL: URL,
        expectedSize: Int?,
        sha256: String,
        version: AppVersion,
        replacing appURL: URL,
        progress: @escaping @Sendable (UpdateService.InstallStep) -> Void
    ) async throws -> StagedUpdate {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("Baplet-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let dmg = try await DMGDownload.run(
            from: dmgURL,
            to: work.appendingPathComponent("Baplet.dmg"),
            expectedSize: expectedSize,
            progress: { progress(.downloading($0)) }
        )

        progress(.verifying)
        guard try sha256Hex(of: dmg) == sha256.lowercased() else {
            throw UpdateError.checksumMismatch
        }

        progress(.preparing)
        return try stage(dmg: dmg, in: work, version: version, nextTo: appURL)
    }

    /// Hashes the file in 1 MB chunks, so the whole DMG never has to sit in memory.
    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the DMG read-only and hidden (no Finder window, no desktop icon), checks the
    /// app inside and copies it with `ditto` into a replacement folder on the volume of
    /// `appURL`, then detaches the image again, also when a step fails.
    private static func stage(dmg: URL, in work: URL, version: AppVersion, nextTo appURL: URL) throws -> StagedUpdate {
        let mountPoint = work.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        do {
            try runTool("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path])
        } catch {
            throw UpdateError.diskImage(error.localizedDescription)
        }
        defer { detach(mountPoint) }

        let source = mountPoint.appendingPathComponent(appName, isDirectory: true)
        let info = NSDictionary(contentsOf: source.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        try checkBundle(info: info, expectedVersion: version)

        let staging: URL
        do {
            staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        } catch {
            throw UpdateError.staging(error.localizedDescription)
        }
        let stagedApp = staging.appendingPathComponent(appName, isDirectory: true)
        do {
            try runTool("/usr/bin/ditto", [source.path, stagedApp.path])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw UpdateError.staging(error.localizedDescription)
        }
        return StagedUpdate(directory: staging, app: stagedApp)
    }

    /// Checks a bundle's Info.plist values: it must be Baplet (`bundleIdentifier`) at the
    /// version the release promised, so a mislabelled or foreign DMG is never installed.
    static func checkBundle(info: [String: Any]?, expectedVersion: AppVersion) throws {
        guard let info else {
            throw UpdateError.unexpectedBundle("\(appName) is missing.")
        }
        let identifier = info["CFBundleIdentifier"] as? String ?? "none"
        guard identifier == bundleIdentifier else {
            throw UpdateError.unexpectedBundle("its bundle identifier is \(identifier).")
        }
        let versionString = info["CFBundleShortVersionString"] as? String ?? "none"
        guard AppVersion(versionString) == expectedVersion else {
            throw UpdateError.unexpectedBundle("it is version \(versionString), not \(expectedVersion).")
        }
    }

    /// Unmounts the disk image, forcing it when a normal detach fails, so no hidden volume
    /// is left behind.
    private static func detach(_ mountPoint: URL) {
        if (try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])) == nil {
            try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
        }
    }

    /// Runs a command-line tool to completion, throwing its stderr output when it exits
    /// with a non-zero status. stderr is read to the end before waiting, so a chatty tool
    /// can't fill the pipe and stall.
    private static func runTool(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(message: message.isEmpty ? "\(path) failed with status \(process.terminationStatus)." : message)
        }
    }

    /// The shell helper that performs the swap once Baplet has quit. Arguments: the PID to
    /// wait for, the installed app, the staged new app, and the staging folder.
    /// It gives up after 30 s if Baplet doesn't quit, and moves the old app back if the new
    /// one can't be put in place, so a failed swap never leaves the user without Baplet.
    static let helperScript = """
        #!/bin/sh
        pid="$1"
        app="$2"
        new="$3"
        staging="$4"
        tries=0
        while /bin/kill -0 "$pid" 2>/dev/null; do
            tries=$((tries + 1))
            if [ "$tries" -gt 300 ]; then
                /bin/rm -rf "$staging"
                exit 1
            fi
            /bin/sleep 0.1
        done
        old="$staging/previous.app"
        if /bin/mv "$app" "$old"; then
            if /bin/mv "$new" "$app"; then
                /bin/rm -rf "$old"
            else
                /bin/mv "$old" "$app"
            fi
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$app" 2>/dev/null
        /usr/bin/open "$app"
        /bin/rm -rf "$staging"
        """

    /// Writes the helper script into the staging folder and starts it in its own session
    /// (`POSIX_SPAWN_SETSID`) with stdio on /dev/null, so it keeps running after Baplet
    /// terminates and isn't taken down with Baplet's process group.
    static func launchReplacement(of appURL: URL, with staged: StagedUpdate, waitingFor pid: Int32) throws {
        let script = staged.directory.appendingPathComponent("replace.sh")
        do {
            try helperScript.write(to: script, atomically: true, encoding: .utf8)
        } catch {
            throw UpdateError.staging(error.localizedDescription)
        }

        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var fileActions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        let arguments = ["/bin/sh", script.path, String(pid), appURL.path, staged.app.path, staged.directory.path]
        let cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { cArguments.forEach { free($0) } }

        var child: pid_t = 0
        let status = posix_spawn(&child, "/bin/sh", &fileActions, &attributes, cArguments, environ)
        guard status == 0 else {
            throw UpdateError.staging(String(cString: strerror(status)))
        }
    }

    /// A failed command-line tool, carrying its error output as the message.
    struct ToolError: LocalizedError {
        let message: String

        /// The tool's own error output, shown inside the update error.
        var errorDescription: String? { message }
    }
}

/// One DMG download with byte-level progress, using a delegate-based `URLSession` because
/// the async download API doesn't report progress. The file is moved into place inside the
/// delegate callback, before URLSession deletes its temporary copy.
nonisolated final class DMGDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int?
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var outcome: Result<URL, Error>?

    /// Keeps the target path, the size from the release (used when the server sends no
    /// length) and the progress callback.
    private init(destination: URL, expectedSize: Int?, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    /// Downloads `url` to `destination` and returns it, reporting progress from 0 to 1.
    /// The session's delegate queue is serial, so the callbacks never race each other.
    static func run(from url: URL, to destination: URL, expectedSize: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let download = DMGDownload(destination: destination, expectedSize: expectedSize, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            download.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    /// Forwards the share of bytes written so far to the progress callback.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedSize ?? 0)
        guard total > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(total)))
    }

    /// Checks the HTTP status and moves the finished file to `destination`; the result is
    /// delivered once the task completes.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            outcome = .failure(UpdateError.httpStatus(http.statusCode))
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            outcome = .success(destination)
        } catch {
            outcome = .failure(UpdateError.staging(error.localizedDescription))
        }
    }

    /// Resumes the waiting caller with the downloaded file or the error, exactly once.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<URL, Error>
        if let error {
            result = .failure(UpdateError.network(error.localizedDescription))
        } else {
            result = outcome ?? .failure(UpdateError.network("The download ended without a file."))
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}
