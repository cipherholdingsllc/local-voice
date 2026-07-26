import Foundation

/// Non-destructive raw↔polished toggle (#10).
public final class TranscriptStore {
    public static let shared = TranscriptStore()

    public private(set) var raw: String = ""
    public private(set) var polished: String = ""
    public private(set) var showingPolished: Bool = true

    public func store(raw: String, polished: String) {
        self.raw = raw
        self.polished = polished
        showingPolished = true
    }

    public var active: String {
        showingPolished ? polished : raw
    }

    public func toggle() -> String {
        showingPolished.toggle()
        return active
    }
}
