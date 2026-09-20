// One fishing attempt. Optional Jev decisions; no video, game memory or add-ons.
import AppKit
import ApplicationServices
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import Vision
import VideoToolbox

// Native capture requires an output delegate. Retain one frame, not a video or queue.
final class LatestFrame: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var frame: (CGImage, Double)?
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid, let buffer = sample.imageBuffer else { return }
        guard let attachment = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachment.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr,
              let image else { return }
        let timestamp = sample.presentationTimeStamp.seconds
        lock.lock(); frame = (image, timestamp); lock.unlock()
    }
    func latest() -> (CGImage, Double)? {
        lock.lock(); defer { lock.unlock() }
        return frame
    }
}

func readText(_ image: CGImage) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hant", "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    return request.results ?? []
}

func containsText(_ image: CGImage, _ terms: [String]) throws -> Bool {
    let text = try readText(image).compactMap { $0.topCandidates(1).first?.string }.joined()
    let normalised = text.applyingTransform(StringTransform(rawValue: "Simplified-Traditional"), reverse: false) ?? text
    return terms.contains { normalised.contains($0) }
}

func section(_ image: CGImage, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGImage {
    image.cropping(to: CGRect(x: x*Double(image.width), y: y*Double(image.height),
                             width: w*Double(image.width), height: h*Double(image.height)))!
}

func fishingChannelConfirmed(_ image: CGImage) throws -> Bool {
    // The observed low-resolution channel label can be read as 鉤魚 by Vision.
    // Require a visible green progress bar as well as a fishing-label candidate.
    guard try containsText(image, ["釣魚", "鉤魚", "Fishing"]) else { return false }
    let pixels = blobs(image, width: image.width, height: image.height).1
    let count = image.width * image.height
    let green = (0..<count).filter {
        let r=Double(pixels[$0*4]), g=Double(pixels[$0*4+1]), b=Double(pixels[$0*4+2])
        return g > 100 && g > r*1.1 && g > b*1.2
    }.count
    return Double(green)/Double(count) > 0.04
}

struct Blob {
    var x: Double
    var y: Double
    var area: Int
}

func distance(_ a: Blob, _ b: Blob) -> Double { hypot(a.x - b.x, a.y - b.y) }
func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

func isBite(_ history: [Blob], _ current: Blob, _ background: Double,
            missingFrames: Int = 0, missingSeconds: Double = 0, missingBackground: Double = 0) -> Bool {
    guard history.count == 6 else { return false }
    // Keep the newest two observations out of the stable reference: they may
    // already contain the onset of the movement we are trying to detect.
    let baseline = Array(history.prefix(4))
    let minimumDrop = max(2.0, 0.45 * sqrt(median(baseline.map { Double($0.area) })))
    let baseY = median(baseline.map(\.y)), baseX = median(baseline.map(\.x))
    let returnedAfterDip = (1...3).contains(missingFrames) && missingSeconds <= 0.6
        && missingBackground < 4 && hypot(current.x-baseX, current.y-baseY) < 6
        && history.last!.y >= baseY && Double(current.area) >= median(baseline.map { Double($0.area) }) * 0.6
    return baseline.map(\.y).max()! - baseline.map(\.y).min()! < 2
        && (current.y-baseY >= minimumDrop || returnedAfterDip)
        && abs(current.x-baseX) < 6 && background < 4
}

func floatRecovered(_ current: Blob, _ previous: Blob, _ x: Double, _ y: Double,
                    _ area: Double, _ background: Double) -> Bool {
    abs(current.y-y) < 2.5 && abs(current.x-x) < 4
        && Double(current.area) >= area*0.75 && background < 4
        && distance(current, previous) < 1
}

func pageIsTwo(_ page: CGImage) -> Bool {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("page-two.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let reference = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let glyph = page.cropping(to: CGRect(x: 22, y: 34, width: 14, height: 13)) else { return false }
    func mask(_ image: CGImage) -> [Bool] {
        let pixels = blobs(image, width: 14, height: 13).1
        return (0..<182).map { pixels[$0*4] > 150 && pixels[$0*4+1] > 120 && pixels[$0*4+2] < 210 }
    }
    let expected = mask(reference), actual = mask(glyph)
    return zip(expected, actual).filter { $0 != $1 }.count <= 14
}

func compactFloatShape(_ width: Int, _ height: Int) -> Bool {
    height <= 3*width
}

func inCastWater(_ x: Double, _ y: Double) -> Bool {
    // Experiment-specific water region, calibrated from successful casts.
    x >= 0.42 && x <= 0.67 && y >= 0.17 && y <= 0.40
}

func blobs(_ image: CGImage, width: Int, height: Int) -> ([Blob], [UInt8]) {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var mask = [Bool](repeating: false, count: width * height)
    for i in 0..<mask.count {
        let r = Int(pixels[4*i]), g = Int(pixels[4*i+1]), b = Int(pixels[4*i+2])
        // The float shifts from orange to yellow under the moving water light.
        mask[i] = r > 110 && r-b > 35 && g-b > 25 && Double(r) > Double(g)*0.9
    }
    var result: [Blob] = []
    for start in 0..<mask.count where mask[start] {
        var queue = [start], head = 0, sx = 0, sy = 0
        var minX = width, maxX = 0, minY = height, maxY = 0
        mask[start] = false
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % width, y = i / width
            sx += x; sy += y
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            for (nx, ny) in [(x-1,y), (x+1,y), (x,y-1), (x,y+1)] {
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let next = ny * width + nx
                    if mask[next] { mask[next] = false; queue.append(next) }
                }
            }
        }
        if queue.count >= 20 && queue.count <= 600 && compactFloatShape(maxX-minX+1, maxY-minY+1) {
            result.append(Blob(x: Double(sx)/Double(queue.count),
                               y: Double(sy)/Double(queue.count), area: queue.count))
        }
    }
    return (result, pixels)
}

