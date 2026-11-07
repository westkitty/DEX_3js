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
    private var inspectionProcess: Process?
    private var inspectionPipe: Pipe?
    private var inspectionProject = ""
    private var probeSequence = UUID()
    private var process: Process?
    private var logPipe: Pipe?
    private let file: URL
    private let lastGood: URL
    private let processRecord: URL
    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DEX 3js", isDirectory: true)
        file = dir.appendingPathComponent("settings.json"); lastGood = dir.appendingPathComponent("settings.last-good.json"); processRecord = dir.appendingPathComponent("process.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        for localFile in [file, lastGood, processRecord] where FileManager.default.fileExists(atPath: localFile.path) { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localFile.path) }
        if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(Settings.self, from: data), decoded.version == 1 { settings = decoded }
        else if let data = try? Data(contentsOf: lastGood), let decoded = try? JSONDecoder().decode(Settings.self, from: data) { settings = decoded; message = "Recovered last known-good settings" }
        else { settings = Settings() }
        selectedID = settings.projects.first?.id
    }
    var selected: Project? { settings.projects.first { $0.id == selectedID } }
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
    func removeSelected() { guard let p = selected else { return }; guard process == nil else { message = "Stop the managed project before removing it"; return }; settings.projects.removeAll { $0.id == p.id }; selectedID = settings.projects.first?.id; serverURL = ""; processLog = ""; processState = "Stopped"; save() }
    func selectProject(_ id: UUID?) {
        guard process == nil || id == selectedID else { message = "Stop the managed project before switching projects"; return }
        guard !inspecting || id == selectedID else { message = "Finish or cancel scene inspection before switching projects"; return }
        if selectedID != id {
            selectedID = id; serverURL = ""; processLog = ""; processState = "Stopped"
            probeSequence = UUID(); health = [:]; lastCheckedAt = nil
            inspectionOutput = ""; inspectionProject = ""
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
        guard process == nil else { message = "A managed project is already running"; return }
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
            Task { @MainActor in self?.processLog = String((self?.processLog ?? "") + text.suffix(3000)); if let match = text.range(of: #"https?://(?:localhost|127\.0\.0\.1):\d+[^\s]*"#, options: .regularExpression) { self?.serverURL = String(text[match]) } }
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
    func stop() { guard let p = process else { message = "No DEX-owned project process"; return }; let ownedGroup = p.processIdentifier; if Darwin.kill(-ownedGroup, SIGTERM) != 0 { p.terminate() }; processState = "Stopping…"; message = "Sent graceful stop to DEX-owned process group"; DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if Darwin.kill(-ownedGroup, 0) == 0 { _ = Darwin.kill(-ownedGroup, SIGKILL) } } }
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
            self.health = resolved
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
        NSWorkspace.shared.open([target], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        message = "Requested Chrome opening; enable Needle Inspector from its extension toolbar"
    }
    func inspectScene() {
        guard !inspecting else { message = "An inspection is already running"; return }
        guard let project = selected, project.trusted else {
            message = "Select a trusted project before launching its inspector"; return
        }
        guard FileManager.default.fileExists(atPath: URL(fileURLWithPath: project.path).appendingPathComponent("package.json").path) else {
            message = "Project package.json is missing"; return
        }
        let lab = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/3d-lab")
        guard FileManager.default.isExecutableFile(atPath: lab.path) else {
            message = "Shared 3d-lab inspector is missing"; return
        }
        let task = Process()
        task.executableURL = lab
        task.arguments = ["inspect", "--project", project.path]
        task.currentDirectoryURL = URL(fileURLWithPath: project.path)
        task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        inspectionPipe = pipe
        inspectionOutput = "Connecting to real Three.js scene…\n"
        inspectionProject = project.path
        inspecting = true
        let expectedPath = project.path
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let string = String(data: chunk, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self, self.inspectionProject == expectedPath else { return }
                self.inspectionOutput = String((self.inspectionOutput + string).suffix(24000))
            }
        }
        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.inspectionPipe?.fileHandleForReading.readabilityHandler = nil
                self.inspectionPipe = nil
                self.inspectionProcess = nil
                self.inspecting = false
                if process.terminationStatus == 0 {
                    self.message = "Scene inspection returned; source files untouched"
                } else {
                    self.message = "Scene inspection stopped or failed (exit \(process.terminationStatus)); see output"
                }
            }
        }
        do {
            try task.run()
            inspectionProcess = task
            message = "Inspecting live project scene"
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            inspectionPipe = nil
            inspecting = false
            inspectionProcess = nil
            inspectionOutput += "Failed to start: \(error.localizedDescription)"
            message = "Scene inspector could not start"
        }
    }
    func cancelInspection() {
        guard let current = inspectionProcess, current.isRunning else { return }
        let pid = current.processIdentifier
        // Signal the launcher-owned process group only if the OS confirms ownership.
        if Darwin.getpgid(pid) == pid {
            _ = Darwin.kill(-pid, SIGTERM)
        } else {
            current.terminate()
        }
        message = "Cancel requested for the selected inspection process"
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

@main struct DEX3jsApp: App {
    @StateObject private var store = Store()
    var body: some Scene { WindowGroup { MainView().environmentObject(store).frame(minWidth: 980, minHeight: 660).preferredColorScheme(.light).onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.cancelInspection(); store.stop() } }.windowStyle(.titleBar).commands { CommandGroup(after: .newItem) { Button("Reload Configuration") { store.reload() }.keyboardShortcut("r", modifiers: [.command, .option]) } } }
}

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
                Text("Read the actual Three.js scene tree through the installed DevTools MCP. This check does not change the project source.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(store.inspecting ? "Inspecting…" : "Inspect live scene") { store.inspectScene() }
                        .disabled(store.inspecting || store.selected == nil)
                    if store.inspecting {
                        Button("Cancel inspection") { store.cancelInspection() }
                    }
                    if !store.inspectionOutput.isEmpty {
                        Button("Copy output") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.inspectionOutput, forType: .string)
                        }
                    }
                }
                if !store.inspectionOutput.isEmpty {
                    ScrollView {
                        Text(store.inspectionOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 130, maxHeight: 310)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("No inspection recorded this session. Start the project, then choose Inspect live scene.")
                        .font(.caption).foregroundStyle(.secondary)
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
