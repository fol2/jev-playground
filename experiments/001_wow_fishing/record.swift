// Record one small, silent macOS screen region; no model calls or input events.
//
//   record --rect x,y,width,height [--seconds 1..30] [--dry-run]
//
// Built by build.sh with ../002_wow_visual/runtime/JSON.swift.
import Foundation

@main
struct Record {
    static func main() {
        var rect: String?, seconds = 30, dryRun = false
        var rest = CommandLine.arguments.dropFirst()
        while let flag = rest.popFirst() {
            switch flag {
            case "--rect": rect = rest.popFirst()
            case "--seconds":
                guard let value = rest.popFirst().flatMap(Int.init), (1...30).contains(value) else { usage("--seconds must be 1..30") }
                seconds = value
            case "--dry-run": dryRun = true
            default: usage("unknown argument " + flag)
            }
        }
        let parts = (rect ?? "").split(separator: ",", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 != nil }) else { usage("--rect: use x,y,width,height in desktop coordinates") }
        guard (1...1000).contains(parts[2]!), (1...1000).contains(parts[3]!) else { usage("--rect: width and height must be between 1 and 1000") }
        let region = parts.map { String($0!) }.joined(separator: ",")
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/001_wow_fishing")
        let clock = DateFormatter()
        clock.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        clock.timeZone = TimeZone(identifier: "UTC")
        clock.locale = Locale(identifier: "en_US_POSIX")
        let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8)
        let output = folder.appendingPathComponent("\(clock.string(from: Date()))_\(id).mov")
        let command = ["/usr/sbin/screencapture", "-v", "-x", "-V\(seconds)", "-R\(region)", output.path]
        if dryRun {
            print(JSON.object([("command", .array(command.map(JSON.string))), ("audio", .bool(false)), ("model_calls", .int(0))]).text(indent: 2))
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            fail("Recording failed: \(error)")
        }
        let note = output.deletingPathExtension().appendingPathExtension("json")
        var metadata = JSON.object([("started_at_utc", .string(utc())), ("desktop_rect", .string(region)), ("requested_seconds", .int(seconds)),
                                    ("audio", .bool(false)), ("status", .string("started")), ("file", .string(output.lastPathComponent))])
        func save() { try? (metadata.text(indent: 2) + "\n").write(to: note, atomically: true, encoding: .utf8) }
        save()
        print("Recording for \(seconds) seconds: \(output.path)")
        fflush(stdout)
        var code: Int32 = 0
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            try process.run()
            let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds + 15)
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(100_000) }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw RecordError(description: "screencapture ran past \(seconds + 15) s")
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? nil
            guard process.terminationStatus == 0, let size, size > 0 else {
                throw RecordError(description: "No recording produced; check Screen Recording permission")
            }
            metadata = metadata.setting("status", .string("captured_unreviewed")).setting("bytes", .int(size))
            print(String(format: "Saved %.2f MiB; inspect before using as evidence.", Double(size) / 1024 / 1024))
        } catch {
            metadata = metadata.setting("status", .string("failed"))
            FileHandle.standardError.write(Data("Recording failed: \(error)\n".utf8))
            code = 1
        }
        metadata = metadata.setting("finished_at_utc", .string(utc()))
        save()
        exit(code)
    }

    struct RecordError: Error, CustomStringConvertible { let description: String }

    static func utc() -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxxxx"
        format.timeZone = TimeZone(identifier: "UTC")
        format.locale = Locale(identifier: "en_US_POSIX")
        return format.string(from: Date())
    }

    static func usage(_ why: String) -> Never {
        FileHandle.standardError.write(Data("usage: record --rect x,y,width,height [--seconds 1..30] [--dry-run]\nerror: \(why)\n".utf8))
        exit(2)
    }

    static func fail(_ why: String) -> Never {
        FileHandle.standardError.write(Data((why + "\n").utf8))
        exit(1)
    }
}
