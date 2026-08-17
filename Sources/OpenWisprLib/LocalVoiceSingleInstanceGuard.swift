import AppKit
import Darwin
import Foundation

enum LocalVoiceSingleInstanceGuard {
    private static var lockDescriptor: Int32 = -1

    static func claimCurrentProcess() -> Bool {
        let canonicalURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Local Voice.app")
            .standardizedFileURL
        let currentURL = Bundle.main.bundleURL.standardizedFileURL

        // Development/release copies should never become a second hotkey
        // listener. Route them to the one trusted installed bundle instead.
        if currentURL.path != canonicalURL.path,
           FileManager.default.fileExists(atPath: canonicalURL.path) {
            NSWorkspace.shared.open(canonicalURL)
            return false
        }

        let supportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Local Voice")
        try? FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
        let lockURL = supportURL.appendingPathComponent("instance.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return true }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            lockDescriptor = descriptor
            terminateLegacyPeers()
            return true
        }

        Darwin.close(descriptor)
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.cipherholdings.localvoice"
        ).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
            .activate(options: [.activateIgnoringOtherApps])
        return false
    }

    private static func terminateLegacyPeers() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.cipherholdings.localvoice"
        ) where application.processIdentifier != ownPID {
            application.terminate()
        }
    }
}
