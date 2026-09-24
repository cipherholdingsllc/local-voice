import Darwin
import Foundation

/// Remove stale whisper-server processes left behind when Local Voice crashes,
/// is force-quit, or is replaced by a newer instance before AppKit teardown
/// finishes. A healthy server is a direct child of the running Local Voice
/// process; anything else is an orphan and consumes the model-loaded memory.
enum WhisperServerOrphanCleaner {
    static func terminateOrphans() {
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let candidates = runningWhisperServerPIDs()
        let orphans = candidates.filter { parentPID(of: $0) != ownPID }
        guard !orphans.isEmpty else { return }

        for pid in orphans {
            fputs(
                "WhisperServerOrphanCleaner: terminating orphan whisper-server pid \(pid)\n",
                stderr
            )
            Darwin.kill(pid, SIGTERM)
        }

        var remaining = orphans
        for _ in 0..<20 {
            remaining = remaining.filter { isAlive($0) }
            guard !remaining.isEmpty else { return }
            usleep(50_000)
        }

        for pid in remaining {
            Darwin.kill(pid, SIGKILL)
        }
    }

    private static func runningWhisperServerPIDs() -> [pid_t] {
        let capacity = 4096
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }

        var result: [pid_t] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0, pid != pid_t(ProcessInfo.processInfo.processIdentifier) else {
                continue
            }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &path, UInt32(MAXPATHLEN))
            guard pathLen > 0 else { continue }
            let pathString = String(cString: path)
            if pathString.lowercased().contains("whisper-server") {
                result.append(pid)
            }
        }
        return result
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        // PROC_PIDT_BSDINFO == 3 from sys/proc_info.h; not imported by Swift.
        let result = proc_pidinfo(pid, Int32(3), 0, &info, size)
        guard result == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        let result = Darwin.kill(pid, 0)
        if result == 0 { return true }
        let error = errno
        return error == EPERM
    }
}
