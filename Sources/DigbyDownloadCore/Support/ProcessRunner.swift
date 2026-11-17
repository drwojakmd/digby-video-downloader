import Foundation
import Darwin

/// Runs an external tool with an argument array (never a shell), streams its output line by line,
/// and can stop it together with everything it started (yt-dlp launches FFmpeg): each child runs
/// in its own process group, and cancelling signals the whole group.
public final class RunningProcess: @unchecked Sendable {
    public let pid: pid_t
    private let lock = NSLock()
    private var finished = false
    private(set) public var cancelled = false

    init(pid: pid_t) { self.pid = pid }

    /// SIGTERM to the whole group, then SIGKILL after a grace period.
    public func cancel(grace: TimeInterval = 3) {
        lock.lock(); cancelled = true; let done = finished; lock.unlock()
        guard !done else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let done = self.finished; self.lock.unlock()
            if !done { kill(-self.pid, SIGKILL) }
        }
    }
    func markFinished() { lock.lock(); finished = true; lock.unlock() }
}

public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var cancelled: Bool
    public var succeeded: Bool { status == 0 && !cancelled }
}

/// Every child process the app started, so quitting can stop them all.
public final class ProcessRegistry: @unchecked Sendable {
    public static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var running: [pid_t: RunningProcess] = [:]
    func add(_ p: RunningProcess) { lock.lock(); running[p.pid] = p; lock.unlock() }
    func remove(_ p: RunningProcess) { lock.lock(); running[p.pid] = nil; lock.unlock() }
    public func terminateAll() {
        lock.lock(); let all = Array(running.values); lock.unlock()
        all.forEach { $0.cancel(grace: 1) }
    }
}

public enum ProcessRunner {
    public struct LaunchError: Error, CustomStringConvertible {
        public var description: String
    }

    /// Runs `executable` with `arguments`. `onLine` receives each stdout/stderr line as it arrives
    /// (on a background queue). `started` hands back the handle for cancellation.
    @discardableResult
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           currentDirectory: URL? = nil, keepOutput: Bool = true,
                           started: ((RunningProcess) -> Void)? = nil,
                           onLine: ((String, _ isError: Bool) -> Void)? = nil) async throws -> ProcessResult {
        var outPipe: [Int32] = [0, 0], errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else { throw LaunchError(description: "Couldn’t create pipes") }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addclose(&actions, outPipe[0])
        posix_spawn_file_actions_addclose(&actions, errPipe[0])
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        if let cwd = currentDirectory { posix_spawn_file_actions_addchdir_np(&actions, cwd.path) }

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Own process group (so cancel reaches grandchildren); close every other inherited descriptor.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)

        let env = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
        let argv = [executable.path] + arguments
        var pid: pid_t = 0
        let rc = withCStrings(argv) { cargv in
            withCStrings(env) { cenv in
                posix_spawn(&pid, executable.path, &actions, &attr, cargv, cenv)
            }
        }
        close(outPipe[1]); close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0]); close(errPipe[0])
            throw LaunchError(description: "Couldn’t start \(executable.lastPathComponent): \(String(cString: strerror(rc)))")
        }
        let handle = RunningProcess(pid: pid)
        ProcessRegistry.shared.add(handle)
        started?(handle)

        let outFD = outPipe[0], errFD = errPipe[0]
        async let out = readLines(outFD, isError: false, keep: keepOutput, onLine: onLine)
        async let err = readLines(errFD, isError: true, keep: true, onLine: onLine)
        let (o, e) = await (out, err)
        let status: Int32 = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var st: Int32 = 0
                while waitpid(pid, &st, 0) == -1 && errno == EINTR {}
                cont.resume(returning: st)
            }
        }
        handle.markFinished()
        ProcessRegistry.shared.remove(handle)
        // Decode the wait status: normal exit code, or 128 + signal.
        let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return ProcessResult(status: code, stdout: o, stderr: e, cancelled: handle.cancelled)
    }

    static func readLines(_ fd: Int32, isError: Bool, keep: Bool, onLine: ((String, Bool) -> Void)?) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var all = Data(), pending = Data()
                var buf = [UInt8](repeating: 0, count: 65536)
                while true {
                    let n = read(fd, &buf, buf.count)
                    if n < 0 && errno == EINTR { continue }
                    if n <= 0 { break }
                    let chunk = Data(buf[0..<n])
                    if keep { all.append(chunk) }
                    if let onLine {
                        pending.append(chunk)
                        while let nl = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                            let line = pending[pending.startIndex..<nl]
                            pending.removeSubrange(pending.startIndex...nl)
                            if !line.isEmpty { onLine(String(decoding: line, as: UTF8.self), isError) }
                        }
                    }
                }
                if let onLine, !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self), isError) }
                close(fd)
                cont.resume(returning: String(decoding: all, as: UTF8.self))
            }
        }
    }

    private static func withCStrings<R>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
        let c = strings.map { strdup($0) } + [nil]
        defer { c.forEach { free($0) } }
        return body(c)
    }
}
