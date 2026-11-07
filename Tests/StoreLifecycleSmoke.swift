import Foundation
import Darwin

@MainActor @main struct StoreLifecycleSmoke {
    static func main() async throws {
        let fm = FileManager.default
        let baselineBrowsers = browserProcessIDs()
        let scratch = fm.temporaryDirectory.appendingPathComponent("dex3js-store-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let projectURL = scratch.appendingPathComponent("Disposable Project", isDirectory: true)
        let settingsURL = scratch.appendingPathComponent("isolated-settings", isDirectory: true)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let port = Int(ProcessInfo.processInfo.environment["DEX3JS_TEST_PORT"] ?? "0") ?? 0
        guard (1...65535).contains(port) else { fatalError("Runner did not supply an isolated local test port") }
        let package = ["name": "dex3js-store-smoke", "version": "1.0.0", "scripts": ["dev": "node fixture.cjs"]] as [String: Any]
        try JSONSerialization.data(withJSONObject: package, options: [.sortedKeys]).write(to: projectURL.appendingPathComponent("package.json"))
        let server = """
        const http = require('node:http');
        const server = http.createServer((_request, response) => response.end('fixture'));
        const mode = process.env.DEX3JS_TEST_MODE || 'normal';
        server.listen(Number(process.env.DEX3JS_TEST_PORT), '127.0.0.1', () => console.log('FIXTURE_READY'));
        if (mode === 'ignore-term') process.on('SIGTERM', () => console.log('FIXTURE_IGNORED_TERM'));
        setInterval(() => console.log('FIXTURE_OUTPUT'), 80);
        """
        try server.write(to: projectURL.appendingPathComponent("fixture.cjs"), atomically: true, encoding: .utf8)

        let project = Project(name: "Disposable Project", path: projectURL.path, trusted: true, url: "http://127.0.0.1:\(port)/")
        var initial: Store? = Store(settingsDirectory: settingsURL)
        initial?.settings = Settings(projects: [project])
        initial?.selectedID = project.id
        initial?.save()
        guard fm.fileExists(atPath: settingsURL.appendingPathComponent("settings.json").path),
              fm.fileExists(atPath: settingsURL.appendingPathComponent("settings.last-good.json").path) else {
            fatalError("Production Store.save did not persist primary and last-good settings")
        }
        initial = nil
        try Data("{ interrupted".utf8).write(to: settingsURL.appendingPathComponent("settings.json"))
        let recoveredSettings = Store(settingsDirectory: settingsURL)
        precondition(recoveredSettings.settings.projects.first?.id == project.id, "Fresh Store did not recover the persisted project identity")
        precondition(recoveredSettings.selected?.path == projectURL.path, "Fresh Store restored the wrong project path")
        precondition(recoveredSettings.message == "Recovered last known-good settings", "Malformed primary settings did not report last-good recovery")
        recoveredSettings.save()
        progress("settings-recovery")

        var launchingStore: Store? = Store(settingsDirectory: settingsURL)
        precondition(launchingStore?.settings.projects.first?.trusted == true, "Trust approval was not restored")
        launchingStore?.start()
        try await waitFor("managed child startup") {
            guard let launchingStore, launchingStore.processState.hasPrefix("Running"),
                  launchingStore.processLog.contains("FIXTURE_OUTPUT") else { return false }
            return loopbackIsReady(port: port)
        }
        guard let ownership = try processRecord(at: settingsURL), ownership.pid > 1, ownership.pgid == ownership.pid else {
            fatalError("Store.start did not write a valid isolated ownership record")
        }
        precondition(groupHasActiveMember(ownership.pgid), "Managed process group was not visible after startup")
        launchingStore = nil // Model an externally surviving child, distinct from normal app termination.

        let reconstructed = Store(settingsDirectory: settingsURL)
        precondition(reconstructed.settings.projects.first?.id == project.id, "Second Store instance lost project identity")
        precondition(reconstructed.processState == "Running · recovered pid \(ownership.pid)", "Fresh Store did not revalidate the test-owned surviving process")
        precondition(reconstructed.selected?.path == projectURL.path, "Recovered Store selected a different project")
        progress("fresh-instance-recovery")

        let unrelatedSentinel = try launchSentinel(in: projectURL)
        defer { stopExact(unrelatedSentinel) }
        let sentinelIdentity = try processIdentity(unrelatedSentinel.processIdentifier)
        precondition(sentinelIdentity.pgid == unrelatedSentinel.processIdentifier, "Sentinel fixture must have an isolated PID-equals-PGID identity")
        let recordURL = settingsURL.appendingPathComponent("process.json")
        try writeForgedRecord(pid: unrelatedSentinel.processIdentifier, pgid: sentinelIdentity.pgid,
                              start: "Jan 01 1970 00:00:00", cwd: projectURL.path, to: recordURL)
        let staleIdentityStore = Store(settingsDirectory: settingsURL)
        precondition(staleIdentityStore.processState == "Stopped", "Stale start-time record was adopted")
        precondition(isRunning(unrelatedSentinel.processIdentifier), "Stale PID validation signaled the unrelated sentinel")

        try writeForgedRecord(pid: unrelatedSentinel.processIdentifier, pgid: sentinelIdentity.pgid,
                              start: sentinelIdentity.start, cwd: projectURL.path, to: recordURL)
        let unrelatedStore = Store(settingsDirectory: settingsURL)
        precondition(unrelatedStore.processState == "Stopped", "An unrelated process with the recorded PID was adopted")
        precondition(isRunning(unrelatedSentinel.processIdentifier), "Unrelated PID validation signaled the sentinel")
        stopExact(unrelatedSentinel)

        // Restore the real owner record and exercise the production cancellation path twice.
        try writeForgedRecord(pid: ownership.pid, pgid: ownership.pgid, start: ownership.start,
                              cwd: projectURL.path, to: recordURL)
        let cancelStore = Store(settingsDirectory: settingsURL)
        precondition(cancelStore.processState.hasPrefix("Running · recovered pid"), "Valid owner record was not reattached for cancellation")
        cancelStore.stop()
        cancelStore.stop()
        try await waitFor("repeated cancellation cleanup") {
            !groupHasActiveMember(ownership.pgid) && cancelStore.processState == "Stopped"
        }
        precondition(!isRunning(unrelatedSentinel.processIdentifier), "Sentinel fixture should be explicitly stopped by its owning test handle")
        precondition(!groupHasActiveMember(ownership.pgid), "Owned parent or child survived cancellation")
        precondition(!fm.fileExists(atPath: recordURL.path), "Cancellation left a stale process record")
        progress("repeated-cancel-cleanup")

        let afterStop = Store(settingsDirectory: settingsURL)
        precondition(afterStop.processState == "Stopped", "Fresh Store did not report the intentionally stopped managed child")

        let outputStore = Store(settingsDirectory: settingsURL)
        setenv("DEX3JS_TEST_MODE", "ignore-term", 1)
        outputStore.start()
        unsetenv("DEX3JS_TEST_MODE")
        try await waitFor("output-producing child startup") {
            guard outputStore.processLog.contains("FIXTURE_OUTPUT") else { return false }
            return loopbackIsReady(port: port)
        }
        guard let timeoutRecord = try processRecord(at: settingsURL) else { fatalError("Output fixture has no process record") }
        let unrelated = try launchSentinel(in: projectURL)
        defer { stopExact(unrelated) }
        precondition(isRunning(unrelated.processIdentifier), "Unrelated sentinel failed before timeout cleanup")
        outputStore.stop()
        try await waitFor("bounded timeout cleanup") {
            !groupHasActiveMember(timeoutRecord.pgid)
                && (outputStore.processState == "Stopped" || outputStore.processState.hasPrefix("Exited ("))
        }
        precondition(outputStore.processState == "Stopped" || outputStore.processState.hasPrefix("Exited ("), "Timeout cleanup left misleading process state: \(outputStore.processState)")
        precondition(isRunning(unrelated.processIdentifier), "Timeout cleanup affected the unrelated sentinel")
        precondition(!fm.fileExists(atPath: recordURL.path), "Timeout cleanup left a stale process record")
        stopExact(unrelated)
        progress("timeout-cleanup")

        let exitStore = Store(settingsDirectory: settingsURL)
        progress("exit-status-start-request")
        exitStore.start()
        progress("exit-status-start-returned: \(exitStore.processState) / \(exitStore.message)")
        guard let exitRecord = try processRecord(at: settingsURL) else { throw SmokeFailure.assertion("Exit-status fixture did not start: \(exitStore.message)") }
        progress("exit-status-record: \(exitRecord.pid)")
        guard Darwin.getpgid(exitRecord.pid) == exitRecord.pgid,
              Darwin.kill(-exitRecord.pgid, 0) == 0,
              Darwin.kill(-exitRecord.pgid, SIGTERM) == 0 else { throw SmokeFailure.assertion("Could not signal the verified fixture process group") }
        progress("exit-status-signaled")
        try await waitFor("exit-status reporting") {
            exitStore.processState.hasPrefix("Exited (") && !groupHasActiveMember(exitRecord.pgid)
        }
        progress("exit-status-reported: \(exitStore.processState)")

        let malformedRecordStore: Store
        try Data("{ not-json".utf8).write(to: recordURL)
        malformedRecordStore = Store(settingsDirectory: settingsURL)
        precondition(malformedRecordStore.processState == "Stopped", "Malformed process record was trusted")
        precondition(malformedRecordStore.settings.projects.first?.id == project.id, "Malformed process record affected persisted settings")
        progress("malformed-record-rejected")

        let chromeAfter = browserProcessIDs()
        precondition(chromeAfter == baselineBrowsers, "Store lifecycle test unexpectedly changed Chrome processes")
        print("PASS: production Store persistence/recovery, fresh-instance process revalidation, stale/unrelated PID rejection, repeated cancellation, output, timeout cleanup, exit status, and browser preservation")
    }

    private static func progress(_ value: String) {
        fputs("STORE TEST: \(value)\n", stderr)
        fflush(stderr)
    }

    private static func waitFor(_ label: String, timeout: TimeInterval = 12, condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(80))
        }
        throw SmokeFailure.timeout(label)
    }

    private static func loopbackIsReady(port: Int) -> Bool {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result == 0
    }

    private static func processRecord(at directory: URL) throws -> OwnerRecord? {
        let url = directory.appendingPathComponent("process.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(OwnerRecord.self, from: data)
    }

    private static func processIdentity(_ pid: Int32) throws -> (pgid: Int32, start: String) {
        let pgidProcess = Process(); pgidProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
        pgidProcess.arguments = ["-p", String(pid), "-o", "pgid="]
        let pgidPipe = Pipe(); pgidProcess.standardOutput = pgidPipe
        try pgidProcess.run(); pgidProcess.waitUntilExit()
        guard let rawGroup = String(data: pgidPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), let group = Int32(rawGroup.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SmokeFailure.processIdentity(pid) }
        let startProcess = Process(); startProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
        startProcess.arguments = ["-p", String(pid), "-o", "lstart="]
        let startPipe = Pipe(); startProcess.standardOutput = startPipe
        try startProcess.run(); startProcess.waitUntilExit()
        let start = String(data: startPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (group, start)
    }

    private static func groupHasActiveMember(_ group: Int32) -> Bool {
        guard group > 1 else { return false }
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,pgid=,stat="]
        let pipe = Pipe(); ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return true }
        ps.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count >= 3 && Int32(fields[1]) == group && !fields[2].contains("Z")
        } ?? true
    }

    private static func isRunning(_ pid: Int32) -> Bool { Darwin.kill(pid, 0) == 0 }

    private static func launchSentinel(in cwd: URL) throws -> Process {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]; process.currentDirectoryURL = cwd
        try process.run()
        guard Darwin.getpgid(process.processIdentifier) == process.processIdentifier else {
            process.terminate(); throw SmokeFailure.sentinelGroup(process.processIdentifier)
        }
        return process
    }

    private static func stopExact(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard Darwin.getpgid(pid) == pid else { return }
        process.terminate()
        process.waitUntilExit()
    }

    private static func writeForgedRecord(pid: Int32, pgid: Int32, start: String, cwd: String, to url: URL) throws {
        let value: [String: Any] = ["version": 1, "pid": pid, "pgid": pgid, "start": start, "cwd": cwd,
                                    "executable": "/opt/homebrew/bin/npm", "appBundleID": "com.westkitty.dex3js"]
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: .atomic)
    }

    private static func browserProcessIDs() -> [Int32] {
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps"); ps.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe(); ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return (String(data: output, encoding: .utf8) ?? "").split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.contains("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") else { return nil }
            return Int32(text.split(whereSeparator: \.isWhitespace).first ?? "")
        }.sorted()
    }
}

private struct OwnerRecord: Decodable { let pid: Int32; let pgid: Int32; let start: String }
private enum SmokeFailure: Error { case timeout(String); case processIdentity(Int32); case sentinelGroup(Int32); case assertion(String) }
