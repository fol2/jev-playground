// Jev fishing control panel: start and stop the fishing loop, set its goal, and watch progress live.
// Native SwiftUI, local only. Reads the runs/ logs the runner writes. It sends start and stop to the fishing
// agent (FishingAgent.swift) through runs/001_wow_fishing/control/, so the panel itself needs no Screen
// Recording or Accessibility permission and survives rebuilds.
//   sh experiments/001_wow_fishing/control/build_app.sh   (builds the .app and opens it)
//   open JevFishingControl.app --args -root /path/to/jev-playground
import AppKit
import Charts
import SwiftUI

// MARK: - One cast, as the runner recorded it

struct Cast: Identifiable, Hashable {
    let id: String          // run_path, or session + number
    let at: Date
    let session: String
    let outcome: String     // caught, no_bite, no_float, false_reel, other
    let fish: String?
    let skill: Int?
    let reel: String?       // F8 or cursor
}

enum Outcome {
    static let order = ["caught", "no_bite", "no_float", "false_reel", "other"]
    static func label(_ o: String) -> String {
        ["caught": "釣到", "no_bite": "冇上釣", "no_float": "搵唔到浮標", "false_reel": "誤收線"][o] ?? "其他"
    }
    static func color(_ o: String) -> Color {
        ["caught": .green, "no_bite": .gray, "no_float": .orange, "false_reel": .red][o] ?? .secondary
    }
}

// MARK: - Reading the runs/ folder

final class RunLog {
    let root: URL
    private var castCache: [String: Cast] = [:]   // finished casts never change
    init(root: URL) { self.root = root }

