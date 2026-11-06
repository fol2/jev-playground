// Jev fishing agent: runs the fishing loop on the panel's commands. It needs Screen Recording and
// Accessibility, so start it from a context that already has them (Terminal, or the agent's shell);
// the panel then needs no permissions and can be rebuilt freely.
//   swiftc -parse-as-library -O experiments/001_wow_fishing/control/FishingAgent.swift -o /tmp/jev-fishing-agent
//   /tmp/jev-fishing-agent /path/to/jev-playground
// Files under runs/001_wow_fishing/control/: command.json (panel writes), status.json and agent.log (agent writes).
import Foundation

struct Command: Codable { var id: Int; var action: String; var target: Int?; var seconds: Int?; var interact: Bool? }
struct Status: Codable {
    var state: String          // idle, running, stopping
    var session: Int
    var target: Int
    var seconds: Int
    var interact: Bool
    var message: String
    var commandID: Int
    var agentPID: Int32
    var updated: Date
}

@main
struct FishingAgent {
    static func main() async {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let agent = Agent(root: root)
        await agent.run()
    }
}

actor Agent {
    let dir: URL
    let root: URL
    var status: Status
    var runner: Process?
    var stopRequested = false

    init(root: URL) {
        self.root = root
        dir = root.appendingPathComponent("runs/001_wow_fishing/control")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        status = Status(state: "idle", session: 0, target: 150, seconds: 600, interact: true, message: "agent started",
                        commandID: 0, agentPID: ProcessInfo.processInfo.processIdentifier, updated: Date())
    }

    func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let url = dir.appendingPathComponent("agent.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data("\(stamp) \(line)\n".utf8)); try? h.close() }
    }

    func write() {
        status.updated = Date()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(status) { try? data.write(to: dir.appendingPathComponent("status.json"), options: .atomic) }
    }

    func readCommand() -> Command? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("command.json")) else { return nil }
        return try? JSONDecoder().decode(Command.self, from: data)
    }

    func run() async {
        // One agent at a time: a newer command id is never handled twice, and a second agent exits.
        let lock = dir.appendingPathComponent("agent.pid")
        if let text = try? String(contentsOf: lock, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid != ProcessInfo.processInfo.processIdentifier, kill(pid, 0) == 0 {
            print("Another fishing agent is running (pid \(pid))."); exit(1)
        }
        try? String(ProcessInfo.processInfo.processIdentifier).write(to: lock, atomically: true, encoding: .utf8)
        // Commands written before this agent started are not run.
        status.commandID = readCommand()?.id ?? 0
        log("agent started, pid \(ProcessInfo.processInfo.processIdentifier)")
        write()
        while true {
            if let c = readCommand(), c.id > status.commandID {
                status.commandID = c.id
                await handle(c)
            }
            write()   // heartbeat: the panel treats a stale status as no agent
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func handle(_ c: Command) async {
        switch c.action {
        case "start" where status.state == "idle":
            status.target = c.target ?? 150; status.seconds = c.seconds ?? 600; status.interact = c.interact ?? true
            status.state = "running"; stopRequested = false
            log("start: target \(status.target), session \(status.seconds) s, reel \(status.interact ? "F8" : "cursor")")
            Task { await self.loop() }
        case "stop" where status.state == "running":
            stopRequested = true; status.state = "stopping"; status.message = "stopping after this cast"
            log("stop requested")
            runner?.interrupt()   // the runner finishes an in-flight cast rather than leave a key held
        default:
            log("ignored \(c.action) while \(status.state)")
        }
        write()
    }

    func loop() async {
        var reviewStops = 0
        for session in 1...60 {
            if stopRequested { break }
            status.session = session; status.message = "session \(session) running"; write()
            let last = await runSession()
            log("session \(session): \(last)")
            status.message = "session \(session): \(last.prefix(160))"
            if last.contains("goal_reached") { log("goal reached"); break }
            if last.contains("pre_go_failed") || last.contains("Stopped") || last.contains("interrupted") { break }
            reviewStops = last.contains("stopped_for_review") ? reviewStops + 1 : 0
            if reviewStops >= 6 { log("six review stops in a row"); break }
        }
        runner = nil; status.state = "idle"; write()
        // Recordings go to the NAS after each run (the script frees local frames only when the NAS has them).
        let sync = Process(); sync.executableURL = URL(fileURLWithPath: "/bin/sh")
        sync.arguments = [root.appendingPathComponent("experiments/001_wow_fishing/sync_recordings.sh").path]
        sync.currentDirectoryURL = root; sync.standardOutput = FileHandle.nullDevice; sync.standardError = FileHandle.nullDevice
        try? sync.run()
    }

    func setRunner(_ p: Process?) { runner = p }

    func runSession() async -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-di", "/tmp/jev-fishing-run", "--background", "--seconds", String(status.seconds), "--until-skill", String(status.target)]
        p.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["JEV_LOCATE"] = "1"; env["JEV_REEL"] = status.interact ? "interact" : nil
        p.environment = env
        let out = root.appendingPathComponent("runs/001_wow_fishing/control/session.log")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: out) else { return "Stopped: cannot write session.log" }
        p.standardOutput = handle; p.standardError = handle
        do { try p.run() } catch { return "Stopped: \(error.localizedDescription)" }
        runner = p
        while p.isRunning { try? await Task.sleep(for: .milliseconds(500)) }
        try? handle.close()
        let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") { log(String(line)) }
        return text.split(separator: "\n").last.map(String.init) ?? "no output"
    }
}
