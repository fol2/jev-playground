// Jev fishing control panel: start and stop the fishing loop, set its goal, and watch progress live.
// Native SwiftUI, local only. Reads the runs/ logs the runner writes; launches the same runner binary.
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
        return out.sorted { $0.at < $1.at }
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

// MARK: - The loop the panel runs

@MainActor
final class Controller: ObservableObject {
    @Published var casts: [Cast] = []
    @Published var frame: NSImage?
    @Published var running = false          // this panel's loop
    @Published var externalRunner = false   // a runner started elsewhere (a shell loop)
    @Published var status = "停咗"
    @Published var log: [String] = []
    @Published var targetSkill = 150
    @Published var sessionSeconds = 600
    @Published var useInteractKey = true
    @Published var syncing = false

    let root: URL
    private let runLog: RunLog
    private var process: Process?
    private var stopRequested = false
    private var timer: Timer?

    init(root: URL) {
        self.root = root
        runLog = RunLog(root: root)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    var skill: Int? { casts.compactMap(\.skill).max() }
    var caught: Int { casts.filter { $0.outcome == "caught" }.count }
    var falseReels: Int { casts.filter { $0.outcome == "false_reel" }.count }
    var rate: Double? { casts.isEmpty ? nil : Double(caught) / Double(casts.count) }

    func refresh() {
        let log = runLog
        Task.detached {
            let c = log.casts(), f = log.latestFrame()
            let ext = Self.runnerRunning()
            await MainActor.run { self.casts = c; self.frame = f; self.externalRunner = ext && !self.running }
        }
    }

    nonisolated static func runnerRunning() -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-f", "jev-fishing-run"]
        p.standardOutput = Pipe(); try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func note(_ line: String) {
        let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.insert("\(t)  \(line)", at: 0); if log.count > 200 { log.removeLast(log.count - 200) }
    }

    func start() {
        guard !running, !externalRunner else { return }
        running = true; stopRequested = false
        note("開始：目標技能 \(targetSkill)，每節 \(sessionSeconds) 秒，收線用 \(useInteractKey ? "F8 鍵" : "游標")")
        Task { await loop() }
    }

    /// Stops after the current cast: the runner finishes an in-flight cast rather than leave a key held.
    func stop() {
        stopRequested = true; status = "停緊（等呢下拋竿完）"
        process?.interrupt()
        note("要求停止")
    }

    private func loop() async {
        var reviewStops = 0
        for session in 1...60 {
            if stopRequested { break }
            if let s = skill, s >= targetSkill { note("已經到目標技能 \(s)"); break }
            status = "第 \(session) 節跑緊"
            let result = await runSession()
            note("第 \(session) 節：\(result)")
            refresh()
            if result.contains("goal_reached") { note("到咗目標技能"); break }
            if result.contains("pre_go_failed") || result.contains("Stopped") { note("準備失敗，停低等你睇"); break }
            reviewStops = result.contains("stopped_for_review") ? reviewStops + 1 : 0
            if reviewStops >= 6 { note("連續 6 節要覆核，停低"); break }
        }
        running = false; process = nil; status = "停咗"
    }

    private func runSession() async -> String {
        await withCheckedContinuation { (done: CheckedContinuation<String, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-di", "/tmp/jev-fishing-run", "--background", "--seconds", String(sessionSeconds), "--until-skill", String(targetSkill)]
            p.currentDirectoryURL = root
            var env = ProcessInfo.processInfo.environment
            env["JEV_LOCATE"] = "1"; env["JEV_REEL"] = useInteractKey ? "interact" : nil
            p.environment = env
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            final class Last: @unchecked Sendable { var line = "" }
            let last = Last()
            pipe.fileHandleForReading.readabilityHandler = { h in
                guard let text = String(data: h.availableData, encoding: .utf8), !text.isEmpty else { return }
                for line in text.split(separator: "\n") {
                    last.line = String(line)
                    let s = String(line)
                    Task { @MainActor in self.note(Self.shorten(s)) }
                }
            }
            p.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                done.resume(returning: last.line)
            }
            do { try p.run(); Task { @MainActor in self.process = p } }
            catch { done.resume(returning: "Stopped: \(error.localizedDescription)") }
        }
    }

    nonisolated static func shorten(_ line: String) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return line }
        if let n = obj["number"] { return "拋竿 \(n)：\(obj["outcome"] ?? "")\((obj["item"] as? String).map { " " + $0 } ?? "")" }
        if let s = obj["status"] { return "結果：\(s)，釣到 \(obj["verified_loot_cycles"] ?? 0)" }
        return line
    }

    func syncNAS() {
        guard !syncing else { return }
        syncing = true; note("同步去 NAS")
        let root = root
        Task.detached {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [root.appendingPathComponent("experiments/001_wow_fishing/sync_recordings.sh").path]
            p.currentDirectoryURL = root; let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let synced = out.split(separator: "\n").filter { $0.contains("synced") }.count
            await MainActor.run { self.syncing = false; self.note(p.terminationStatus == 0 ? "NAS 同步完：\(synced) 次拋竿" : "NAS 同步失敗") }
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
                Circle().fill(c.running ? .green : c.externalRunner ? .orange : .secondary).frame(width: 10, height: 10)
                Text(c.running ? c.status : c.externalRunner ? "外面有個 loop 跑緊" : "停咗").font(.headline)
            }
            Stepper("目標技能：\(c.targetSkill)", value: $c.targetSkill, in: 1...450, step: 5).disabled(c.running)
            Stepper("每節：\(c.sessionSeconds / 60) 分鐘", value: $c.sessionSeconds, in: 60...1800, step: 60).disabled(c.running)
            Toggle("收線用 F8 Interact 鍵（唔郁游標）", isOn: $c.useInteractKey).disabled(c.running)
            HStack {
                Button { c.start() } label: { Label("開始", systemImage: "play.fill") }
                    .keyboardShortcut(.return).disabled(c.running || c.externalRunner)
                Button(role: .destructive) { c.stop() } label: { Label("停止", systemImage: "stop.fill") }
                    .disabled(!c.running)
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