func save(_ image: CGImage, _ url: URL) {
    let jpeg = url.pathExtension == "jpg"
    let type = jpeg ? UTType.jpeg.identifier : UTType.png.identifier
    if let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) {
        let options = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, options)
        CGImageDestinationFinalize(destination)
    }
}

var inputTargetPID: pid_t?
var inputTargetWindow: CGWindowID?
var nativeTarget: RoutedClickTarget?

func post(_ event: CGEvent?) {
    if let pid = inputTargetPID {
        event?.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        if let window = inputTargetWindow {
            event?.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
            event?.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        }
        if let event, [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(event.type) {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setDoubleValueField(.mouseEventPressure, value: event.type == .leftMouseDown || event.type == .rightMouseDown ? 1 : 0)
        }
        event?.postToPid(pid)
    }
    else { event?.post(tap: .cghidEventTap) }
}

func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
    let source = inputTargetPID == nil ? nil : CGEventSource(stateID: .privateState)
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    event?.flags = flags
    post(event)
}

func mouse(_ type: CGEventType, _ point: CGPoint) {
    if type == .mouseMoved, let target = nativeTarget {
        do { try NativeBackgroundClickTransport().move(target: target, point: point) }
        catch { fputs("Background move failed: \(error)\n", stderr); exit(1) }
        return
    }
    let source = inputTargetPID == nil ? nil : CGEventSource(stateID: .privateState)
    post(CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                 mouseButton: .right))
}

func clickAt(_ point: CGPoint, _ button: MouseButtonDTO) async throws {
    if let target = nativeTarget {
        _ = try NativeBackgroundClickTransport().dispatch(.init(target: target,
            eventTapPointTopLeft: point, appKitPoint: point, clickCount: 1, mouseButton: button))
    } else {
        mouse(.mouseMoved, point)
        try await Task.sleep(for: .milliseconds(40))
        let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        let cgButton: CGMouseButton = button == .right ? .right : .left
        post(CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: cgButton))
        try await Task.sleep(for: .milliseconds(40))
        post(CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: cgButton))
    }
}

@main
struct Fishing {
    @MainActor static func main() async {
        do { try await run() }
        catch { fputs("Stopped: \(error)\n", stderr); exit(1) }
    }

