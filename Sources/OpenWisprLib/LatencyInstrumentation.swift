import Foundation

/// Per-stage timing log for latency budget tuning (#14).
public final class LatencyInstrumentation {
    public static let shared = LatencyInstrumentation()

    private var stages: [String: Date] = [:]
    private var completed: [(stage: String, ms: Double)] = []
    private let lock = NSLock()

    public private(set) var lastSession: [String: Double] = [:]

    public func mark(_ stage: String) {
        lock.lock()
        stages[stage] = Date()
        lock.unlock()
    }

    public func end(_ stage: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let start = stages.removeValue(forKey: stage) else { return }
        let ms = Date().timeIntervalSince(start) * 1000
        completed.append((stage, ms))
        lastSession[stage] = ms
    }

    public func reset() {
        lock.lock()
        stages.removeAll()
        completed.removeAll()
        lastSession.removeAll()
        lock.unlock()
    }

    public func summary() -> String {
        lock.lock()
        defer { lock.unlock() }
        return completed.map { "\($0.stage)=\($0.ms)ms" }.joined(separator: " · ")
    }

    public func totalMs() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return completed.reduce(0) { $0 + $1.ms }
    }
}
