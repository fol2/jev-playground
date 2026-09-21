// Bounded probe: a known TextEdit document in front, one key sent only to WoW.
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class Probe: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await self.run() }
            catch { print("Probe stopped: \(error)") }
            NSApp.terminate(nil)
        }
    }

    func controlText(_ pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
            return result
        }
        guard let focusedWindow = value(app, kAXFocusedWindowAttribute as CFString),
              let title = value(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString) as? String,
              title.hasPrefix("jev-background-input"),
              let focused = value(app, kAXFocusedUIElementAttribute as CFString) else { return nil }
        return value(focused as! AXUIElement, kAXValueAttribute as CFString) as? String
    }

    func run() async throws {
        try await Task.sleep(for: .seconds(1))
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit",
              CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() else {
            print("foreground=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none") capture=\(CGPreflightScreenCaptureAccess()) accessibility=\(AXIsProcessTrusted())")
            throw NSError(domain: "Control window not foreground or permissions missing", code: 1)
        }
        let content = try await SCShareableContent.current
        guard let game = content.windows.filter({
            $0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.bundleIdentifier == "com.blizzard.worldofwarcraft"
        }).max(by: { $0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height }),
        let pid = game.owningApplication?.processID else {
            throw NSError(domain: "WoW window unavailable", code: 2)
        }
        let filter = SCContentFilter(desktopIndependentWindow: game)
        let config = SCStreamConfiguration()
        config.width = Int(game.frame.width); config.height = Int(game.frame.height)
        config.showsCursor = false
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("runs/001_wow_fishing/background_\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func save(_ image: CGImage, _ name: String) {
            let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL,
                UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
        func channelText(_ image: CGImage) throws -> String {
            let crop = image.cropping(to: CGRect(x: Double(image.width)*0.44, y: Double(image.height)*0.83,
                width: Double(image.width)*0.14, height: Double(image.height)*0.05))!
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: crop).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        }
        let before = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        save(before, "before.jpg")
        let priorChannel = try channelText(before)
        guard !priorChannel.contains("釣魚") && !priorChannel.contains("Fishing") else {
            throw NSError(domain: "Already fishing; cannot attribute a new cast", code: 3)
        }
        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit",
              let textBefore = controlText(frontBefore),
              textBefore == "JEV background probe\nNo keys should arrive here.\n" else {
            throw NSError(domain: "Expected control document is not focused", code: 4)
        }
        let pointerBefore = CGEvent(source: nil)!.location
        if CommandLine.arguments.contains("--full") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/tmp/jev-fishing-live")
            process.arguments = ["--execute", "--background"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let log = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try log.write(to: folder.appendingPathComponent("live-output.jsonl"))
            let lines = String(data: log, encoding: .utf8) ?? ""
            let after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            save(after, "after.jpg")
            let result: [String: Any] = [
                "foreground_remained_textedit": NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore,
                "pointer_unchanged": CGEvent(source: nil)!.location == pointerBefore,
                "control_document_unchanged": controlText(frontBefore) == textBefore,
                "pre_go_passed": lines.contains("\"event\":\"pre_go_pass\""),
                "right_click_sent": lines.contains("\"event\":\"right_click\""),
                "child_exit_code": process.terminationStatus, "output": folder.path
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent("result.json"))
            print(String(data: data, encoding: .utf8)!)
            print(lines)
            return
        }
        let source = CGEventSource(stateID: .privateState)
        CGEvent(keyboardEventSource: source, virtualKey: 18, keyDown: true)?.postToPid(pid)
        try await Task.sleep(for: .milliseconds(80))
        CGEvent(keyboardEventSource: source, virtualKey: 18, keyDown: false)?.postToPid(pid)
        try await Task.sleep(for: .seconds(1))
        let after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        save(after, "after.jpg")
        let afterChannel = try channelText(after)
        let pointerAfter = CGEvent(source: nil)!.location
        let result: [String: Any] = [
            "foreground_remained_control_window": NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore,
            "pointer_unchanged": pointerBefore == pointerAfter,
            "control_document_unchanged": controlText(frontBefore) == textBefore,
            "before_channel": priorChannel, "after_channel": afterChannel,
            "fishing_channel_detected": afterChannel.contains("釣魚") || afterChannel.contains("Fishing"),
            "target_pid": pid, "key_calls": 1, "mouse_calls": 0, "output": folder.path
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("result.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}

@main
struct BackgroundProbe {
    static func main() {
        let app = NSApplication.shared
        let delegate = Probe()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