    @MainActor static func run() async throws {
        if CommandLine.arguments.contains("--self-test") {
            // Measured sequence from Test A run live_1789923995_3A8353.
            let history = [Blob(x: 360.64, y: 162.9067, area: 75),
                Blob(x: 360.6494, y: 162.4286, area: 77), Blob(x: 361.058, y: 161.6087, area: 69),
                Blob(x: 360.8133, y: 162, area: 75), Blob(x: 360.72, y: 162.0667, area: 75),
                Blob(x: 360.9355, y: 164.5645, area: 62)]
            let dip = Blob(x: 360.871, y: 172, area: 31)
            guard isBite(history, dip, 2.0731) else {
                throw NSError(domain: "Regression: bite onset contaminates the stability window", code: 10)
            }
            guard !isBite(history, dip, 10), !isBite([], dip, 2),
                  !isBite(history, Blob(x: 361, y: 163, area: 70), 2) else {
                throw NSError(domain: "Regression: invalid or ordinary observation accepted", code: 11)
            }
            let small = [Blob(x: 343.0833, y: 123.3611, area: 36),
                Blob(x: 343.0588, y: 123.5588, area: 34), Blob(x: 343.0541, y: 123.2703, area: 37),
                Blob(x: 343.1081, y: 123.2162, area: 37), Blob(x: 343.3158, y: 123.0789, area: 38),
                Blob(x: 343.2821, y: 122.8462, area: 39)]
            guard isBite(small, Blob(x: 343.5217, y: 126.3478, area: 23), 1.4608),
                  !isBite(small, Blob(x: 343, y: 124.2, area: 35), 2) else {
                throw NSError(domain: "Regression: fixed pixel threshold misses a smaller bobber", code: 12)
            }
            let submerged = [Blob(x: 333.7, y: 139.9, area: 31),
                Blob(x: 333.7, y: 139.9, area: 32), Blob(x: 333.7, y: 139.969, area: 32),
                Blob(x: 333.7, y: 139.871, area: 31), Blob(x: 333.77, y: 140.065, area: 31),
                Blob(x: 333.74, y: 140.452, area: 31)]
            let returned = Blob(x: 332.929, y: 139.071, area: 28)
            guard isBite(submerged, returned, 1.7, missingFrames: 2, missingSeconds: 0.33, missingBackground: 1.68),
                  !isBite(submerged, returned, 1.7, missingFrames: 2, missingSeconds: 0.33, missingBackground: 12),
                  !isBite(submerged, returned, 1.7, missingFrames: 2, missingSeconds: 2, missingBackground: 1),
                  !isBite(submerged, returned, 1.7) else {
                throw NSError(domain: "Regression: brief local submersion and return", code: 13)
            }
            guard !compactFloatShape(2, 24), compactFloatShape(8, 10),
                  !inCastWater(0.51, 0.167), !inCastWater(0.346, 0.326),
                  inCastWater(0.48, 0.32), inCastWater(0.55, 0.30) else {
                throw NSError(domain: "Regression: rod, rock or neighbouring NPC acquired", code: 14)
            }
            guard !floatRecovered(Blob(x: 344.3043, y: 52.3913, area: 46),
                                  Blob(x: 343.94, y: 50.14, area: 50), 344.2, 52.2353, 51, 2.66) else {
                print("Regression: moving rebound accepted as recovered"); exit(1)
            }
            func answer(_ choice: String, _ probability: Double) -> JevReply {
                JevReply(action: choice, details: ["response": ["answers": ["action": ["probabilities": ["REEL": probability]]]]])
            }
            guard !reelIsSupported(answer("REEL", 0.74)), reelIsSupported(answer("REEL", 0.93)),
                  !reelIsSupported(answer("WAIT", 0.99)), !reelIsSupported(JevReply(action: "REEL", details: [:])) else {
                print("Regression: unsupported Jev reel executed"); exit(1)
            }
            print("Twenty-one local decision and acquisition checks passed; no UI, capture or provider calls.")
            return
        }
        if let argument = CommandLine.arguments.firstIndex(of: "--inspect-image"), argument+1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[argument+1])
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            for b in blobs(image, width: image.width, height: image.height).0 {
                print("blob x=\(b.x) y=\(b.y) area=\(b.area)")
            }
            return
        }
        if let argument = CommandLine.arguments.firstIndex(of: "--jev-fixture"), argument+1 < CommandLine.arguments.count {
            let state = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[argument+1]))) as! [String: Any]
            let client = try JevClient()
            defer { client.cancel() }
            func output(_ event: String, _ details: [String: Any]) {
                var row = details; row["event"] = event
                print(String(data: try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), encoding: .utf8)!)
            }
            try client.start(state: state, question: fishingQuestion, emit: output)
            while true {
                if let answer = client.take() { output("jev_response", answer.details); return }
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let execute = CommandLine.arguments.contains("--execute")
        let background = CommandLine.arguments.contains("--background")
        let probe = CommandLine.arguments.contains("--probe")
        let check = CommandLine.arguments.contains("--check")
        let jev = CommandLine.arguments.contains("--jev") ? try JevClient() : nil
        defer { jev?.cancel() }
        let prepared = CommandLine.arguments.contains("--prepared")
        guard execute || probe || check else {
            print("Usage: live --probe | --check | --execute [--background] (one cast maximum)")
            return
        }
        guard CGPreflightScreenCaptureAccess(), !(execute || check) || AXIsProcessTrusted() else {
            throw NSError(domain: "Screen Recording / Accessibility permission unavailable", code: 1)
        }
        let content = try await SCShareableContent.current
        guard let window = content.windows.filter({
            $0.owningApplication?.bundleIdentifier == "com.blizzard.worldofwarcraft"
                && $0.windowLayer == 0 && $0.isOnScreen && $0.frame.width > 300
        }).max(by: { $0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height }),
        let pid = window.owningApplication?.processID,
        let app = NSRunningApplication(processIdentifier: pid) else {
            throw NSError(domain: "WoW window not found", code: 2)
        }
        let bounds = window.frame
        inputTargetPID = background ? pid : nil
        inputTargetWindow = background ? window.windowID : nil
        if background { nativeTarget = try routedTarget(pid: pid, window: window.windowID, bounds: bounds) }
        let crop = CGRect(x: bounds.width * 0.25, y: bounds.height * 0.12,
                          width: bounds.width * 0.44, height: bounds.height * 0.36).integral
        let width = Int(crop.width / 2), height = Int(crop.height / 2)
        let config = SCStreamConfiguration()
        config.sourceRect = crop
        config.width = width; config.height = height
        config.showsCursor = false
        config.captureResolution = .nominal
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("runs/001_wow_fishing/live_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("events.jsonl")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let started = ProcessInfo.processInfo.systemUptime
        func emit(_ event: String, _ details: [String: Any] = [:]) {
            var row = details
            row["event"] = event; row["seconds"] = ProcessInfo.processInfo.systemUptime - started
            let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            try? log.write(contentsOf: data + Data([10]))
            if event != "sample" { print(String(data: data, encoding: .utf8)!); fflush(stdout) }
        }
        func valid() -> Bool {
            let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            guard background ? !foreground : foreground else {
                emit("focus_lost", ["frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"])
                return false
            }
            guard !CGEventSource.keyState(.combinedSessionState, key: 53) else { return false }
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.windowID) as? [[String: Any]]
            guard let rect = info?.first?[kCGWindowBounds as String] as? NSDictionary,
                  let current = CGRect(dictionaryRepresentation: rect) else {
                emit("window_unavailable", ["window_id": window.windowID]); return false
            }
            if current != bounds {
                emit("geometry_changed", ["expected": NSStringFromRect(bounds), "actual": NSStringFromRect(current)])
                return false
            }
            return true
        }
        if !background { app.activate(options: []) }
        try await Task.sleep(for: .milliseconds(300))
        guard valid() else { emit("stopped_focus_or_geometry"); return }
        if check || (execute && !prepared) {
            emit("pre_go_begin")
            // Coordinates describe the visually inspected default UI at this window size.
            // Fail on unreadable evidence rather than assuming a different UI layout works.
            let full = SCStreamConfiguration()
            full.width = Int(bounds.width); full.height = Int(bounds.height)
            full.showsCursor = false
            func capture() async throws -> CGImage {
                guard valid() else { throw NSError(domain: "Pre-go lost focus or geometry", code: 3) }
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
            }
            func press(_ code: CGKeyCode, _ flags: CGEventFlags = []) async throws {
                guard valid() else { throw NSError(domain: "Pre-go lost focus", code: 3) }
                key(code, down: true, flags: flags)
                try await Task.sleep(for: .milliseconds(50))
                key(code, down: false, flags: flags)
                try await Task.sleep(for: .milliseconds(300))
            }
            func hover(_ x: Double, _ y: Double) async throws {
                guard valid() else { throw NSError(domain: "Pre-go lost focus", code: 3) }
                mouse(.mouseMoved, CGPoint(x: bounds.minX+x*bounds.width, y: bounds.minY+y*bounds.height))
                try await Task.sleep(for: .milliseconds(450))
            }
            var screen = try await capture()
            save(screen, directory.appendingPathComponent("pre-go.jpg"))
            if try containsText(section(screen, 0.4, 0.1, 0.2, 0.11), ["refresh", "Refresh"]) {
                emit("pre_go_world_refresh_pending"); return
            }
            let centre = section(screen, 0.2, 0.28, 0.6, 0.10)
            if try containsText(centre, ["Lua錯誤", "Lua 錯誤", "遊戲選單", "返回遊戲", "物品"]) {
                emit("pre_go_blocked_overlay"); return
            }
            // Character sheet, then read the equipped main-hand item tooltip.
            try await press(8) // C
            screen = try await capture()
            if try containsText(section(screen, 0.2, 0.32, 0.6, 0.07), ["Lua錯誤", "Lua 錯誤"]) {
                // Close X in the inspected default-layout Lua dialog, only after
                // its title is recognised; then prove the dialog disappeared.
                let point = CGPoint(x: bounds.minX+0.776*bounds.width,
                                    y: bounds.minY+0.349*bounds.height)
                try await clickAt(point, .left)
                try await Task.sleep(for: .milliseconds(300))
                screen = try await capture()
                guard try !containsText(section(screen, 0.2, 0.32, 0.6, 0.07), ["Lua錯誤", "Lua 錯誤"]) else {
                    emit("pre_go_character_error_still_open"); return
                }
                emit("dismissed_character_beta_error")
            }
            try await hover(0.0725, 0.460)
            screen = try await capture()
            let equipment = section(screen, 0.075, 0.28, 0.21, 0.19)
            save(equipment, directory.appendingPathComponent("rod.jpg"))
            func words(_ image: CGImage) throws -> [String] {
                try readText(image).compactMap { $0.topCandidates(1).first?.string }
            }
            var rod = try containsText(equipment, ["魚竿", "釣竿", "Fishing Pole"])
            try await press(8) // Close character sheet.
            var shouldEquip = !rod
            if let jev {
                let choice = try await jev.decide(state: ["equipped_main_hand_tooltip": try words(equipment)],
                    instructions: "Prepare for fishing. Read the equipped item tooltip (Traditional Chinese or English). Choose the next action.",
                    criteria: ["KEEP": "A fishing pole is already equipped.", "EQUIP_ROD": "A recognisable non-fishing weapon is equipped; inspect the known bag slot for a fishing pole.", "ABSTAIN": "The tooltip is unreadable or ambiguous."], emit: emit)
                guard choice != "ABSTAIN", (choice == "KEEP") == rod else { emit("pre_go_jev_equipment_unconfirmed"); return }
                shouldEquip = choice == "EQUIP_ROD"
            }
            if shouldEquip {
                emit("pre_go_switching_from_main_weapon")
                // Try the previous slot, then search the bounded default bag grid.
                // Verify the tooltip before equipping; never click an unknown item.
                try await press(11) // B: open combined bag.
                var bagX = 0.924, bagY = 0.789
                try await hover(bagX, bagY)
                screen = try await capture()
                var bagItem = section(screen, 0.60, 0.45, 0.32, 0.48)
                if !(try containsText(bagItem, ["魚竿", "釣竿", "Fishing Pole"])) {
                    // Bounded default-layout bag search. OCR only; provider sees the found tooltip.
                    var found = false
                    for row in 0..<5 {
                        for column in (0..<10).reversed() {
                            bagX = 0.805 + Double(column)*0.0197
                            bagY = 0.894 - Double(row)*0.035
                            try await hover(bagX, bagY)
                            screen = try await capture()
                            bagItem = section(screen, 0.60, 0.45, 0.32, 0.48)
                            if try containsText(bagItem, ["魚竿", "釣竿", "Fishing Pole"]) { found = true; break }
                        }
                        if found { break }
                    }
                    emit("pre_go_bag_search", ["found": found, "x": bagX, "y": bagY])
                }
                save(bagItem, directory.appendingPathComponent("bag-rod.jpg"))
                guard try containsText(bagItem, ["魚竿", "釣竿", "Fishing Pole"]) else {
                    emit("pre_go_bag_rod_unconfirmed"); return
                }
                if let jev {
                    let choice = try await jev.decide(state: ["bag_item_tooltip": try words(bagItem)],
                        instructions: "Should this bag item be equipped for fishing?", criteria: ["EQUIP": "This item is a fishing pole.", "ABSTAIN": "Not a fishing pole or unclear."], emit: emit)
                    guard choice == "EQUIP", valid() else { emit("pre_go_jev_bag_unconfirmed"); return }
                }
                try await clickAt(CGPoint(x: bounds.minX+bagX*bounds.width,
                                         y: bounds.minY+bagY*bounds.height), .right)
                try await Task.sleep(for: .milliseconds(400))
                try await press(11) // Close bag.
                try await press(8) // Reopen equipment and verify actual equipped rod.
                screen = try await capture()
                if try containsText(section(screen, 0.2, 0.32, 0.6, 0.07), ["Lua錯誤", "Lua 錯誤"]) {
                    try await clickAt(CGPoint(x: bounds.minX+0.776*bounds.width,
                                             y: bounds.minY+0.349*bounds.height), .left)
                    try await Task.sleep(for: .milliseconds(300))
                    screen = try await capture()
                    guard try !containsText(section(screen, 0.2, 0.32, 0.6, 0.07), ["Lua錯誤", "Lua 錯誤"]) else {
                        emit("pre_go_character_error_still_open"); return
                    }
                    emit("dismissed_character_beta_error_after_equipping")
                }
                try await hover(0.0725, 0.460)
                screen = try await capture()
                let equipped = section(screen, 0.075, 0.28, 0.21, 0.19)
                save(equipped, directory.appendingPathComponent("equipped-rod.jpg"))
                rod = try containsText(equipped, ["魚竿", "釣竿", "Fishing Pole"])
                try await press(8)
            }
            guard rod else { emit("pre_go_rod_unconfirmed"); return }
            emit("pre_go_rod_verified")
            if let jev {
                try await hover(0.227, 0.981)
                screen = try await capture()
                let choice = try await jev.decide(state: ["slot_one_tooltip": try words(section(screen, 0.82, 0.75, 0.18, 0.2)),
                    "page_two_glyph_matches": pageIsTwo(section(screen, 0.201, 0.950, 0.020, 0.05))],
                    instructions: "Fishing is configured on action-bar page 2, slot 1. Choose preparation action from observed current page and slot tooltip.",
                    criteria: ["KEEP": "Page 2 is selected and slot 1 is Fishing.", "PAGE_TWO": "Switch to configured fishing page 2 because the current page or skill differs.", "ABSTAIN": "Evidence cannot determine a safe preparation action."], emit: emit)
                guard choice != "ABSTAIN" else { emit("pre_go_jev_page_unconfirmed"); return }
                if choice == "PAGE_TWO" { try await press(19, .maskShift) }
            } else { try await press(19, .maskShift) } // Shift+2.
            try await hover(0.227, 0.981)
            screen = try await capture()
            let skill = section(screen, 0.82, 0.75, 0.18, 0.2)
            save(skill, directory.appendingPathComponent("skill.jpg"))
            guard try containsText(skill, ["釣魚", "Fishing"]) else {
                emit("pre_go_fishing_slot_unconfirmed"); return
            }
            let page = section(screen, 0.201, 0.950, 0.020, 0.05)
            save(page, directory.appendingPathComponent("page.jpg"))
            guard pageIsTwo(page) else {
                emit("pre_go_page_two_unconfirmed"); return
            }
            if let jev {
                let choice = try await jev.decide(state: ["equipped_fishing_pole_verified": rod,
                    "slot_one_tooltip": try words(skill), "page_two_glyph_matches": pageIsTwo(page),
                    "water": "Fixed previously calibrated scene; visibility of own float must be checked after casting."],
                    instructions: "Are equipment and controls ready for one fishing cast? Water visibility is checked after casting, not certified here.",
                    criteria: ["READY": "Fishing pole equipped, page 2 selected, slot 1 is Fishing.", "ABSTAIN": "Equipment or controls are not verified."], emit: emit)
                guard choice == "READY", valid() else { emit("pre_go_jev_not_ready"); return }
            }
            emit("pre_go_controls_verified", ["page": 2, "slot": 1])
            // Water/line of sight cannot be certified from a colour mask. The real
            // acceptance gate is a stable, visible float shortly after the cast.
            emit("pre_go_pass", ["water": "requires_post_cast_visible_float", "output": directory.path])
            if check { return }
            try await hover(0.02, 0.9)
        }
        let initial = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        save(initial, directory.appendingPathComponent("before.jpg"))
        var (existing, _) = blobs(initial, width: width, height: height)
        emit("ready", ["output": directory.path, "width": width, "height": height,
                       "crop": [crop.minX, crop.minY, crop.width, crop.height],
                       "existing_blobs": existing.count, "execute": execute])
        if probe { return }
        // Keep the pointer out of the observation region, including in-game cursor artwork.
        mouse(.mouseMoved, CGPoint(x: bounds.minX + 30, y: bounds.maxY - 30))
        key(18, down: true) // Physical 1 key, bound to Fishing by the user.
        try await Task.sleep(for: .milliseconds(50))
        key(18, down: false)
        emit("cast")
        let castAt = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .milliseconds(150))
        guard valid() else { emit("stopped_before_cast_verification"); return }
        // Re-sample after the old cast clears, before the new float lands.
        let cleared = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        existing = blobs(cleared, width: width, height: height).0
        save(cleared, directory.appendingPathComponent("cast-clear.jpg"))
        try await Task.sleep(for: .milliseconds(250))
        guard valid() else { emit("stopped_before_cast_verification"); return }
        let channelConfig = SCStreamConfiguration()
        channelConfig.sourceRect = CGRect(x: bounds.width*0.44, y: bounds.height*0.83,
                                         width: bounds.width*0.14, height: bounds.height*0.05)
        channelConfig.width = Int(bounds.width*0.14)
        channelConfig.height = Int(bounds.height*0.05)
        channelConfig.showsCursor = false
        var channel = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: channelConfig)
        var confirmed = try fishingChannelConfirmed(channel)
        for _ in 0..<2 where !confirmed {
            guard valid() else { emit("stopped_before_cast_verification"); return }
            try await Task.sleep(for: .milliseconds(200))
            channel = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: channelConfig)
            confirmed = try fishingChannelConfirmed(channel)
            emit("cast_channel_recheck", ["confirmed": confirmed])
        }
        save(channel, directory.appendingPathComponent("cast-channel.jpg"))
        guard confirmed else {
            emit("stopped_cast_not_confirmed"); return
        }
        emit("cast_channel_verified")
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        config.queueDepth = 3
        let source = LatestFrame()
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(source, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "fishing.frames"))
        try await stream.startCapture()
        func observe() async throws {
        var target: Blob? = nil, history: [Blob] = [], previous: [UInt8]? = nil
        var pending: Blob? = nil, pendingCount = 0
        var acquiredAt = 0.0, missing = 0
        var pendingBite: (x: Double, y: Double, area: Double, at: Double)?
        var recoveredFrames = 0
        var requestedReference: (x: Double, y: Double, area: Double, at: Double)?
        var lastRequest = -100.0
        var lastSubmitted: Blob?
        var submittedChange = false
        var missingStarted = 0.0, missingBackground = 0.0
        var lastTimestamp = -1.0
        while ProcessInfo.processInfo.systemUptime - castAt < 30 {
            guard valid() else { emit("stopped_focus_or_geometry"); return }
            let iterationAt = ProcessInfo.processInfo.systemUptime
            guard let (image, timestamp) = source.latest(), timestamp != lastTimestamp else {
                try await Task.sleep(for: .milliseconds(25)); continue
            }
            lastTimestamp = timestamp
            let frameAge = CMClockGetTime(CMClockGetHostTimeClock()).seconds - timestamp
            guard frameAge >= 0 && frameAge < 0.35 else {
                history.removeAll()
                emit("discarded_stale_frame", ["age_seconds": frameAge])
                try await Task.sleep(for: .milliseconds(100)); continue
            }
            let captureAt = iterationAt - frameAge
            let (candidates, pixels) = blobs(image, width: width, height: height)
            let now = ProcessInfo.processInfo.systemUptime
            if target == nil && now-castAt > 6 {
                save(image, directory.appendingPathComponent("no-visible-float.jpg"))
                emit("stopped_no_visible_float", ["cause": "occlusion_invalid_cast_or_detection_failure"])
                return
            }
            guard now - captureAt < 0.35 else { history.removeAll(); continue }
            var background = 0.0, count = 0
            if let previous {
                for y in stride(from: 0, to: height, by: 8) {
                    for x in stride(from: 0, to: width, by: 8) {
                        if let target, hypot(Double(x)-target.x, Double(y)-target.y) < 35 { continue }
                        let i = (y*width+x)*4
                        background += Double(abs(Int(pixels[i])-Int(previous[i])))
                        count += 1
                    }
                }
            }
            background /= Double(max(count, 1))
            previous = pixels
            let candidate: Blob?
            if let target {
                candidate = candidates.filter { distance($0, target) < 20 }
                    .min { distance($0, target) < distance($1, target) }
            } else if now - castAt > 0.8 {
                // Calibrated cast corridor excludes the neighbouring NPC's float.
                let fresh = candidates.filter { item in
                    let windowX = (crop.minX + item.x*crop.width/Double(width))/bounds.width
                    let windowY = (crop.minY + item.y*crop.height/Double(height))/bounds.height
                    return inCastWater(windowX, windowY)
                        && !existing.contains { distance(item, $0) < 15 }
                }
                let best = fresh.max { $0.area < $1.area }
                if let best {
                    pendingCount = pending.map { distance(best, $0) < 6 } == true ? pendingCount + 1 : 1
                    pending = best
                    candidate = pendingCount >= 3 ? best : nil
                } else { pending = nil; pendingCount = 0; candidate = nil }
            } else { candidate = nil }
            if let current = candidate {
                let gapFrames = missing
                let gapSeconds = missing > 0 ? now-missingStarted : 0
                missing = 0
                if target == nil {
                    acquiredAt = now
                    emit("target_acquired", ["x": current.x, "y": current.y, "area": current.area])
                    save(image, directory.appendingPathComponent("acquired.jpg"))
                    emit("post_cast_visible_float_verified")
                }
                if history.count == 6 && now-acquiredAt > 1 {
                    let baseY = median(history.prefix(4).map(\.y))
                    let drop = current.y - baseY
                    emit("sample", ["x": current.x, "y": current.y, "area": current.area,
                                    "drop": drop, "background_change": background,
                                    "missing_frames": gapFrames, "missing_seconds": gapSeconds,
                                    "reference_area": median(history.prefix(4).map { Double($0.area) }),
                                    "reference_spread": history.prefix(4).map(\.y).max()! - history.prefix(4).map(\.y).min()!])
                    var reel = false
                    var reference = (x: median(history.prefix(4).map(\.x)), y: baseY,
                                     area: median(history.prefix(4).map { Double($0.area) }), at: now)
                    if let jev {
                        if let answer = jev.take() {
                            emit("jev_response", answer.details)
                            guard answer.action != "ERROR" else { emit("stopped_jev_error"); return }
                            if let sent = requestedReference, now-sent.at <= 1.5 {
                                reel = reelIsSupported(answer)
                                // A non-actionable reply must not replace the next request's fresh baseline.
                                if reel { reference = sent }
                                if answer.action == "REEL" && !reel { emit("jev_reel_abstained", ["reason": "probability_below_0.85"]) }
                            } else { emit("jev_stale_response") }
                        }
                        // Broad change scheduling, independent of Test A's bite verdict.
                        // Quiet frames still get periodic judgements. No model output is fabricated locally.
                        let changed = abs(drop) > 1.5 || gapFrames > 0
                            || abs(Double(current.area)/reference.area-1) > 0.50
                        let novel = !submittedChange || lastSubmitted.map { distance($0, current) > 1.5 } == true
                        if pendingBite == nil && !reel && !jev.busy && now-lastRequest > 0.2
                            && ((changed && novel) || now-lastRequest > 4) {
                            guard jev.calls < jev.limit else { emit("stopped_jev_budget"); return }
                            func rounded(_ x: Double) -> Double { (x*100).rounded()/100 }
                            let rows = (history + [current]).map {
                                [rounded($0.x-reference.x), rounded($0.y-reference.y), rounded(Double($0.area)/reference.area)]
                            }
                            let direction = current.y-reference.y >= 0 ? "downwards" : "upwards"
                            let largestDownwardStep = zip(history, Array(history.dropFirst()) + [current]).map { $1.y-$0.y }.max()!
                            try jev.start(state: ["observed_motion": "The latest float position is \(rounded(abs(current.y-reference.y))) pixels \(direction) from the preceding baseline. The largest single downward step is \(rounded(largestDownwardStep)) pixels. The visible float has an approximate linear size of \(rounded(sqrt(reference.area))) pixels. It disappeared for \(gapFrames) frames immediately before this observation.",
                                "sequence_dx_downward_dy_area_ratio": rows,
                                "baseline_coloured_area_pixels": reference.area,
                                "sequence_seconds": rounded(0.6+gapSeconds), "background_change": rounded(background),
                                "missing_frames_before_current": gapFrames, "missing_seconds": rounded(gapSeconds),
                                "background_during_missing": rounded(missingBackground)], question: fishingQuestion, emit: emit)
                            requestedReference = reference; lastRequest = now; lastSubmitted = current
                            submittedChange = changed
                        }
                        if !changed { submittedChange = false }
                    } else {
                        reel = isBite(history, current, background, missingFrames: gapFrames,
                                      missingSeconds: gapSeconds, missingBackground: missingBackground)
                    }
                    if pendingBite == nil && reel {
                        pendingBite = reference
                        recoveredFrames = 0
                        emit("bite_detected_waiting_for_return", ["drop": drop])
                    }
                    if let signal = pendingBite {
                        if now-signal.at > 2.0 {
                            emit("stopped_bite_not_recovered"); return
                        }
                        let recovered = floatRecovered(current, history.last!, signal.x, signal.y, signal.area, background)
                        recoveredFrames = recovered ? recoveredFrames+1 : 0
                    }
                    if recoveredFrames >= 2 {
                        guard valid(), ProcessInfo.processInfo.systemUptime-captureAt < 0.35 else {
                            emit("stopped_before_click"); return
                        }
                        let point = CGPoint(x: bounds.minX+crop.minX+current.x*crop.width/Double(width),
                                            y: bounds.minY+crop.minY+current.y*crop.height/Double(height))
                        emit("bite_candidate", ["drop": drop, "desktop_x": point.x, "desktop_y": point.y])
                        guard valid(), ProcessInfo.processInfo.systemUptime-captureAt < 0.2 else {
                            emit("stopped_before_click"); return
                        }
                        try await clickAt(point, .right)
                        emit("right_click")
                        save(image, directory.appendingPathComponent("bite.jpg"))
                        try await Task.sleep(for: .milliseconds(800))
                        let full = SCStreamConfiguration()
                        full.width = Int(bounds.width); full.height = Int(bounds.height)
                        full.showsCursor = false
                        let after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
                        let lootRect = CGRect(x: max(0, point.x-bounds.minX-280),
                            y: max(0, point.y-bounds.minY-180), width: 800, height: 400)
                            .intersection(CGRect(x: 0, y: 0, width: after.width, height: after.height))
                        let lootImage = after.cropping(to: lootRect)!
                        save(lootImage, directory.appendingPathComponent("after.jpg"))
                        let labels = try readText(lootImage)
                        let words = labels.compactMap { $0.topCandidates(1).first?.string }
                        guard words.contains(where: { $0.contains("物品") || $0 == "Items" }) else {
                            emit("retrieval_unverified"); return
                        }
                        let items = labels.filter {
                            let text = $0.topCandidates(1).first?.string ?? ""
                            return text.contains("新鮮") || text.contains("新鲜") || text.contains("Fresh")
                        }
                        func labelPoint(_ label: VNRecognizedTextObservation) -> CGPoint {
                            CGPoint(x: bounds.minX+lootRect.minX+label.boundingBox.midX*lootRect.width,
                                    y: bounds.minY+lootRect.minY+(1-label.boundingBox.midY)*lootRect.height)
                        }
                        guard let item = items.min(by: {
                            let a=labelPoint($0), b=labelPoint($1)
                            return hypot(a.x-point.x,a.y-point.y) < hypot(b.x-point.x,b.y-point.y)
                        }), valid() else { emit("loot_item_unconfirmed"); return }
                        let name = item.topCandidates(1).first!.string
                        emit("fish_loot_observed", ["item": name])
                        try await clickAt(labelPoint(item), .left)
                        try await Task.sleep(for: .milliseconds(500))
                        let collected = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
                        let remaining = collected.cropping(to: lootRect)!
                        save(remaining, directory.appendingPathComponent("collected.jpg"))
                        if try containsText(remaining, ["物品", "Items"]) {
                            emit("loot_not_cleared", ["item": name])
                        } else { emit("loot_collected", ["item": name]) }
                        return
                    }
                }
                target = current
                history.append(current)
                if history.count > 6 { history.removeFirst() }
            } else if target != nil {
                missing += 1
                if missing == 1 { missingStarted = now; missingBackground = background }
                else { missingBackground = max(missingBackground, background) }
                emit("target_temporarily_missing", ["frames": missing, "background_change": background])
                if missing == 1 && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("first-missing.jpg").path) {
                    save(image, directory.appendingPathComponent("first-missing.jpg"))
                }
                if missing > 3 { emit("stopped_target_lost"); return }
            }
            let remaining = 0.1 - (ProcessInfo.processInfo.systemUptime-iterationAt)
            if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
        }
        emit("timed_out_without_click")
        }
        do {
            try await observe()
            try await stream.stopCapture()
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }
}
