import Foundation

/// Local-route privacy self-test.
///
/// This proves that the selected engine is a known local route and can
/// transcribe a local fixture. Packet-level network isolation is a separate
/// release test; this code does not pretend to create a firewall.
public enum PrivacySelfTest {
    public struct Result: Sendable {
        public let passed: Bool
        public let localEngineAvailable: Bool
        public let route: STTExecutionRoute
        public let transcriptionSucceeded: Bool
        public let packetIsolationVerified: Bool
        public let message: String
    }

    public static func run(router: STTRouter) -> Result {
        var route = router.activeExecutionRoute()
        var localEngineAvailable = router.hasAvailableLocalEngine()
        var transcriptionSucceeded = false
        var sttMessage = ""

        if localEngineAvailable, let url = try? makeTestTone() {
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                _ = try router.transcribe(audioURL: url)
                transcriptionSucceeded = true
                route = router.activeExecutionRoute()
                localEngineAvailable = router.hasAvailableLocalEngine()
                sttMessage = "Local speech route verified via \(route.label)"
            } catch {
                sttMessage = "Local route test failed: \(error.localizedDescription)"
            }
        } else {
            sttMessage = "No configured local speech engine is available"
        }

        let passed = localEngineAvailable && transcriptionSucceeded
        let message = passed
            ? "\(sttMessage). Packet isolation is a separate release gate."
            : "Privacy test incomplete: \(sttMessage)"

        return Result(
            passed: passed,
            localEngineAvailable: localEngineAvailable,
            route: route,
            transcriptionSucceeded: transcriptionSucceeded,
            packetIsolationVerified: false,
            message: message
        )
    }

    private static func makeTestTone() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-test-\(UUID().uuidString).wav")
        let dataSize = 8000 * 2
        var d = Data()
        d.append(contentsOf: "RIFF".utf8)
        d.append(UInt32(36 + dataSize).leData)
        d.append(contentsOf: "WAVEfmt ".utf8)
        d.append(UInt32(16).leData)
        d.append(UInt16(1).leData)
        d.append(UInt16(1).leData)
        d.append(UInt32(16000).leData)
        d.append(UInt32(32000).leData)
        d.append(UInt16(2).leData)
        d.append(UInt16(16).leData)
        d.append(contentsOf: "data".utf8)
        d.append(UInt32(dataSize).leData)
        d.append(Data(count: dataSize))
        try d.write(to: url)
        return url
    }
}

private extension UInt32 {
    var leData: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
private extension UInt16 {
    var leData: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
