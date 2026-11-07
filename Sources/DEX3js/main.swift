import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var favorite = false
    var actions: [ProjectAction] = []
    var trusted = false
    var url: String? = nil
}
struct ProjectAction: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
}
struct Settings: Codable { var version = 1; var projects: [Project] = []; var preferredEditor = "Visual Studio Code" }
struct ProjectProfile: Codable { var version: Int; var name: String; var url: String?; var actions: [ProfileAction] }
struct ProfileAction: Codable { var name: String; var path: String }

struct SceneNode: Identifiable, Hashable {
    var id: String { path }
    let path, name, type, summary: String
    let reportedChildCount: Int?
    let canInspect: Bool
    let selectionDisabledReason: String?
    let children: [SceneNode]
    var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }
    var descendants: [SceneNode] { [self] + children.flatMap(\.descendants) }
    init(_ value: [String: Any], path parent: String = "", parentCanBeAddressed: Bool = true) {
        type = value["type"] as? String ?? "Object"
        let rawName = (value["name"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let canAddress = parentCanBeAddressed && rawName != nil
        name = rawName ?? "(unnamed \(type))"
        reportedChildCount = value["childCount"] as? Int
        canInspect = canAddress
        selectionDisabledReason = rawName == nil
            ? "The installed scene bridge provides no name or stable identifier for this object."
            : (!parentCanBeAddressed ? "An ancestor has no addressable MCP path, so this object cannot be selected." : nil)
        let nodePath = parent.isEmpty ? name : "\(parent).\(name)"
        path = nodePath
        let fields = value.filter { !["name", "type", "children"].contains($0.key) }
        summary = fields.keys.sorted().compactMap { key in
            guard let data = try? JSONSerialization.data(withJSONObject: fields[key] as Any, options: [.fragmentsAllowed, .sortedKeys]), let text = String(data: data, encoding: .utf8) else { return nil }
            return "\(key): \(text)"
        }.joined(separator: "\n")
        children = (value["children"] as? [[String: Any]] ?? []).map { SceneNode($0, path: nodePath, parentCanBeAddressed: canAddress) }
    }
}

private struct SceneCompletion {
    let generation: UUID
    let callback: (Result<Any, Error>) -> Void
}

private struct ProjectProcessRecord: Decodable {
    let pid: Int32
    let pgid: Int32
    let start: String
    let cwd: String
    let executable: String
    let appBundleID: String
}

@MainActor final class Store: ObservableObject {
    @Published var settings: Settings
    @Published var selectedID: UUID?
    @Published var query = ""
    @Published var message = "Ready"
    @Published var processState = "Stopped"
    @Published var processLog = ""
    @Published var serverURL = ""
    @Published var health: [String: ProbeObservation] = [:]
    @Published var isCheckingTools = false
    @Published var lastCheckedAt: Date?
    @Published var inspectionOutput = ""
    @Published var inspecting = false
    @Published var sceneNodes: [SceneNode] = []
    @Published var selectedScenePath = ""
    @Published var objectDetails = ""
    @Published var pendingChanges = ""
    @Published var previewProperty = "roughness"
    @Published var previewValue = "0.35"
    @Published var sceneStatus = "Disconnected"
    @Published var sceneSnapshotProject = ""
    @Published var sceneBrowserURL = ""
    @Published var sceneSessionID = ""
    @Published var sceneSessionProject = ""
    @Published var sceneBrowserName = ""
    @Published var sceneBrowserVersion = ""
    @Published var sceneBrowserPID: Int32 = 0
    @Published var sceneMCPPID: Int32 = 0
    @Published var sceneBrowserTargetID = ""
    @Published var sceneCDPPort = 0
    @Published var sceneLastError = ""
    @Published var sceneSessionStartedAt: Date?
    @Published var sceneLastActivityAt: Date?
    @Published var sceneLastSuccessfulInspection: Date?
    @Published var sceneOwned = false
    @Published var sceneCleanupMessage = ""
    @Published var sceneSearch = ""
    @Published var sceneTypeFilter = "All"
    @Published var expandedScenePaths: Set<String> = []
    @Published var isPreviewMutationPending = false
    private var sceneProcess: Process?
    private var sceneInput: Pipe?
    private var sceneFramer = SceneOutputFramer()
    private var nextSceneCommand = 0
    private var sceneCompletions: [Int: SceneCompletion] = [:]
    private var sceneGeneration = UUID()
    private var sceneOwnedProcessGroup: Int32 = 0
    private var sceneHelperPath = ""
    var sceneSessionActive: Bool { sceneProcess?.isRunning == true }
    var sceneConnected: Bool { sceneStatus == "Connected · scene loaded" }
    var sceneTypes: [String] { ["All"] + Array(Set(sceneNodes.flatMap(\.descendants).map(\.type))).sorted() }
    var visibleSceneMatches: [SceneNode] {
        sceneNodes.flatMap(\.descendants).filter { node in
            let matchesName = sceneSearch.isEmpty || node.name.localizedCaseInsensitiveContains(sceneSearch) || node.path.localizedCaseInsensitiveContains(sceneSearch)
            let matchesType = sceneTypeFilter == "All" || node.type == sceneTypeFilter
            return matchesName && matchesType
        }
    }
    var sceneSessionAge: String {
        guard let started = sceneSessionStartedAt else { return "Not active" }
        let elapsed = max(0, Int(Date().timeIntervalSince(started)))
        if elapsed < 60 { return "\(elapsed)s" }
        return "\(elapsed / 60)m \(elapsed % 60)s"
    }
    var pendingChangeIDs: [Int] {
        let pattern = #"#(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(pendingChanges.startIndex..., in: pendingChanges)
        return Array(Set(regex.matches(in: pendingChanges, range: range).compactMap { match in Range(match.range(at: 1), in: pendingChanges).flatMap { Int(pendingChanges[$0]) } })).sorted()
    }
    func expandAllScene(_ expanded: Bool) { expandedScenePaths = expanded ? Set(sceneNodes.flatMap(\.descendants).filter { !$0.children.isEmpty }.map(\.path)) : [] }
    func inspectorDiagnosticReport() -> String {
        let formatter = ISO8601DateFormatter()
        func stamp(_ value: Date?) -> String { value.map(formatter.string(from:)) ?? "Not recorded" }
        return [
            "DEX 3js inspector diagnostics",
            "Project: \(sceneSessionProject.isEmpty ? (selected?.name ?? "None") : sceneSessionProject)",
            "State: \(sceneStatus)", "DEX-owned: \(sceneOwned ? "Yes" : "No / unverified")",
            "Browser: \(sceneBrowserName.isEmpty ? "Not active" : sceneBrowserName)",
            "Browser version: \(sceneBrowserVersion.isEmpty ? "Not verified" : sceneBrowserVersion)",
            "Target: \(sceneBrowserTargetID.isEmpty ? "Not verified" : sceneBrowserTargetID)",
            "Proxy: \(sceneBrowserURL.isEmpty ? "Not active" : sceneBrowserURL)",
            "Session age: \(sceneSessionAge)", "Last activity: \(stamp(sceneLastActivityAt))",
            "Last successful inspection: \(stamp(sceneLastSuccessfulInspection))",
            "Cleanup: \(sceneCleanupMessage.isEmpty ? "No cleanup action recorded" : sceneCleanupMessage)",
            "Last error: \(sceneLastError.isEmpty ? "None" : sceneLastError)"
        ].joined(separator: "\n")
    }
    private var probeSequence = UUID()
    private var process: Process?
    private var recoveredProcessPID: Int32?
    private var logPipe: Pipe?
    private let file: URL
    private let lastGood: URL
    private let processRecord: URL
    init(settingsDirectory: URL? = nil) {
        let dir = settingsDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DEX 3js", isDirectory: true)
        file = dir.appendingPathComponent("settings.json"); lastGood = dir.appendingPathComponent("settings.last-good.json"); processRecord = dir.appendingPathComponent("process.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        for localFile in [file, lastGood, processRecord] where FileManager.default.fileExists(atPath: localFile.path) { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localFile.path) }
        if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(Settings.self, from: data), decoded.version == 1 { settings = decoded }
        else if let data = try? Data(contentsOf: lastGood), let decoded = try? JSONDecoder().decode(Settings.self, from: data) { settings = decoded; message = "Recovered last known-good settings" }
        else { settings = Settings() }
        selectedID = settings.projects.first?.id
        if let record = verifiedProjectProcessRecord() {
            selectedID = settings.projects.first(where: { $0.path == record.cwd })?.id
            recoveredProcessPID = record.pid
            processState = "Running · recovered pid \(record.pid)"
            serverURL = selected?.url ?? ""
            message = "Recovered the verified DEX-owned project process after the app restarted"
        }
    }
    var selected: Project? { settings.projects.first { $0.id == selectedID } }
    private var managedProjectIsRunning: Bool { process?.isRunning == true || (recoveredProcessPID != nil && verifiedProjectProcessRecord() != nil) }
    var visibleProjects: [Project] { settings.projects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }.sorted { $0.favorite && !$1.favorite } }
    func save() {
        do {
            let data = try JSONEncoder.pretty.encode(settings)
            try data.write(to: file, options: .atomic)
            try data.write(to: lastGood, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lastGood.path)
            message = "Configuration saved"
        } catch { message = "Settings save failed: \(error.localizedDescription)" }
    }
    func reload() {
        guard let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(Settings.self, from: data), decoded.version == 1 else { message = "Settings are invalid; keeping last known-good configuration"; return }
        settings = decoded; selectedID = decoded.projects.first?.id; message = "Configuration reloaded"
    }
    func addProject(_ url: URL) {
        let maySelect = process == nil
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("package.json").path) else { message = "Selected folder has no package.json"; return }
        let name = url.lastPathComponent
        var project = Project(name: name, path: url.standardizedFileURL.path)
        if let profile = readProfile(at: url) { project.name = profile.name; project.url = profile.url; project.actions = profile.actions.map { ProjectAction(name: $0.name, url: $0.path) } }
        settings.projects.removeAll { $0.path == project.path }; settings.projects.insert(project, at: 0); if maySelect { selectedID = project.id }; save()
    }
    func removeSelected() { guard let p = selected else { return }; guard !managedProjectIsRunning else { message = "Stop the managed project before removing it"; return }; settings.projects.removeAll { $0.id == p.id }; selectedID = settings.projects.first?.id; serverURL = ""; processLog = ""; processState = "Stopped"; save() }
    func selectProject(_ id: UUID?) {
        guard !managedProjectIsRunning || id == selectedID else { message = "Stop the managed project before switching projects"; return }
            guard !inspecting || id == selectedID else { message = "Disconnect scene inspector before switching projects"; return }
        if selectedID != id {
            selectedID = id; serverURL = ""; processLog = ""; processState = "Stopped"
            probeSequence = UUID(); health = [:]; lastCheckedAt = nil
            pendingChanges = ""; disconnectScene(); selectedScenePath = ""
            if !sceneSnapshotProject.isEmpty { sceneStatus = "Disconnected · cached snapshot: \(sceneSnapshotProject)" }
            message = "Project selected"
            isCheckingTools = false
            refreshHealth()
        }
    }
    func toggleFavorite(_ p: Project) { guard let i = settings.projects.firstIndex(where: {$0.id == p.id}) else { return }; settings.projects[i].favorite.toggle(); save() }
    func reloadProfile() { guard let p = selected, let profile = readProfile(at: URL(fileURLWithPath: p.path)) else { message = "Missing or invalid dex3js.json profile"; return }; guard let i = settings.projects.firstIndex(where: {$0.id == p.id}) else { return }; settings.projects[i].name = profile.name; settings.projects[i].url = profile.url; settings.projects[i].actions = profile.actions.map { ProjectAction(name: $0.name, url: $0.path) }; save() }
    func importProfile() { let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowedContentTypes = [.json]; if panel.runModal() == .OK, let url = panel.url, let profile = decodeProfile(at: url), let i = settings.projects.firstIndex(where: {$0.id == selectedID}) { settings.projects[i].name = profile.name; settings.projects[i].url = profile.url; settings.projects[i].actions = profile.actions.map { ProjectAction(name: $0.name, url: $0.path) }; save() } else { message = "Selected profile is invalid or no project is selected" } }
    func exportProfile() { guard let p = selected else { return }; let panel = NSSavePanel(); panel.nameFieldStringValue = "dex3js.json"; if panel.runModal() == .OK, let url = panel.url { let profile = ProjectProfile(version: 1, name: p.name, url: p.url, actions: p.actions.map { ProfileAction(name: $0.name, path: $0.url) }); do { try JSONEncoder.pretty.encode(profile).write(to: url, options: .atomic); message = "Project profile exported" } catch { message = "Export failed: \(error.localizedDescription)" } } }
    private func readProfile(at projectURL: URL) -> ProjectProfile? { decodeProfile(at: projectURL.appendingPathComponent("dex3js.json")) }
    private func decodeProfile(at url: URL) -> ProjectProfile? { guard let data = try? Data(contentsOf: url), let profile = try? JSONDecoder().decode(ProjectProfile.self, from: data), validProfile(profile) else { return nil }; return profile }
    private func validProfile(_ profile: ProjectProfile) -> Bool {
        guard profile.version == 1, !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.actions.allSatisfy({ action in
                  guard !action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action.path.hasPrefix("/"), !action.path.hasPrefix("//"), !action.path.contains("\\"),
                        let path = URLComponents(string: action.path), path.scheme == nil, path.host == nil else { return false }
                  return true
              }) else { return false }
        guard let raw = profile.url else { return true }
        guard let base = URLComponents(string: raw), ["http", "https"].contains(base.scheme?.lowercased() ?? ""),
              ["localhost", "127.0.0.1"].contains(base.host?.lowercased() ?? ""),
              base.port.map({ (1...65535).contains($0) }) ?? true else { return false }
        return true
    }
    func setTrust(_ value: Bool) { guard let i = settings.projects.firstIndex(where: {$0.id == selectedID}) else { return }; settings.projects[i].trusted = value; save() }
    func start() {
        guard let p = selected, p.trusted else { message = "Review and approve this project's start command first"; return }
        guard process == nil, recoveredProcessPID == nil else { message = "A managed project is already running"; return }
        serverURL = ""; processLog = ""
        let root = URL(fileURLWithPath: p.path)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("package.json").path) else { message = "Project path is missing package.json"; return }
        guard let manifest = try? Data(contentsOf: root.appendingPathComponent("package.json")), let json = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any], let scripts = json["scripts"] as? [String: String], scripts["dev"] != nil else { message = "This project has no package.json dev script"; return }
        let manager = packageManagerName(at: root)
        let candidates: [String: [String]] = ["npm": ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"], "pnpm": ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"], "yarn": ["/opt/homebrew/bin/yarn", "/usr/local/bin/yarn"], "bun": ["/opt/homebrew/bin/bun", "/usr/local/bin/bun"]]
        guard let executable = candidates[manager]?.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { message = "No verified executable found for package manager \(manager)"; return }
        let args = manager == "npm" ? ["run", "dev", "--", "--host", "127.0.0.1"] : ["run", "dev", "--host", "127.0.0.1"]
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args; task.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment; env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"; task.environment = env
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe; logPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let bytes = h.availableData; guard !bytes.isEmpty, let text = String(data: bytes, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.processLog = String(self.processLog + text.suffix(3000))
                if let match = text.range(of: #"https?://(?:localhost|127\.0\.0\.1):\d+[^\s]*"#, options: .regularExpression) {
                    let capturedURL = String(text[match])
                    if self.serverURL != capturedURL {
                        self.serverURL = capturedURL
                        // If the initial probe is already running, its completion notices
                        // the changed endpoint and repeats against this URL. Otherwise,
                        // begin probing as soon as the dev server announces it.
                        self.refreshHealth()
                    }
                }
            }
        }
        task.terminationHandler = { [weak self] proc in
            // Foundation launched npm into a dedicated process group (PGID == its PID).
            // Terminate only that positively owned group so npm's Vite/esbuild children do not survive.
            let ownedGroup = proc.processIdentifier
            _ = Darwin.kill(-ownedGroup, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if Darwin.kill(-ownedGroup, 0) == 0 { _ = Darwin.kill(-ownedGroup, SIGKILL) }
            }
            Task { @MainActor in self?.clearProcessRecord(pid: proc.processIdentifier); self?.process = nil; self?.processState = "Exited (\(proc.terminationStatus))"; self?.logPipe?.fileHandleForReading.readabilityHandler = nil }
        }
        do { try task.run(); process = task; writeProcessRecord(task, workingDirectory: p.path); processState = "Running · pid \(task.processIdentifier)"; message = "Started owned \(manager) dev process" }
        catch { message = "Launch failed: \(error.localizedDescription)" }
    }
    private func writeProcessRecord(_ task: Process, workingDirectory: String) {
        let pid = task.processIdentifier
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/ps"); ps.arguments = ["-p", String(pid), "-o", "lstart="]
        let output = Pipe(); ps.standardOutput = output; ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { message = "Process started, but ownership record could not be read"; return }
        ps.waitUntilExit(); let start = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let object: [String: Any] = ["version": 1, "pid": pid, "pgid": pid, "start": start, "cwd": workingDirectory, "executable": task.executableURL?.path ?? "", "appBundleID": "com.westkitty.dex3js"]
        do { let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]); try data.write(to: processRecord, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: processRecord.path) }
        catch { message = "Process started, ownership record failed: \(error.localizedDescription)" }
    }
    private func clearProcessRecord(pid: Int32) {
        guard let data = try? Data(contentsOf: processRecord), let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (record["pid"] as? NSNumber)?.int32Value == pid else { return }
        try? FileManager.default.removeItem(at: processRecord)
    }
    private func verifiedProjectProcessRecord() -> ProjectProcessRecord? {
        guard let data = try? Data(contentsOf: processRecord),
              let record = try? JSONDecoder().decode(ProjectProcessRecord.self, from: data),
              record.appBundleID == "com.westkitty.dex3js", record.pid > 1, record.pgid == record.pid,
              ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm",
               "/opt/homebrew/bin/yarn", "/usr/local/bin/yarn", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"].contains(record.executable),
              let project = settings.projects.first(where: { $0.path == record.cwd }), project.trusted else { return nil }
        func output(_ executable: String, _ arguments: [String]) -> String? {
            let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            guard (try? task.run()) != nil else { return nil }; task.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let groupText = output("/bin/ps", ["-p", String(record.pid), "-o", "pgid="]),
              let group = Int32(groupText), group == record.pgid,
              let start = output("/bin/ps", ["-p", String(record.pid), "-o", "lstart="]), start == record.start,
              let command = output("/bin/ps", ["-p", String(record.pid), "-o", "args="]),
              command.split(whereSeparator: \.isWhitespace).first.map(String.init) == URL(fileURLWithPath: record.executable).lastPathComponent,
              command.localizedCaseInsensitiveContains("run dev"),
              let cwdOutput = output("/usr/sbin/lsof", ["-a", "-p", String(record.pid), "-d", "cwd", "-Fn"]),
              let liveCWD = cwdOutput.split(separator: "\n").first(where: { $0.hasPrefix("n") }).map({ String($0.dropFirst()) }),
              let recordedCWD = Self.canonicalFilesystemPath(record.cwd),
              let actualCWD = Self.canonicalFilesystemPath(liveCWD), recordedCWD == actualCWD else { return nil }
        return record
    }
    private static func canonicalFilesystemPath(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard path.withCString({ realpath($0, &buffer) }) != nil else { return nil }
        return String(cString: buffer)
    }
    func stop() {
        if sceneSessionActive { disconnectScene() }
        let ownedGroup: Int32
        if let p = process, p.isRunning { ownedGroup = p.processIdentifier }
        else if let recovered = verifiedProjectProcessRecord(), recovered.pid == recoveredProcessPID { ownedGroup = recovered.pgid }
        else { message = "No verified DEX-owned project process is available to stop"; processState = "Stopped · ownership could not be verified"; return }
        guard Darwin.getpgid(ownedGroup) == ownedGroup else { message = "Project process group identity changed; no signal was sent"; return }
        _ = Darwin.kill(-ownedGroup, SIGTERM); processState = "Stopping…"; message = "Sent graceful stop to verified DEX-owned process group"
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if Darwin.kill(-ownedGroup, 0) == 0 { _ = Darwin.kill(-ownedGroup, SIGKILL) }; Task { @MainActor in self.clearProcessRecord(pid: ownedGroup); self.process = nil; self.recoveredProcessPID = nil; self.processState = "Stopped" } }
    }
    func openURL(_ value: String) { guard let url = URL(string: value) else { return }; NSWorkspace.shared.open(url) }
    func openFolder() { guard let p = selected else { return }; NSWorkspace.shared.open(URL(fileURLWithPath: p.path)) }
    func openEditor() { guard let p = selected else { return }; let choices = ["/opt/homebrew/bin/code", "/usr/local/bin/code", "/Applications/Cursor.app/Contents/MacOS/Cursor"]; if let bin = choices.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { let proc = Process(); proc.executableURL = URL(fileURLWithPath: bin); proc.arguments = [p.path]; try? proc.run() } else { message = "No supported editor launcher found; open the folder manually" } }
    func selectFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { addProject(url) } }
    func studio() {
        let lab = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/3d-lab")
        guard FileManager.default.isExecutableFile(atPath: lab.path) else { message = "Shared 3d-lab launcher is missing"; return }
        let task = Process(); task.executableURL = lab; task.arguments = ["studio"]; task.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory()); task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory()]
        do {
            try task.run()
            message = "Studio launch requested; refresh connections to confirm readiness"
        } catch { message = "Studio launch failed: \(error.localizedDescription)" }
    }
    // Explicit, bounded local probes: an installed or registered MCP is not a live connection.
    func refreshHealth() {
        guard !isCheckingTools else { return }
        let token = UUID()
        probeSequence = token
        isCheckingTools = true
        let selectedURL = serverURL.isEmpty ? selected?.url : serverURL
        health = [
            "project": .checking,
            "bridge": .checking,
            "studioAPI": .checking,
            "studioWeb": .checking
        ]
        Task { [weak self] in
            async let project = ToolProbe.check(selectedURL)
            async let bridge = ToolProbe.check("http://127.0.0.1:9222/__devtools_status", bridge: true)
            async let api = ToolProbe.check("http://127.0.0.1:4000/health")
            async let web = ToolProbe.check("http://127.0.0.1:5180/")
            let resolved = await [
                "project": project,
                "bridge": bridge,
                "studioAPI": api,
                "studioWeb": web
            ]
            guard let self, self.probeSequence == token else { return }
            if !self.serverURL.isEmpty, selectedURL != self.serverURL {
                self.isCheckingTools = false
                self.refreshHealth()
                return
            }
            var observations = resolved
            if self.sceneProcess != nil {
                observations["bridge"] = self.sceneStatus == "Connected · scene loaded"
                    ? ProbeObservation(state: .connected, detail: "DEX DevTools MCP confirmed the live browser scene")
                    : ProbeObservation(state: .disconnected, detail: "DEX DevTools MCP session active; waiting for a readable browser scene")
            }
            self.health = observations
            self.lastCheckedAt = Date()
            self.isCheckingTools = false
            self.message = "Local connection check completed"
        }
    }
    func probe(_ key: String) -> ProbeObservation {
        health[key] ?? .unknown
    }
    func openSelectedProject() {
        guard let raw = (serverURL.isEmpty ? selected?.url : serverURL),
              let url = LocalEndpoint.validated(raw) else {
            message = "Start the project or configure a local HTTP URL first"; return
        }
        openURL(url.absoluteString)
    }
    func openProjectAction(_ action: ProjectAction) {
        guard let raw = (serverURL.isEmpty ? selected?.url : serverURL),
              let base = LocalEndpoint.validated(raw),
              action.url.hasPrefix("/"), !action.url.hasPrefix("//"),
              let target = URL(string: action.url, relativeTo: base)?.absoluteURL,
              let checked = LocalEndpoint.validated(target.absoluteString) else {
            message = "This project action has no safe local destination"; return
        }
        openURL(checked.absoluteString)
    }
    func openStudioWeb() {
        guard probe("studioWeb").state == .ready else {
            message = "Studio web is not verified reachable. Start Studio, then refresh connections."; return
        }
        openURL("http://127.0.0.1:5180/")
    }
    func openNeedleInChrome() {
        guard let raw = (serverURL.isEmpty ? selected?.url : serverURL),
              let target = LocalEndpoint.validated(raw) else {
            message = "Start the local project before opening its inspector"; return
        }
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        guard FileManager.default.fileExists(atPath: chrome.path) else {
            message = "Google Chrome not found at the expected location"; return
        }
        let launcher = Process(); launcher.executableURL = URL(fileURLWithPath: chrome.path + "/Contents/MacOS/Google Chrome")
        launcher.arguments = ["--new-window", target.absoluteString]
        do {
            try launcher.run()
            message = "Opened the project in Chrome's regular profile; enable Needle Inspector from its extension toolbar"
        } catch { message = "Chrome could not open the project: \(error.localizedDescription)" }
    }
    func inspectScene() {
        guard !inspecting else { message = "Scene inspection is already in progress"; return }
        if sceneSessionActive {
            if sceneConnected { refreshScene() } else { reconnectScene() }
            return
        }
        startInspectorSession(reconnecting: false)
    }
    private func startInspectorSession(reconnecting: Bool) {
        guard let project = selected, project.trusted else {
            message = "Select a trusted project before launching its inspector"; return
        }
        guard managedProjectIsRunning else { message = "Start this trusted project from DEX before connecting the scene inspector"; return }
        guard FileManager.default.fileExists(atPath: URL(fileURLWithPath: project.path).appendingPathComponent("package.json").path) else {
            message = "Project package.json is missing"; return
        }
        guard let localURL = LocalEndpoint.validated(serverURL.isEmpty ? project.url ?? "" : serverURL) else { sceneStatus = "Unavailable"; message = "DEX has not measured a local project URL yet. Wait for the server URL, then retry."; return }
        guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { sceneStatus = "Unavailable"; message = "Node.js is missing; repair the installed 3d-lab toolkit."; return }
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("scene-bridge.mjs"), FileManager.default.fileExists(atPath: helper.path) else { sceneStatus = "Unavailable"; message = "Scene bridge helper is missing; rebuild DEX."; return }
        guard sceneProcess == nil else { message = "The previous inspector session is still shutting down"; return }
        let sessionID = UUID().uuidString
        sceneGeneration = UUID(); sceneCompletions.removeAll(); sceneFramer.reset()
        sceneSessionID = sessionID; sceneSessionProject = project.name
        sceneSessionStartedAt = Date(); sceneLastActivityAt = Date(); sceneLastSuccessfulInspection = nil
        sceneBrowserName = "Google Chrome · isolated DEX profile"; sceneBrowserVersion = ""; sceneBrowserPID = 0; sceneMCPPID = 0
        sceneBrowserTargetID = ""; sceneCDPPort = 0; sceneOwned = false; sceneLastError = ""
        sceneCleanupMessage = "Starting isolated inspector session"; sceneHelperPath = helper.path
        let task = Process(); task.executableURL = URL(fileURLWithPath: node); task.arguments = [helper.path, "--session-id", sessionID]
        task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        let output = Pipe(); let input = Pipe(); task.standardOutput = output; task.standardInput = input; task.standardError = FileHandle.nullDevice
        sceneInput = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData; guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.consumeSceneOutput(chunk) }
        }
        task.terminationHandler = { [weak self] proc in Task { @MainActor in
            guard let self, self.sceneProcess?.processIdentifier == proc.processIdentifier else { return }
            self.sceneProcess = nil; self.sceneInput = nil; self.inspecting = false
            let truncatedBytes = self.sceneFramer.finish()
            let failure = truncatedBytes > 0
                ? "Inspector helper exited with a truncated response (\(truncatedBytes) buffered bytes); reconnect to retry."
                : "Inspector helper exited before completing the pending request; reconnect to retry."
            let pending = Array(self.sceneCompletions.values)
            self.sceneCompletions.removeAll()
            pending.forEach { $0.callback(.failure(NSError(domain: "DEXScene", code: 4, userInfo: [NSLocalizedDescriptionKey: failure]))) }
            if self.sceneStatus == "Disconnecting" { return }
            if !pending.isEmpty || truncatedBytes > 0 { self.sceneLastError = failure; self.inspectionOutput = failure }
            if self.sceneOwnedProcessGroup > 0 && Darwin.kill(-self.sceneOwnedProcessGroup, 0) == 0 {
                self.sceneStatus = "Cleanup pending"
                self.sceneCleanupMessage = "Inspector helper exited; DEX is verifying the owned MCP/browser resources are closed."
                self.finishOwnedSceneGroupCleanup(group: self.sceneOwnedProcessGroup, completion: nil)
            } else {
                self.clearSceneSession()
                self.sceneStatus = self.sceneSnapshotProject.isEmpty ? "Disconnected" : "Disconnected · cached snapshot"
                self.sceneCleanupMessage = "DEX-owned inspector processes and browser are closed"
                self.health["bridge"] = ProbeObservation(state: .disconnected, detail: "Inspector session is closed")
            }
        } }
        do {
            try task.run()
            let pid = task.processIdentifier
            guard pid > 0, Darwin.getpgid(pid) == pid else {
                task.terminate(); sceneStatus = "Error"; sceneLastError = "DEX could not verify a private process group for the inspector; no browser was opened."; message = sceneLastError; return
            }
            sceneProcess = task; sceneOwnedProcessGroup = pid
        } catch {
            sceneStatus = "Unavailable"; health["bridge"] = ProbeObservation(state: .stopped, detail: "Could not start DEX scene helper")
            sceneLastError = error.localizedDescription; message = "Could not start scene bridge: \(error.localizedDescription)"; return
        }
        inspectionOutput = "Connecting to the real Three.js scene…"; inspecting = true; sceneStatus = reconnecting ? "Reconnecting" : "Connecting"
        health["bridge"] = ProbeObservation(state: .disconnected, detail: "DEX DevTools MCP session is connecting")
        message = reconnecting ? "Starting a fresh DEX-owned inspector session after verified cleanup" : "Starting one isolated DEX-owned inspector session"
        let generation = sceneGeneration
        sendScene("connect", ["project": project.path, "url": localURL.absoluteString]) { [weak self] result in
            guard let self, self.sceneGeneration == generation else { return }; switch result {
            case .success(let value):
                guard let response = value as? [String: Any], let owned = response["owned"] as? Bool, owned,
                      let rawProxyURL = response["proxyURL"] as? String, LocalEndpoint.validated(rawProxyURL) != nil,
                      let targetID = response["browserTargetID"] as? String, !targetID.isEmpty else {
                    self.inspecting = false; self.sceneStatus = "Error"; self.sceneLastError = "The managed browser did not return a verified DEX-owned target."; self.inspectionOutput = self.sceneLastError; self.message = "Inspector setup stopped; it will not use or close an unverified browser tab."; self.disconnectScene(); return
                }
                self.inspecting = false
                self.applySceneSession(response)
                self.sceneStatus = "Awaiting scene"
                self.sceneCleanupMessage = "One DEX-owned isolated browser target and one local proxy are active"
                self.health["bridge"] = ProbeObservation(state: .disconnected, detail: "Owned inspector target is ready; waiting for a live Three.js scene")
                self.refreshScene()
            case .failure(let error):
                self.inspecting = false; self.sceneStatus = "Error"
                self.health["bridge"] = ProbeObservation(state: .stopped, detail: "DEX MCP connection failed")
                self.sceneLastError = error.localizedDescription; self.inspectionOutput = error.localizedDescription
                self.message = "Inspector setup failed. DEX will close only the isolated browser session it launched."; self.disconnectScene()
            }
        }
    }
    func reconnectScene() {
        guard !inspecting else { message = "Wait for the current inspector request to finish"; return }
        guard selected?.trusted == true, process != nil else { message = "Start the trusted project before reconnecting the inspector"; return }
        guard sceneSessionActive else { startInspectorSession(reconnecting: true); return }
        guard let project = selected, let url = LocalEndpoint.validated(serverURL.isEmpty ? project.url ?? "" : serverURL) else { message = "A verified local project URL is required to reconnect"; return }
        sceneStatus = "Reconnecting"; sceneLastError = ""; inspecting = true
        sceneCleanupMessage = "Checking the existing DEX-owned MCP session, browser target and proxy before replacement"
        sendScene("connect", ["project": project.path, "url": url.absoluteString]) { [weak self] result in
            guard let self else { return }
            self.inspecting = false
            switch result {
            case .success(let value):
                guard let response = value as? [String: Any], response["owned"] as? Bool == true,
                      let proxy = response["proxyURL"] as? String, LocalEndpoint.validated(proxy) != nil,
                      let target = response["browserTargetID"] as? String, !target.isEmpty else {
                    self.reconnectByReplacement(reason: "The existing session did not return verifiable target ownership."); return
                }
                self.applySceneSession(response)
                let reused = response["reused"] as? Bool == true
                self.sceneCleanupMessage = reused ? "Existing DEX-owned browser target and proxy recovered" : "The MCP verified and replaced its invalid owned browser session"
                self.message = reused ? "Existing inspector session recovered" : "Invalid DEX-owned session replaced after cleanup"
                self.sceneStatus = "Awaiting scene"
                self.refreshScene()
            case .failure(let error): self.reconnectByReplacement(reason: error.localizedDescription)
            }
        }
    }
    private func reconnectByReplacement(reason: String) {
        sceneLastError = "Existing inspector session could not be recovered: \(reason)"
        sceneCleanupMessage = "Closing the verified DEX-owned process group before starting a replacement"
        disconnectScene { [weak self] closed in
            guard let self else { return }
            guard closed else {
                self.sceneStatus = "Cleanup unverified"
                self.sceneLastError = "\(self.sceneLastError) DEX preserved the group because shutdown could not be verified; no duplicate session was started."
                self.message = self.sceneLastError; return
            }
            self.startInspectorSession(reconnecting: true)
        }
    }
    func openSceneBrowser() {
        guard sceneSessionActive, !sceneBrowserTargetID.isEmpty else { message = "No verified DEX-owned inspector target is available"; return }
        sendScene("activate") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.sceneLastActivityAt = Date(); self.message = "Brought the existing DEX-owned inspector tab forward; no new tab was created"
            case .failure(let error): self.sceneLastError = error.localizedDescription; self.message = "Could not activate the owned inspector tab. Reconnect to replace the verified session."
            }
        }
    }
    func refreshScene() {
        guard sceneSessionActive else { message = "Connect the inspector first; refresh never opens a browser"; return }
        guard !inspecting else { message = "A scene request is already in progress"; return }
        inspecting = true; sceneStatus = "Loading scene"; message = "Reading live scene hierarchy in the existing browser target"
        let generation = sceneGeneration
        sendScene("tree") { [weak self] result in
            guard let self, self.sceneGeneration == generation else { return }; self.inspecting = false
            switch result {
            case .success(let value):
                guard let envelope = value as? [String: Any], let root = envelope["scene"] as? [String: Any] else { self.sceneStatus = "Empty scene"; self.sceneNodes = []; return }
                let priorSelection = self.selectedScenePath
                let priorExpansion = self.expandedScenePaths
                self.sceneNodes = [SceneNode(root)]; self.sceneSnapshotProject = self.sceneSessionProject.isEmpty ? (self.selected?.name ?? "selected project") : self.sceneSessionProject
                let nodes = self.sceneNodes.flatMap(\.descendants)
                self.expandedScenePaths = Set(priorExpansion.filter { path in nodes.contains(where: { $0.path == path && !$0.children.isEmpty }) })
                if let rootPath = self.sceneNodes.first?.path { self.expandedScenePaths.insert(rootPath) }
                if nodes.contains(where: { $0.path == priorSelection && $0.canInspect }) { self.selectedScenePath = priorSelection }
                else { self.selectedScenePath = self.sceneNodes.first?.path ?? "" }
                if let session = envelope["session"] as? [String: Any] { self.applySceneSession(session) }
                self.sceneLastSuccessfulInspection = Date(); self.sceneLastError = ""
                self.sceneStatus = self.sceneNodes.isEmpty ? "Empty scene" : "Connected · scene loaded"
                self.health["bridge"] = self.sceneNodes.isEmpty
                    ? ProbeObservation(state: .disconnected, detail: "The MCP returned an empty scene")
                    : ProbeObservation(state: .connected, detail: "DEX DevTools MCP confirmed the live browser scene")
                self.inspectionOutput = "Loaded \(self.sceneNodes.first?.nodeCount ?? 0) scene nodes from \(self.sceneSnapshotProject). Each MCP response is bounded to depth 4 and 20 children per node."
                self.sceneCleanupMessage = "Live hierarchy refreshed in the same owned target; project source untouched"
                self.message = "Live scene refreshed; selection preserved when its path remained available"
                if !self.selectedScenePath.isEmpty { self.selectSceneObject(self.selectedScenePath) }
            case .failure(let error):
                self.sceneStatus = "Disconnected · cached snapshot"; self.sceneLastError = error.localizedDescription
                self.health["bridge"] = ProbeObservation(state: .disconnected, detail: "The inspector target or scene bridge stopped responding")
                self.inspectionOutput = "Scene disconnected. The last successful hierarchy remains visible; reconnect to continue inspecting.\n\(error.localizedDescription)"
                self.message = "Scene disconnected. Reconnect to continue inspecting. The existing target was not replaced."
            }
        }
    }
    func selectSceneObject(_ path: String) {
        guard sceneConnected, !inspecting, sceneSessionActive else { message = "Wait for the current scene request or reconnect first"; return }
        selectedScenePath = path
        let generation = sceneGeneration
        sendScene("details", ["path": path]) { [weak self] result in
            guard let self, self.sceneGeneration == generation, self.selectedScenePath == path else { return }
            self.sceneLastActivityAt = Date()
            switch result { case .success(let value): self.objectDetails = Self.pretty(value); self.sceneLastError = ""; case .failure(let error): self.sceneLastError = error.localizedDescription; self.objectDetails = error.localizedDescription }
        }
    }
    func previewSceneChange() {
        guard sceneConnected, !inspecting, !isPreviewMutationPending else { message = "Wait for the current scene edit to finish before applying another"; return }
        guard let value = Double(previewValue), value.isFinite, ["roughness", "metalness", "opacity", "emissiveIntensity"].contains(previewProperty) else { message = "Choose a supported finite numeric material value"; return }
        if previewProperty == "emissiveIntensity", value < 0 { message = "Emissive intensity must be zero or greater"; return }
        if ["roughness", "metalness", "opacity"].contains(previewProperty), !(0...1).contains(value) { message = "\(previewProperty) must be between 0 and 1"; return }
        let name = selectedScenePath.components(separatedBy: ".").last ?? selectedScenePath
        isPreviewMutationPending = true; inspecting = true
        let generation = sceneGeneration
        sendScene("preview", ["tool": "set_material_property", "params": ["name": name, "property": previewProperty, "value": value]]) { [weak self] result in
            guard let self, self.sceneGeneration == generation else { return }
            self.isPreviewMutationPending = false; self.inspecting = false; self.sceneLastActivityAt = Date()
            switch result {
            case .success(let response): self.sceneLastError = ""; self.message = "Temporary browser preview applied; source files unchanged. \(Self.pretty(response))"; self.loadPendingChanges()
            case .failure(let error): self.sceneLastError = error.localizedDescription; self.message = "Preview failed. Project source is unchanged. \(error.localizedDescription)"
            }
        }
    }
    func loadPendingChanges() {
        guard sceneConnected, !inspecting else { return }
        let generation = sceneGeneration
        sendScene("pending") { [weak self] result in
            guard let self, self.sceneGeneration == generation else { return }
            switch result { case .success(let value): self.pendingChanges = Self.pretty(value); case .failure(let error): self.sceneLastError = error.localizedDescription }
        }
    }
    func revertSceneChange(_ id: Int? = nil) {
        guard sceneConnected, !inspecting else { message = "Wait for the current scene request before reverting"; return }
        var args: [String: Any] = [:]; if let id { args["ids"] = [id] }
        inspecting = true; isPreviewMutationPending = true; let generation = sceneGeneration
        sendScene("revert", args) { [weak self] result in
            guard let self, self.sceneGeneration == generation else { return }
            self.inspecting = false; self.isPreviewMutationPending = false
            switch result { case .success(let value): self.sceneLastError = ""; self.message = "Temporary scene values restored. \(Self.pretty(value))"; self.loadPendingChanges(); case .failure(let error): self.sceneLastError = error.localizedDescription; self.message = "Revert failed; the scene may have disconnected. \(error.localizedDescription)" }
        }
    }
    func sendScene(_ op: String, _ args: [String: Any] = [:], completion: @escaping (Result<Any, Error>) -> Void) {
        guard let input = sceneInput else { completion(.failure(NSError(domain: "DEXScene", code: 1, userInfo: [NSLocalizedDescriptionKey: "Inspector is disconnected"]))); return }
        nextSceneCommand += 1; let id = nextSceneCommand; sceneCompletions[id] = SceneCompletion(generation: sceneGeneration, callback: completion)
        do { let data = try JSONSerialization.data(withJSONObject: ["id": id, "op": op, "args": args], options: [.fragmentsAllowed, .sortedKeys]); input.fileHandleForWriting.write(data + Data([10])) }
        catch { sceneCompletions.removeValue(forKey: id)?.callback(.failure(error)) }
    }
    private func consumeSceneOutput(_ data: Data) {
        switch sceneFramer.append(data) {
        case .oversized: failSceneOutputOverflow()
        case .lines(let lines): for line in lines {
                guard let item = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if item["event"] as? String == "ready" { if let session = item["session"] as? [String: Any] { applySceneSession(session) }; continue }
                if item["event"] as? String == "disconnected" {
                    guard let session = item["session"] as? [String: Any], session["sessionID"] as? String == sceneSessionID else { continue }
                    let detail = item["error"] as? String ?? "Inspector bridge exited unexpectedly"
                    sceneStatus = sceneSnapshotProject.isEmpty ? "Disconnected" : "Disconnected · cached snapshot"
                    sceneLastError = detail; inspectionOutput = detail
                    sceneCleanupMessage = "Bridge process exited; reconnect will verify and release only the owned browser before replacement"
                    health["bridge"] = ProbeObservation(state: .disconnected, detail: "DEX DevTools MCP process exited")
                    continue
                }
                guard let id = item["id"] as? Int, let response = sceneCompletions.removeValue(forKey: id) else { continue }
                guard response.generation == sceneGeneration else { continue }
                if item["ok"] as? Bool == true { response.callback(.success(item["result"] ?? NSNull())) }
                else { response.callback(.failure(NSError(domain: "DEXScene", code: 2, userInfo: [NSLocalizedDescriptionKey: item["error"] as? String ?? "MCP request failed"]))) }
            }
        }
    }
    private func failSceneOutputOverflow() {
        let detail = "Inspector helper sent a response line larger than 1 MiB. The session was closed to bound memory use; reconnect after updating or restarting the helper."
        sceneFramer.reset()
        sceneGeneration = UUID()
        let pending = Array(sceneCompletions.values)
        sceneCompletions.removeAll()
        sceneStatus = "Error"; sceneLastError = detail; inspectionOutput = detail; message = detail
        pending.forEach { $0.callback(.failure(NSError(domain: "DEXScene", code: 3, userInfo: [NSLocalizedDescriptionKey: detail]))) }
        disconnectScene()
    }
    func applySceneSession(_ value: [String: Any]) {
        func string(_ key: String) -> String { value[key] as? String ?? "" }
        func integer(_ key: String) -> Int32 { Int32(value[key] as? Int ?? 0) }
        func date(_ key: String) -> Date? { guard let raw = value[key] as? String else { return nil }; return ISO8601DateFormatter().date(from: raw) }
        sceneSessionID = string("sessionID").isEmpty ? sceneSessionID : string("sessionID")
        sceneSessionProject = URL(fileURLWithPath: string("projectPath")).lastPathComponent.isEmpty ? sceneSessionProject : URL(fileURLWithPath: string("projectPath")).lastPathComponent
        sceneBrowserName = string("browser").isEmpty ? sceneBrowserName : string("browser")
        sceneBrowserVersion = string("browserVersion")
        sceneBrowserPID = integer("browserPID"); sceneMCPPID = integer("mcpPID")
        sceneBrowserTargetID = string("browserTargetID"); sceneCDPPort = Int(integer("cdpPort"))
        if let raw = value["proxyURL"] as? String, LocalEndpoint.validated(raw) != nil { sceneBrowserURL = raw }
        sceneSessionStartedAt = date("sessionStartedAt") ?? sceneSessionStartedAt
        sceneLastActivityAt = date("lastActivityAt") ?? Date()
        sceneLastSuccessfulInspection = date("lastSuccessfulInspection") ?? sceneLastSuccessfulInspection
        sceneOwned = value["owned"] as? Bool == true
        if value["sceneBridgeConnected"] as? Bool == true, !sceneConnected { sceneStatus = "Connected · scene loaded" }
    }
    func clearSceneSession() {
        sceneSessionID = ""; sceneSessionProject = ""; sceneBrowserName = ""; sceneBrowserVersion = ""
        sceneBrowserPID = 0; sceneMCPPID = 0; sceneBrowserTargetID = ""; sceneCDPPort = 0
        sceneBrowserURL = ""; sceneSessionStartedAt = nil; sceneLastActivityAt = nil
        sceneOwned = false; sceneOwnedProcessGroup = 0
    }
    private func finishOwnedSceneGroupCleanup(group: Int32, completion: ((Bool) -> Void)?) {
        guard group > 0 else { completion?(true); return }
        DispatchQueue.global().async { [weak self] in
            func exists() -> Bool { Darwin.kill(-group, 0) == 0 || errno == EPERM }
            let gracefulDeadline = Date().addingTimeInterval(5)
            while exists() && Date() < gracefulDeadline { Thread.sleep(forTimeInterval: 0.1) }
            if exists() { _ = Darwin.kill(-group, SIGTERM) }
            let termDeadline = Date().addingTimeInterval(2)
            while exists() && Date() < termDeadline { Thread.sleep(forTimeInterval: 0.1) }
            if exists() { _ = Darwin.kill(-group, SIGKILL) }
            let killDeadline = Date().addingTimeInterval(2)
            while exists() && Date() < killDeadline { Thread.sleep(forTimeInterval: 0.1) }
            let closed = !exists()
            Task { @MainActor in
                guard let self else { completion?(closed); return }
                self.sceneOwnedProcessGroup = 0
                if closed {
                    self.clearSceneSession()
                    self.sceneStatus = self.sceneSnapshotProject.isEmpty ? "Disconnected" : "Disconnected · cached snapshot"
                    self.sceneCleanupMessage = "DEX-owned MCP, browser target and proxy process group closed and verified"
                    self.health["bridge"] = ProbeObservation(state: .disconnected, detail: "Inspector session is closed")
                } else {
                    self.sceneStatus = "Cleanup unverified"
                    self.sceneCleanupMessage = "DEX could not verify that its owned process group exited. No replacement session was started."
                    self.sceneLastError = self.sceneCleanupMessage
                }
                completion?(closed)
            }
        }
    }
    func disconnectScene(completion: ((Bool) -> Void)? = nil) {
        guard let task = sceneProcess else { clearSceneSession(); completion?(true); return }
        if sceneStatus == "Disconnecting" { message = "Inspector cleanup is already in progress"; completion?(false); return }
        let group = sceneOwnedProcessGroup
        guard group > 0, Darwin.getpgid(task.processIdentifier) == group else {
            task.terminate(); sceneStatus = "Cleanup unverified"; sceneLastError = "DEX lost its verified process-group identity; no group-wide cleanup was attempted."; completion?(false); return
        }
        sceneGeneration = UUID(); sceneCompletions.removeAll(); sceneFramer.reset(); inspecting = false; isPreviewMutationPending = false
        sceneStatus = "Disconnecting"; sceneCleanupMessage = "Closing only the isolated browser session launched by DEX"
        health["bridge"] = ProbeObservation(state: .disconnected, detail: "DEX scene inspector is disconnecting")
        sceneInput?.fileHandleForWriting.write(Data("{\"op\":\"close\"}\n".utf8))
        try? sceneInput?.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if task.isRunning { task.terminate() }
                self.finishOwnedSceneGroupCleanup(group: group, completion: completion)
            }
        }
    }
    private static func pretty(_ value: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return String(describing: value) }; return String(data: data, encoding: .utf8) ?? String(describing: value) }
    func cancelInspection() {
        disconnectScene(); pendingChanges = ""
        if !sceneSnapshotProject.isEmpty { sceneStatus = "Disconnecting · cached snapshot: \(sceneSnapshotProject)" }
        if sceneProcess == nil { health["bridge"] = ProbeObservation(state: .disconnected, detail: "DEX scene inspector is disconnected") }
        message = "Inspector disconnected; its browser session is closing. The last scene snapshot remains viewable."
    }
    func diagnostics() -> String {
        let tool = "~/.local/share/3d-lab"; let exists = FileManager.default.fileExists(atPath: NSString(string: tool).expandingTildeInPath)
        return "DEX 3js diagnostics\nProject: \(selected?.name ?? "None")\nProcess: \(processState)\nURL: \(serverURL.isEmpty ? "Not measured" : serverURL)\nShared toolkit: \(exists ? "Available" : "Not installed")\nCodex Desktop: \(agentStatus("codex"))\nClaude Code Desktop: \(agentStatus("claude"))\n"
    }
    func packageManagerName(at root: URL) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) { return "pnpm" }
        if fm.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) { return "yarn" }
        if fm.fileExists(atPath: root.appendingPathComponent("bun.lock").path) || fm.fileExists(atPath: root.appendingPathComponent("bun.lockb").path) { return "bun" }
        return "npm"
    }
    func agentStatus(_ client: String) -> String {
        let appID = client == "codex" ? "com.openai.codex" : "com.anthropic.claudefordesktop"
        let config = client == "codex" ? "~/.codex/config.toml" : "~/.claude.json"
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) != nil else { return "Not detected" }
        let path = NSString(string: config).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "Config unavailable" }
        let names = client == "codex" ? ["threejs_devtools", "ai_threejs_studio"] : ["threejs-devtools", "ai-threejs-studio"]
        let count = names.filter { text.contains($0) }.count
        return count == names.count ? "2 MCP registered · unverified" : "MCP incomplete · unverified"
    }
}
extension JSONEncoder { static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }
#if !DEX3JS_TESTING
@main struct DEX3jsApp: App {
    @StateObject private var store = Store()
    init() { DEXAppearance.applyToApplication() }
    var body: some Scene { WindowGroup { MainView().environmentObject(store).frame(minWidth: 980, minHeight: 660).preferredColorScheme(DEXAppearance.colorScheme).onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.cancelInspection(); store.stop() } }.windowStyle(.titleBar).commands { CommandGroup(after: .newItem) { Button("Reload Configuration") { store.reload() }.keyboardShortcut("r", modifiers: [.command, .option]) } } }
}
#endif

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var tab = "Control Center"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) { Text("DEX 3js").font(.system(size: 24, weight: .semibold)); Text("Three.js development launcher").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                statusPill("Codex", icon: "terminal", state: store.agentStatus("codex"))
                statusPill("Claude Code", icon: "chevron.left.forwardslash.chevron.right", state: store.agentStatus("claude"))
            }.padding(22)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("PROJECTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button { store.selectFolder() } label: { Image(systemName: "plus") }.help("Add project folder") }
                    TextField("Search projects", text: $store.query).textFieldStyle(.roundedBorder)
                    List(selection: Binding(get: { store.selectedID }, set: { store.selectProject($0) })) {
                        ForEach(store.visibleProjects) { p in HStack { Image(systemName: p.favorite ? "star.fill" : "cube.transparent").foregroundStyle(p.favorite ? .orange : .secondary); VStack(alignment: .leading, spacing: 2) { Text(p.name); Text(p.path).font(.caption2).lineLimit(1).foregroundStyle(.secondary) } }.tag(p.id).contextMenu { Button(p.favorite ? "Unfavorite" : "Favorite") { store.toggleFavorite(p) }; Button("Remove from launcher") { store.selectedID = p.id; store.removeSelected() } } }
                    }.listStyle(.sidebar)
                    Button { store.selectFolder() } label: { Label("Add Project", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)
                }.padding(16).frame(width: 290).background(Color(nsColor: .controlBackgroundColor))
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) { ForEach(["Control Center", "Projects", "Toolbox", "Diagnostics", "Configuration"], id: \.self) { x in Button(x) { tab = x }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8).background(tab == x ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(tab == x ? Color.accentColor : .secondary) } }.padding(.horizontal, 22).padding(.vertical, 14)
                    Divider()
                    ScrollView { VStack(alignment: .leading, spacing: 18) { Group { if tab == "Control Center" { controlCenter } else if tab == "Projects" { projectDetail } else if tab == "Toolbox" { toolbox } else if tab == "Diagnostics" { diagnostics } else { configuration } }.padding(22) }.frame(maxWidth: .infinity, alignment: .leading) }
                    Divider()
                    HStack { Circle().fill(store.processState.hasPrefix("Running") ? .green : .gray).frame(width: 8, height: 8); Text(store.processState); Spacer(); Text(store.message).foregroundStyle(.secondary).lineLimit(1) }.font(.caption).padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.refreshHealth() }
    }
    var controlCenter: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Control Center").font(.system(size: 28, weight: .semibold))
                    Text("Run your project. Inspect the scene. Know what's connected.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let project = store.selected {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).font(.headline)
                                Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            Text(store.processState).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Button("Start project") { store.start(); store.refreshHealth() }.disabled(!project.trusted || store.processState.hasPrefix("Running"))
                            Button("Stop project") { store.stop() }.disabled(!store.processState.hasPrefix("Running"))
                            Button("Open project") { store.openSelectedProject() }
                            Button("Open folder") { store.openFolder() }
                        }
                        if !project.trusted {
                            Text("To start this project, review and approve its dev script in Projects.").font(.callout).foregroundStyle(.orange)
                        }
                        if !project.actions.isEmpty {
                            Text("Museum & project views").font(.subheadline.weight(.medium))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(project.actions) { action in
                                    Button(action.name) { store.openProjectAction(action) }
                                        .buttonStyle(.bordered)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }.padding(7)
                } label: { Label("Active project", systemImage: "cube.transparent") }
            } else {
                ContentUnavailableView("Choose a project", systemImage: "folder", description: Text("Select a Three.js project in the left sidebar."))
            }
            healthPanel
            inspectorPanel
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Studio is a separate scene-authoring workspace, not an editable copy of your museum.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Start Studio") { store.studio() }
                        Button("Open Studio") { store.openStudioWeb() }.disabled(store.probe("studioWeb").state != .ready)
                        Button("Open Needle in Chrome") { store.openNeedleInChrome() }.disabled(store.selected == nil)
                    }
                    Text("Needle: enable the Chrome extension for the local site; Pro-only edits may require a license. DevTools material previews are not source edits.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(7)
            } label: { Label("Visual tools", systemImage: "slider.horizontal.3") }
        }
    }
    var healthPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Actual loopback responses — not installation guesses").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.isCheckingTools ? "Checking…" : "Refresh connections") { store.refreshHealth() }
                        .disabled(store.isCheckingTools)
                }
                ForEach(["project", "bridge", "studioAPI", "studioWeb"], id: \.self) { key in
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthTitle(key)).font(.callout.weight(.medium))
                            Text(store.probe(key).detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.probe(key).state.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(healthColor(store.probe(key).state).opacity(0.12), in: Capsule())
                    }
                    Divider()
                }
                if let checked = store.lastCheckedAt {
                    Text("Last checked: \(checked.formatted(date: .omitted, time: .standard))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(7)
        } label: { Label("Connections", systemImage: "point.3.connected.trianglepath.dotted") }
    }
    var inspectorPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                GroupBox("Inspector session manager") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(store.sceneStatus, systemImage: store.sceneConnected ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(store.sceneConnected ? .green : .secondary)
                                .accessibilityLabel("Inspector connection status: \(store.sceneStatus)")
                                .accessibilityAddTraits(.updatesFrequently)
                            Spacer()
                            Text(store.sceneSessionAge).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(store.sceneSessionActive ? "Reconnect" : "Connect") { if store.sceneSessionActive { store.reconnectScene() } else { store.inspectScene() } }
                                .disabled(store.inspecting || store.selected?.trusted != true || !store.processState.hasPrefix("Running"))
                            Button("Refresh scene") { store.refreshScene() }.disabled(!store.sceneConnected || store.inspecting)
                            Button("Open inspector") { store.openSceneBrowser() }.disabled(!store.sceneSessionActive || store.sceneBrowserTargetID.isEmpty)
                            Button("Close DEX session") { store.cancelInspection() }.disabled(!store.sceneSessionActive)
                            Button("Copy report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.inspectorDiagnosticReport(), forType: .string) }
                        }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow { Text("Project").foregroundStyle(.secondary); Text(store.sceneSessionProject.isEmpty ? (store.selected?.name ?? "None") : store.sceneSessionProject) }
                            GridRow { Text("Browser").foregroundStyle(.secondary); Text(store.sceneBrowserVersion.isEmpty ? (store.sceneBrowserName.isEmpty ? "Not active" : store.sceneBrowserName) : "\(store.sceneBrowserName) · \(store.sceneBrowserVersion)") }
                            GridRow { Text("Target / proxy").foregroundStyle(.secondary); Text(store.sceneBrowserTargetID.isEmpty ? "Not verified" : "\(store.sceneBrowserTargetID) · \(store.sceneBrowserURL)").textSelection(.enabled) }
                            GridRow { Text("Last inspection").foregroundStyle(.secondary); Text(store.sceneLastSuccessfulInspection?.formatted(date: .abbreviated, time: .standard) ?? "Not yet completed") }
                        }.font(.caption)
                        if !store.sceneCleanupMessage.isEmpty { Text(store.sceneCleanupMessage).font(.caption).foregroundStyle(.secondary) }
                        if !store.sceneLastError.isEmpty { Label(store.sceneLastError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled).accessibilityAddTraits(.updatesFrequently) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(5)
                }
                Text("Live hierarchy and object data come from the installed Three.js DevTools MCP. Preview changes live only in its browser session; they never edit project files.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Copy details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.objectDetails.isEmpty ? store.inspectionOutput : store.objectDetails, forType: .string) }.disabled(store.objectDetails.isEmpty && store.inspectionOutput.isEmpty)
                    if !store.sceneConnected { Text("Scene disconnected. Reconnect to continue inspecting.").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("SCENE HIERARCHY").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button("Expand all") { store.expandAllScene(true) }.disabled(store.sceneNodes.isEmpty); Button("Collapse") { store.expandAllScene(false) }.disabled(store.sceneNodes.isEmpty) }
                        HStack(spacing: 6) { TextField("Search objects", text: $store.sceneSearch).textFieldStyle(.roundedBorder).accessibilityLabel("Search scene objects"); Picker("Type", selection: $store.sceneTypeFilter) { ForEach(store.sceneTypes, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 120).accessibilityLabel("Filter scene object type") }
                        if store.sceneNodes.isEmpty { ContentUnavailableView(store.sceneStatus == "Error" ? "Scene unavailable" : "No scene loaded", systemImage: "square.3.layers.3d", description: Text(store.inspectionOutput.isEmpty ? "Start the project, open a browser view, and connect the inspector." : store.inspectionOutput)) }
                        else { ScrollView { LazyVStack(alignment: .leading, spacing: 2) {
                            if store.sceneSearch.isEmpty && store.sceneTypeFilter == "All" {
                                ForEach(store.sceneNodes) { SceneNodeRow(node: $0, expandedPaths: $store.expandedScenePaths) }
                            } else {
                                ForEach(store.visibleSceneMatches) { node in Button { store.selectSceneObject(node.path) } label: { VStack(alignment: .leading, spacing: 2) { Text(node.name).lineLimit(1); Text("\(node.type) · \(node.path)").font(.caption2).foregroundStyle(.secondary).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading).padding(5).background(store.selectedScenePath == node.path ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(.plain).disabled(!node.canInspect).help(node.selectionDisabledReason ?? node.summary) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6) }.accessibilityElement(children: .contain).accessibilityLabel("Live scene hierarchy").frame(minHeight: 240, maxHeight: 330).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7)) }
                    }.frame(minWidth: 260, maxWidth: 340, alignment: .leading)
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("OBJECT INSPECTOR").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(store.selectedScenePath.isEmpty ? "Select an object in the hierarchy" : store.selectedScenePath).font(.caption).textSelection(.enabled).accessibilityLabel(store.selectedScenePath.isEmpty ? "No scene object selected" : "Selected scene object: \(store.selectedScenePath)")
                        ScrollView { Text(store.objectDetails.isEmpty ? "Select an object to read its properties." : store.objectDetails).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.frame(minHeight: 180, maxHeight: 260).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                        Text("TEMPORARY MATERIAL PREVIEW").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Picker("Property", selection: $store.previewProperty) { ForEach(["roughness", "metalness", "opacity", "emissiveIntensity"], id: \.self) { Text($0).tag($0) } }
                                    .labelsHidden().accessibilityLabel("Material property").frame(width: 142)
                                TextField("Value", text: $store.previewValue).frame(width: 74).accessibilityLabel("Numeric preview value")
                                Button("Preview") { store.previewSceneChange() }.disabled(store.selectedScenePath.isEmpty || !store.sceneConnected)
                                    .accessibilityHint("Requires a selected object with a supported material and a live scene connection.")
                            }
                            HStack(spacing: 8) {
                                Button("Show pending") { store.loadPendingChanges() }.disabled(!store.sceneConnected)
                                Button("Revert all") { store.revertSceneChange() }.disabled(!store.sceneConnected)
                            }
                        }
                        if !store.pendingChanges.isEmpty { ScrollView { VStack(alignment: .leading, spacing: 5) { Text(store.pendingChanges).font(.system(size: 10, design: .monospaced)).textSelection(.enabled); ForEach(store.pendingChangeIDs, id: \.self) { id in Button("Revert change #\(id)") { store.revertSceneChange(id) }.buttonStyle(.bordered) } }.frame(maxWidth: .infinity, alignment: .leading).padding(6) }.frame(maxHeight: 90).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7)) }
                        Text("Preview requires a supported material on the selected object. Changes remain temporary in the browser and can be reverted here.").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(7)
        } label: { Label("Live scene", systemImage: "square.3.layers.3d") }
    }
    func healthTitle(_ key: String) -> String {
        switch key {
        case "project": return "Configured project URL"
        case "bridge": return "Three.js DevTools scene bridge"
        case "studioAPI": return "AI Three.js Studio API"
        case "studioWeb": return "AI Three.js Studio editor"
        default: return key
        }
    }
    func healthColor(_ state: ProbeState) -> Color {
        switch state {
        case .ready: return .green
        case .connected: return .green
        case .checking: return .blue
        case .disconnected: return .orange
        case .blocked, .stopped: return .red
        case .unknown: return .gray
        }
    }
    func statusPill(_ title: String, icon: String, state: String) -> some View { HStack(spacing: 6) { Image(systemName: icon); VStack(alignment: .leading, spacing: 1) { Text(title).font(.caption.weight(.semibold)); Text(state).font(.caption2).foregroundStyle(.secondary) } }.padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)) }
    var projectDetail: some View {
        Group { if let p = store.selected {
            HStack(alignment: .top) { VStack(alignment: .leading, spacing: 5) { Text(p.name).font(.system(size: 28, weight: .semibold)); Text(p.path).font(.callout).foregroundStyle(.secondary) }; Spacer(); Button { store.toggleFavorite(p) } label: { Image(systemName: p.favorite ? "star.fill" : "star") } }
            HStack { Label(framework(p), systemImage: "cube"); Label("Package manager: \(packageManager(p))", systemImage: "shippingbox"); Label("Three.js project", systemImage: "checkmark.circle") }.font(.caption).foregroundStyle(.secondary)
            GroupBox("Development server") { VStack(alignment: .leading, spacing: 10) { HStack { Text(store.processState); Spacer(); if !store.serverURL.isEmpty { Button("Open") { store.openURL(store.serverURL) } }; Button("Start") { store.start() }.disabled(store.processState.hasPrefix("Running")); Button("Stop") { store.stop() }.disabled(!store.processState.hasPrefix("Running")) }; if !store.serverURL.isEmpty { Text(store.serverURL).font(.system(.body, design: .monospaced)) }; if !store.processLog.isEmpty { Text(store.processLog).font(.system(.caption, design: .monospaced)).lineLimit(8).textSelection(.enabled) } }.padding(6) }
            HStack { Button("Open in Browser") { if !store.serverURL.isEmpty { store.openURL(store.serverURL) } else if let url = p.url { store.openURL(url) } }.disabled(store.serverURL.isEmpty && p.url == nil); Button("Open Folder") { store.openFolder() }; Button("Open in IDE") { store.openEditor() }; Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.serverURL, forType: .string) }.disabled(store.serverURL.isEmpty); Button("Studio") { store.studio() } }
            HStack { Button("Import profile…") { store.importProfile() }; Button("Reload dex3js.json") { store.reloadProfile() }; Button("Export dex3js.json") { store.exportProfile() } }
            GroupBox("Project actions") { VStack(alignment: .leading, spacing: 6) { if p.actions.isEmpty { Text("No project actions configured. Add named URLs to dex3js.json; examples are in the repository.").foregroundStyle(.secondary) } else { ForEach(p.actions) { action in Button(action.name) { store.openProjectAction(action) } } } }.frame(maxWidth: .infinity, alignment: .leading).padding(6) }
            Toggle("I reviewed this project's dev script and approve running it", isOn: Binding(get: { p.trusted }, set: { store.setTrust($0) })).font(.caption)
        } else { ContentUnavailableView("Select a project", systemImage: "cube.transparent", description: Text("Add an existing Three.js project with the folder picker.")); Button("Add Project") { store.selectFolder() } } }
    }
    func framework(_ p: Project) -> String { let file = URL(fileURLWithPath: p.path).appendingPathComponent("package.json"); guard let d = try? Data(contentsOf: file), let s = String(data: d, encoding: .utf8) else { return "Unknown project" }; return s.contains("@react-three/fiber") ? "React Three Fiber" : (s.contains("three") ? "Three.js" : "JavaScript project") }
    func packageManager(_ p: Project) -> String { store.packageManagerName(at: URL(fileURLWithPath: p.path)) }
    var toolbox: some View { VStack(alignment: .leading, spacing: 12) { Text("Shared Three.js toolkit").font(.title2.weight(.semibold)); Text("Statuses are based on local files and configuration. MCP connectivity is not inferred from registration.").foregroundStyle(.secondary); ForEach(toolRows, id: \.name) { row in HStack { VStack(alignment: .leading, spacing: 3) { Text(row.name).fontWeight(.medium); Text(row.kind).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(row.state).font(.caption).padding(.horizontal, 9).padding(.vertical, 5).background(row.state == "Installed" || row.state == "Enabled" ? Color.green.opacity(0.12) : Color.gray.opacity(0.12), in: Capsule()) }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8)) } } }
    var toolRows: [(name:String,kind:String,state:String)] { [("Three.js DevTools MCP","MCP server","Installed · 0.5.0"),("Needle Inspector","Browser extension","Enabled · 2.9.0"),("Official Three.js DevTools","Browser development tool","Unverified"),("Chrome DevTools MCP","MCP server","Not installed"),("Spector.js MCP","MCP server","Not installed"),("Playwright CLI","Command-line tool","Unverified"),("Blender Lab MCP","MCP server","Not installed"),("glTF Transform","Asset pipeline","Unverified"),("glTF Validator","Asset validator","Unverified"),("AI Three.js Studio","Standalone app + MCP","Installed · fa2f5eb"),("Tweakpane","Project library","Not installed globally"),("Theatre.js","Project library","Not installed globally"),("Triplex","Project authoring tool","Unverified"),("Postprocessing","Project library","Not installed globally"),("three-mesh-bvh","Project library","Not installed globally")] }
    var diagnostics: some View { VStack(alignment: .leading, spacing: 12) { Text("Diagnostics").font(.title2.weight(.semibold)); Text(store.diagnostics()).font(.system(.body, design: .monospaced)).textSelection(.enabled); HStack { Button("Copy sanitized report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.diagnostics(), forType: .string) }; Button("Open shared Studio") { store.studio() }; Button("Reload configuration") { store.reload() } } } }
    var configuration: some View { VStack(alignment: .leading, spacing: 12) { Text("Configuration").font(.title2.weight(.semibold)); Text("Settings: ~/Library/Application Support/DEX 3js/settings.json"); Text("Configuration is versioned JSON data, written atomically with a last known-good backup. It is not shell code.").foregroundStyle(.secondary); Text("Import and export project profiles as dex3js.json. External profile edits take effect with Reload dex3js.json; external settings edits take effect with Reload from disk."); Button("Open settings folder") { NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/Library/Application Support/DEX 3js").expandingTildeInPath)) }; Button("Reload from disk") { store.reload() }; Button("Export settings") { let panel = NSSavePanel(); panel.nameFieldStringValue = "dex3js-settings.json"; if panel.runModal() == .OK, let url = panel.url, let d = try? JSONEncoder.pretty.encode(store.settings) { try? d.write(to: url, options: .atomic) } } } }
}

struct SceneNodeRow: View {
    @EnvironmentObject var store: Store
    let node: SceneNode
    @Binding var expandedPaths: Set<String>
    init(node: SceneNode, expandedPaths: Binding<Set<String>>) { self.node = node; _expandedPaths = expandedPaths }
    private var isExpanded: Binding<Bool> { Binding(get: { expandedPaths.contains(node.path) }, set: { value in if value { expandedPaths.insert(node.path) } else { expandedPaths.remove(node.path) } }) }
    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                LazyVStack(alignment: .leading, spacing: 2) { ForEach(node.children) { child in SceneNodeRow(node: child, expandedPaths: $expandedPaths).environmentObject(store) } }
            } label: { row }
        }
    }
    private var row: some View {
        Button { store.selectSceneObject(node.path) } label: {
            HStack(spacing: 6) {
                Image(systemName: node.type.contains("Light") ? "lightbulb" : node.type == "Scene" ? "square.3.layers.3d" : "cube")
                    .foregroundStyle(.secondary).frame(width: 14)
                Text(node.name).lineLimit(1)
                Text(node.type).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let reported = node.reportedChildCount, reported > node.children.count {
                    Text("showing \(node.children.count) of \(reported)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 2).contentShape(Rectangle())
                .background(store.selectedScenePath == node.path ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!node.canInspect)
        .accessibilityLabel(node.canInspect ? "\(node.name), \(node.type)" : "\(node.name). \(node.selectionDisabledReason ?? "Cannot inspect object.")")
        .help(node.canInspect ? node.summary : (node.selectionDisabledReason ?? "Cannot inspect object."))
    }
}