    private func json(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
    private func events(_ runPath: String) -> [[String: Any]] {
        guard let text = try? String(contentsOfFile: runPath + "/events.jsonl", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }
    static func skill(in line: String) -> Int? {
        guard let r = line.range(of: #"Fishing has increased [ti]o (\d+)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(line[r].split(separator: " ").last!.filter(\.isNumber))
    }

    private func cast(from c: [String: Any], session: String, start: Date) -> Cast {
        let runPath = c["run_path"] as? String
        let key = runPath ?? "\(session)#\(c["number"] ?? 0)"
        if let cached = castCache[key] { return cached }
        let ev = runPath.map(events) ?? []
        let names = Set(ev.compactMap { $0["event"] as? String })
        let o = c["outcome"] as? String ?? "", native = c["native_outcome"] as? String ?? ""
        let outcome: String
        if o == "loot_collected" { outcome = "caught" }
        else if names.contains("right_click") || o == "retrieval_unverified" { outcome = "false_reel" }
        else if ["stopped_no_visible_float", "stopped_target_lost"].contains(native) { outcome = "no_float" }
        else if o == "timed_out_without_click" { outcome = "no_bite" }
        else { outcome = "other" }
        let skill = ev.flatMap { ($0["chat_after_ocr"] as? [String]) ?? [] }.compactMap(Self.skill).max()
        var fish: String?
        if let item = c["item"] as? String, let a = item.firstIndex(where: { $0 == "［" || $0 == "[" }),
           let b = item.lastIndex(where: { $0 == "］" || $0 == "]" }), a < b {
            fish = String(item[item.index(after: a)..<b]).trimmingCharacters(in: .whitespaces)
        }
        let reel = names.contains("interact_key") ? "F8" : names.contains("right_click") ? "游標" : nil
        let made = Cast(id: key, at: start.addingTimeInterval(c["elapsed_seconds"] as? Double ?? 0),
                        session: session, outcome: outcome, fish: fish, skill: skill, reel: reel)
        if runPath != nil { castCache[key] = made }
        return made
    }

    /// Every cast from the last two days of Test A runs, oldest first.
    func casts(since: Date = Date().addingTimeInterval(-2 * 86400)) -> [Cast] {
        let dir = root.appendingPathComponent("runs/001_wow_fishing")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        var out: [Cast] = []
        for name in names where name.hasPrefix("test_a_") {
            guard let s = json(dir.appendingPathComponent(name + "/summary.json")),
                  let startText = s["started_at_utc"] as? String,
                  let start = iso.date(from: startText) ?? iso2.date(from: startText), start > since,
                  let cycles = s["cycles"] as? [[String: Any]] else { continue }
            out += cycles.map { cast(from: $0, session: name, start: start) }
        }
        // The running session has no summary yet: its runner prints each cast as a JSON line.
        if let text = try? String(contentsOf: dir.appendingPathComponent("control/session.log"), encoding: .utf8),
           let results = text.split(separator: "\n").first(where: { $0.hasPrefix("Test A") }),
           let path = results.components(separatedBy: "results: ").last,
           !FileManager.default.fileExists(atPath: path + "/summary.json") {
            let name = (path as NSString).lastPathComponent
            let stamp = name.split(separator: "_").dropFirst(2).first.map(String.init) ?? ""
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; f.timeZone = TimeZone(identifier: "UTC")
            let start = f.date(from: stamp) ?? Date()
            for line in text.split(separator: "\n") where line.hasPrefix("{\"number\"") {
                if let c = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                    out.append(cast(from: c, session: name, start: start))
                }
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    /// One agent log line, with the runner's JSON made readable.
    static func shorten(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let time = parts.first.flatMap { ISO8601DateFormatter().date(from: $0) }
            .map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? ""
        let body = parts.count > 1 ? parts[1] : line
        guard let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return "\(time)  \(body)" }
        if let n = obj["number"] { return "\(time)  拋竿 \(n)：\(Outcome.label(Self.outcomeKey(obj)))\((obj["item"] as? String).map { " " + $0 } ?? "")" }
        if let s = obj["status"] { return "\(time)  結果：\(s)，釣到 \(obj["verified_loot_cycles"] ?? 0)" }
        return "\(time)  \(body)"
    }
    static func outcomeKey(_ c: [String: Any]) -> String {
        switch c["outcome"] as? String ?? "" {
        case "loot_collected": return "caught"
        case "retrieval_unverified": return "false_reel"
        case "timed_out_without_click": return "no_bite"
        case "target_unconfirmed": return "no_float"
        default: return "other"
        }
    }

    /// The newest picture of the water: the latest kept frame, else the latest acquired image.
    func latestFrame() -> NSImage? {
        let dir = root.appendingPathComponent("runs/001_wow_fishing")
        let fm = FileManager.default
        let lives = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("live_") }.sorted().suffix(3).reversed()
        for live in lives {
            let base = dir.appendingPathComponent(live)
            if let frames = try? fm.contentsOfDirectory(atPath: base.appendingPathComponent("frames").path),
               let last = frames.filter({ $0.hasSuffix(".jpg") }).sorted().last,
               let img = NSImage(contentsOf: base.appendingPathComponent("frames/" + last)) { return img }
            for name in ["acquired.jpg", "before.jpg"] {
                if let img = NSImage(contentsOf: base.appendingPathComponent(name)) { return img }
            }
        }
        return nil
    }
}

// MARK: - Talking to the fishing agent

struct AgentStatus: Codable { var state: String; var session: Int; var message: String; var agentPID: Int32; var updated: Date }

@MainActor
final class Controller: ObservableObject {
    @Published var casts: [Cast] = []
    @Published var frame: NSImage?
    @Published var agent: AgentStatus?
    @Published var log: [String] = []
    @Published var targetSkill = 150
    @Published var sessionSeconds = 600
    @Published var useInteractKey = true
    @Published var syncing = false

    let root: URL
    let controlDir: URL
    private let runLog: RunLog
    private var timer: Timer?

    init(root: URL) {
        self.root = root
        controlDir = root.appendingPathComponent("runs/001_wow_fishing/control")
        runLog = RunLog(root: root)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    var skill: Int? { casts.compactMap(\.skill).max() }
    var caught: Int { casts.filter { $0.outcome == "caught" }.count }
    var falseReels: Int { casts.filter { $0.outcome == "false_reel" }.count }
    var rate: Double? { casts.isEmpty ? nil : Double(caught) / Double(casts.count) }
    /// The agent writes its status every second; older than 5 s means it is not running.
    var agentAlive: Bool { agent.map { Date().timeIntervalSince($0.updated) < 5 } ?? false }
    var running: Bool { agentAlive && agent?.state != "idle" }
    var startCommand: String { "/tmp/jev-fishing-agent \(root.path)" }

    func refresh() {
        let log = runLog, dir = controlDir
        Task.detached {
            let c = log.casts(), f = log.latestFrame()
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            let st = (try? Data(contentsOf: dir.appendingPathComponent("status.json"))).flatMap { try? dec.decode(AgentStatus.self, from: $0) }
            let lines = ((try? String(contentsOf: dir.appendingPathComponent("agent.log"), encoding: .utf8)) ?? "")
                .split(separator: "\n").suffix(120).reversed().map { RunLog.shorten(String($0)) }
            await MainActor.run { self.casts = c; self.frame = f; self.agent = st; self.log = lines }
        }
    }

    private func send(_ action: String) {
        let command: [String: Any] = ["id": Int(Date().timeIntervalSince1970 * 1000), "action": action,
                                      "target": targetSkill, "seconds": sessionSeconds, "interact": useInteractKey]
        if let data = try? JSONSerialization.data(withJSONObject: command) {
            try? data.write(to: controlDir.appendingPathComponent("command.json"), options: .atomic)
        }
        refresh()
    }
    func start() { send("start") }
    /// The agent stops after the current cast: the runner never leaves a key held.
    func stop() { send("stop") }

    func syncNAS() {
        guard !syncing else { return }
        syncing = true
        let root = root
        Task.detached {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [root.appendingPathComponent("experiments/001_wow_fishing/sync_recordings.sh").path]
            p.currentDirectoryURL = root; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            await MainActor.run { self.syncing = false; self.refresh() }
        }
    }
}

// MARK: - Views

struct Tile: View {
    let title: String, value: String, note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .regular, design: .serif)).monospacedDigit()
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SessionBar: Identifiable { let id = UUID(); let session: String; let start: Date; let outcome: String; let count: Int }

struct ContentView: View {
    @ObservedObject var c: Controller
    private let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d/M HH:mm"; return f }()

    var sessionBars: [SessionBar] {
        let bySession = Dictionary(grouping: c.casts, by: \.session)
        return bySession.flatMap { session, casts in
            let start = casts.map(\.at).min() ?? .distantPast
            return Outcome.order.compactMap { o in
                let n = casts.filter { $0.outcome == o }.count
                return n > 0 ? SessionBar(session: session, start: start, outcome: o, count: n) : nil
            }
        }.sorted { $0.start < $1.start }
    }

    var body: some View {
        HSplitView {
            controls.frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Tile(title: "釣魚技能", value: c.skill.map(String.init) ?? "—", note: "目標 \(c.targetSkill)")
                        Tile(title: "釣到魚", value: String(c.caught), note: "\(c.casts.count) 次拋竿")
                        Tile(title: "成功率", value: c.rate.map { String(format: "%.0f%%", $0 * 100) } ?? "—", note: "釣到 ÷ 拋竿")
                        Tile(title: "誤收線", value: String(c.falseReels), note: "收咗線但冇魚")
                    }
                    GroupBox("技能升級曲線") {
                        Chart {
                            ForEach(c.casts.filter { $0.skill != nil }) { cast in
                                LineMark(x: .value("時間", cast.at), y: .value("技能", cast.skill!)).interpolationMethod(.linear)
                            }
                            RuleMark(y: .value("目標", c.targetSkill)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.secondary)
                        }
                        .chartYScale(domain: 0...max(150, c.targetSkill))
                        .frame(height: 200)
                    }
                    GroupBox("每節結果") {
                        Chart(sessionBars) { bar in
                            BarMark(x: .value("節", time.string(from: bar.start)), y: .value("次數", bar.count))
                                .foregroundStyle(by: .value("結果", Outcome.label(bar.outcome)))
                        }
                        .chartForegroundStyleScale(domain: Outcome.order.map(Outcome.label), range: Outcome.order.map(Outcome.color))
                        .frame(height: 200)
                    }
                    GroupBox("最近 30 次拋竿") {
                        Table(Array(c.casts.suffix(30).reversed())) {
                            TableColumn("時間") { Text(time.string(from: $0.at)).monospacedDigit() }.width(90)
                            TableColumn("結果") { Text(Outcome.label($0.outcome)).foregroundStyle(Outcome.color($0.outcome)) }.width(90)
                            TableColumn("魚") { Text($0.fish ?? "") }
                            TableColumn("技能") { Text($0.skill.map(String.init) ?? "").monospacedDigit() }.width(50)
                            TableColumn("收線") { Text($0.reel ?? "") }.width(50)
                        }
                        .frame(height: 260)
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 520)
        }
        .frame(minWidth: 860, minHeight: 640)
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(!c.agentAlive ? .red : c.running ? .green : .secondary).frame(width: 10, height: 10)
                Text(!c.agentAlive ? "釣魚 agent 未開" : c.agent?.state == "stopping" ? "停緊（等呢下拋竿完）"
                     : c.running ? "第 \(c.agent?.session ?? 0) 節跑緊" : "停咗").font(.headline)
            }
            if !c.agentAlive {
                VStack(alignment: .leading, spacing: 6) {
                    Text("喺 Terminal 行呢句開 agent（Terminal 已經有螢幕錄影同輔助使用權限）：").font(.caption).foregroundStyle(.secondary)
                    Text(c.startCommand).font(.caption.monospaced()).textSelection(.enabled)
                        .padding(6).background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    Button("複製指令") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(c.startCommand, forType: .string) }
                }
            }
            Stepper("目標技能：\(c.targetSkill)", value: $c.targetSkill, in: 1...450, step: 5).disabled(c.running)
            Stepper("每節：\(c.sessionSeconds / 60) 分鐘", value: $c.sessionSeconds, in: 60...1800, step: 60).disabled(c.running)
            Toggle("收線用 F8 Interact 鍵（唔郁游標）", isOn: $c.useInteractKey).disabled(c.running)
            HStack {
                Button { c.start() } label: { Label("開始", systemImage: "play.fill") }
                    .keyboardShortcut(.return).disabled(!c.agentAlive || c.running)
                Button(role: .destructive) { c.stop() } label: { Label("停止", systemImage: "stop.fill") }
                    .disabled(!c.running || c.agent?.state == "stopping")
            }
            Button { c.syncNAS() } label: { Label(c.syncing ? "同步緊…" : "同步去 NAS", systemImage: "externaldrive") }
                .disabled(c.syncing || c.running)
            GroupBox("Jev 見到嘅水面") {
                if let f = c.frame { Image(nsImage: f).resizable().aspectRatio(contentMode: .fit) }
                else { Text("未有畫面").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80) }
            }
            GroupBox("紀錄") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(c.log.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 120)
            }
        }
        .padding(16)
    }
}

@main
struct FishingControlApp: App {
    @StateObject private var controller: Controller
    init() {
        // "-root /path" (AppKit reads it into UserDefaults). A bare path argument would be taken as a
        // document to open, and SwiftUI then opens no window.
        let root = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "root") ?? FileManager.default.currentDirectoryPath)
        _controller = StateObject(wrappedValue: Controller(root: root))
    }
    var body: some Scene {
        WindowGroup("Jev 釣魚控制台") { ContentView(c: controller) }
    }
}
