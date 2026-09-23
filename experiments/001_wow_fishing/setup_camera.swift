// One-time native UI setup. No game scripts, provider requests or fishing inputs.
import AppKit
import ScreenCaptureKit
import Vision

struct CameraSetupError: Error, CustomStringConvertible { let description: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CameraSetupError(description: message) }
}
struct CameraText {
    let text: String
    let rect: CGRect // Window-relative, top-left coordinates.
}
func normaliseCameraText(_ text: String) -> String {
    text.lowercased().filter { !$0.isWhitespace && $0 != ":" }
}
func cameraLabel(_ rows: [CameraText], _ names: [String]) -> CameraText? {
    let names = names.map(normaliseCameraText)
    return rows.first { names.contains(normaliseCameraText($0.text)) }
}
func cameraBinding(_ rows: [CameraText], _ label: CameraText) -> CameraText? {
    rows.filter { $0.rect.minX > label.rect.maxX && abs($0.rect.midY-label.rect.midY) < label.rect.height }
        .min { $0.rect.minX < $1.rect.minX }
}
func expectedCameraKey(_ text: String, _ key: String) -> Bool {
    let value = normaliseCameraText(text)
    return value.contains("ctrl") && value.contains("alt") && value.hasSuffix(key.lowercased())
}

@main
struct CameraSetup {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("Camera setup stopped: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        let args = Set(CommandLine.arguments.dropFirst())
        let allowed: Set<String> = ["--execute", "--save-current-view", "--replace", "--help", "--self-test"]
        try require(args.isSubset(of: allowed), "Unknown option; use --help.")
        if args == ["--self-test"] {
            let label = CameraText(text: "Set View 1", rect: CGRect(x: 10, y: 10, width: 80, height: 16))
            let primary = CameraText(text: "Alt 鍵-CTRL-F9", rect: CGRect(x: 120, y: 10, width: 90, height: 16))
            let secondary = CameraText(text: "Not Bound", rect: CGRect(x: 240, y: 10, width: 80, height: 16))
            let otherRow = CameraText(text: "wrong", rect: CGRect(x: 100, y: 45, width: 80, height: 16))
            try require(cameraLabel([label], ["Set View 1"]) != nil, "English label")
            try require(cameraLabel([label], ["Set View 2"]) == nil, "Wrong view rejected")
            try require(cameraBinding([otherRow, secondary, primary], label)?.text == primary.text, "Primary button on same row")
            try require(cameraBinding([otherRow], label) == nil, "Adjacent row rejected")
            try require(expectedCameraKey(primary.text, "F9"), "Localised modifier text")
            try require(!expectedCameraKey("CTRL-F9", "F9"), "Missing modifier rejected")
            try require(!expectedCameraKey("CTRL-ALT-F10", "F9"), "Wrong function key rejected")
            try require(expectedCameraKey("ALT-CTRL-F9", "F9"), "English modifier text")  // issue #10
            print("Camera setup: 8 offline checks passed; no capture or input.")
            return
        }
        guard args.contains("--execute") && !args.contains("--help") else {
            print("""
            One-time camera setup (macOS, default WoW settings UI, English / Traditional Chinese).
            Choose the desired camera pitch and zoom first; close bags, chat and dialogues.
            Run: setup_camera.sh --execute --save-current-view
            Binds Set View 1 to Control+Option+F9 and Save View 1 to Control+Option+F10.
            Saves the CURRENT view; does not choose an angle, turn the character or fish.
            Uses the current binding scope. Stops on unreadable UI or differing view bindings.
            Never activates WoW. --replace explicitly replaces a previous local setup receipt.
            No action is taken without --execute and --save-current-view.
            """)
            return
        }
        try require(args.contains("--save-current-view"), "Saving the current view requires --save-current-view.")
        let receipt = URL(fileURLWithPath: "data/001_wow_fishing/camera-setup.json")
        try require(!FileManager.default.fileExists(atPath: receipt.path) || args.contains("--replace"),
                    "Setup already recorded. Pre-go should only restore. Use --replace to save a new baseline.")
        try require(AXIsProcessTrusted() && CGPreflightScreenCaptureAccess(), "Accessibility / Screen Recording permission missing.")
        NSApplication.shared.setActivationPolicy(.prohibited)
        let windows = try await SCShareableContent.current.windows.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width >= 640 && $0.frame.height >= 360
                && $0.owningApplication?.bundleIdentifier == "com.blizzard.worldofwarcraft"
        }
        try require(windows.count == 1, "Expected exactly one WoW window.")
        let window = windows[0], bounds = window.frame
        let pid = window.owningApplication!.processID
        let target = try routedTarget(pid: pid, window: window.windowID, bounds: bounds)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(bounds.width); config.height = Int(bounds.height); config.showsCursor = false
        let deadline = Date().addingTimeInterval(90)
        func valid() async throws {
            try require(Date() < deadline && !CGEventSource.keyState(.combinedSessionState, key: 53), "Deadline / Escape stop.")
            let current = try await SCShareableContent.current.windows
            try require(current.contains { $0.windowID == window.windowID && $0.frame == bounds && $0.owningApplication?.processID == pid },
                        "Window identity or geometry changed.")
        }
        func press(_ code: CGKeyCode, _ flags: CGEventFlags = []) async throws {
            try await valid()
            let source = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
                event.flags = flags; event.postToPid(pid)
                try await Task.sleep(for: .milliseconds(50))
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        func click(_ point: CGPoint) async throws {
            try await valid()
            let point = CGPoint(x: bounds.minX+point.x, y: bounds.minY+point.y)
            _ = try NativeBackgroundClickTransport().dispatch(.init(target: target,
                eventTapPointTopLeft: point, appKitPoint: point, clickCount: 1, mouseButton: .left))
            try await Task.sleep(for: .milliseconds(250))
        }
        func read() async throws -> [CameraText] {
            try await valid()
            // Keep the in-game pointer away from binding buttons and their tooltips.
            try NativeBackgroundClickTransport().move(target: target, point: CGPoint(x: bounds.minX+20, y: bounds.minY+20))
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let roi = CGRect(x: bounds.width*0.28, y: bounds.height*0.08, width: bounds.width*0.44, height: bounds.height*0.64).integral
            let cropped = image.cropping(to: roi)!
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hant", "en-US"]; request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: cropped).perform([request])
            return (request.results ?? []).compactMap { item in
                guard let text = item.topCandidates(1).first?.string else { return nil }

                let box = item.boundingBox
                return CameraText(text: text, rect: CGRect(x: roi.minX+box.minX*roi.width,
                    y: roi.minY+(1-box.maxY)*roi.height, width: box.width*roi.width, height: box.height*roi.height))
            }
        }
        func clickLabel(_ names: [String], _ rows: [CameraText]) async throws {
            guard let label = cameraLabel(rows, names) else { throw CameraSetupError(description: "Cannot find \(names[0]).") }
            try await click(CGPoint(x: label.rect.midX, y: label.rect.midY))
        }
        var rows = try await read()
        if cameraLabel(rows, ["按鍵綁定", "Key Bindings"]) == nil {
            if cameraLabel(rows, ["選項", "Options"]) == nil { try await press(53); rows = try await read() }
            try await clickLabel(["選項", "Options"], rows)
            rows = try await read()
        }
        try await clickLabel(["按鍵綁定", "Key Bindings"], rows)
        rows = try await read()
        // The native page retains expansion and scroll position. Search a bounded number of rows.
        func scrollDown(_ rows: [CameraText]) async throws {
            guard let close = cameraLabel(rows, ["關閉", "Close"]) else {
                throw CameraSetupError(description: "Cannot locate settings panel scrollbar.")
            }
            // Default settings panel: the down arrow is immediately above/right of Close.
            // Scale the offset with the button font rather than desktop resolution.
            let arrow = CGPoint(x: close.rect.midX+1.75*close.rect.height,
                                y: close.rect.midY-2.1*close.rect.height)
            for _ in 0..<3 { try await click(arrow) }
        }
        let bindings: [([String], CGKeyCode, String)] = [
            (["設定視角1", "Set View 1"], 101, "F9"),
            (["保存視角1", "儲存視角1", "Save View 1"], 109, "F10")]
        for (names, code, key) in bindings {
            var expanded = false
            for _ in 0..<18 {
                if cameraLabel(rows, names) != nil { break }
                if !expanded, cameraLabel(rows, ["下一個視角", "Next View"]) == nil,
                   let view = cameraLabel(rows, ["鏡頭功能", "視野功能", "Camera Functions"]) {
                    try await click(CGPoint(x: view.rect.midX, y: view.rect.midY)); expanded = true
                } else { try await scrollDown(rows) }
                rows = try await read()
            }
            guard let label = cameraLabel(rows, names), let binding = cameraBinding(rows, label) else {
                throw CameraSetupError(description: "Cannot locate \(names[0]) and its binding button.")
            }
            if !expectedCameraKey(binding.text, key) {
                try require(["未設定", "Not Bound", "Unbound"].map(normaliseCameraText).contains(normaliseCameraText(binding.text)),
                            "Existing camera binding differs: \(binding.text). Resolve in native settings first.")
                try await click(CGPoint(x: binding.rect.midX, y: binding.rect.midY))
                try await press(code, [.maskControl, .maskAlternate])
                rows = try await read()
                guard let updated = cameraLabel(rows, names), let assigned = cameraBinding(rows, updated), expectedCameraKey(assigned.text, key) else {
                    // Do not accept a dialogue or claim success without binding readback.
                    throw CameraSetupError(description: "Binding was not verified; inspect native settings for a conflict.")
                }
            }
            print("Verified \(names.last!): Control+Option+\(key)")
        }
        try await clickLabel(["關閉", "Close"], rows)
        // Closing Options returns to the game menu in this client.
        try await press(53)
        rows = try await read()
        try require(cameraLabel(rows, ["選項", "Options", "按鍵綁定", "Key Bindings"]) == nil, "Settings/menu still open; view not saved.")
        try await press(109, [.maskControl, .maskAlternate])
        let result: [String: Any] = ["saved_at": ISO8601DateFormatter().string(from: Date()),
            "restore_key": "CTRL-ALT-F9", "save_key": "CTRL-ALT-F10", "ui_view_label": "1",
            "binding_readback_verified": true, "save_key_sent": true, "restore_visually_verified": false,
            "window_width": bounds.width, "window_height": bounds.height]
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: receipt, options: .atomic)
        print("Saved current-view key sent. Verify by changing camera zoom, then Control+Option+F9. Receipt: \(receipt.path)")
    }
}
