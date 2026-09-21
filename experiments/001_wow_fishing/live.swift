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
    let pixels = imagePixels(image, width: image.width, height: image.height)
    func green(_ i: Int) -> Bool {
        let r=Double(pixels[i*4]), g=Double(pixels[i*4+1]), b=Double(pixels[i*4+2])
        return g > 100 && g > r*1.1 && g > b*1.2
    }
    let count = image.width*image.height
    guard Double((0..<count).filter(green).count)/Double(count) > 0.04 else { return false }
    if try containsText(image, ["釣魚", "鉤魚", "Fishing"]) { return true }
    // Pre-go verified the Fishing binding. A long green strip with its dark
    // channel panel underneath remains identifiable when the tiny label is not.
    for y in 0..<max(0,image.height-12) {
        var length = 0, darkBelow = 0
        for x in 0..<image.width {
            if green(y*image.width+x) {
                length += 1
                let i=((y+12)*image.width+x)*4
                if pixels[i]<60 && pixels[i+1]<60 && pixels[i+2]<60 { darkBelow += 1 }
                if length > image.width/2 && Double(darkBelow)/Double(length)>0.7 { return true }
            } else { length = 0; darkBelow = 0 }
        }
    }
    return false
}

// Match every frame to the acquisition image, not the previous tracking estimate.
// A lost/ambiguous match supplies no observation. Never adopt water as a new anchor.
final class FloatTracker {
    let crop: CGRect
    private let anchor: [Double]
    private let centre: CGPoint
    private let area: Int

    init(_ target: Blob, image: CGImage) throws {
        let side = min(160, min(image.width, image.height))
        crop = CGRect(x: max(0, min(Double(image.width-side), target.x-Double(side)/2)),
                      y: max(0, min(Double(image.height-side), target.y-Double(side)/2)),
                      width: Double(side), height: Double(side)).integral
        guard let patch = image.cropping(to: crop) else {
            throw NSError(domain: "Invalid float patch", code: 4)
        }
        anchor = greyPixels(patch)
        centre = CGPoint(x: target.x-Double(crop.minX), y: target.y-Double(crop.minY))
        area = target.area
    }

    func observe(_ image: CGImage) -> Blob? {
        guard let patch = image.cropping(to: crop),
              let motion = pixelMotion(previous: anchor, current: greyPixels(patch),
                                       width: patch.width, height: patch.height, centre: centre) else { return nil }
        return Blob(x: Double(crop.minX+centre.x)+motion.dx,
                    y: Double(crop.minY+centre.y)+motion.dy,
                    area: area, matchCorrelation: motion.correlation)
    }
}

func pageIsTwo(_ page: CGImage) -> Bool {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("page-two.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let reference = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let glyph = page.cropping(to: CGRect(x: 22, y: 34, width: 14, height: 13)) else { return false }
    func mask(_ image: CGImage) -> [Bool] {
        let pixels = imagePixels(image, width: 14, height: 13)
        return (0..<182).map { pixels[$0*4] > 150 && pixels[$0*4+1] > 120 && pixels[$0*4+2] < 210 }
    }
    let expected = mask(reference), actual = mask(glyph)
    return zip(expected, actual).filter { $0 != $1 }.count <= 14
}

// Recognise the known rod icon from one bag image; tooltip OCR confirms identity.
func rodIconCandidate(_ image: CGImage) -> (x: Double, y: Double, score: Double)? {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("rod-icon.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let reference = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    func vector(_ image: CGImage) -> [Double] {
        var pixels = [UInt8](repeating: 0, count: 16*16*4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        var grey = [Double]()
        for i in 0..<256 {
            grey.append(Double(pixels[i*4]) + Double(pixels[i*4+1]) + Double(pixels[i*4+2]))
        }
        let mean = grey.reduce(0,+)/256
        let centred = grey.map { $0-mean }
        let length = sqrt(centred.reduce(0) { $0+$1*$1 })
        return centred.map { $0/max(1,length) }
    }
    let expected = vector(reference)
    var best: (x: Double, y: Double, score: Double)?
    let side = 32*Double(image.width)/2560
    for row in 0..<5 {
        for column in 0..<10 {
            let x = 0.805+Double(column)*0.0197, y = 0.894-Double(row)*0.035
            guard let patch = image.cropping(to: CGRect(x: x*Double(image.width)-side/2,
                y: y*Double(image.height)-side/2, width: side, height: side)) else { continue }
            let score = zip(expected, vector(patch)).reduce(0) { $0+$1.0*$1.1 }
            if score > (best?.score ?? -1) { best = (x,y,score) }
        }
    }
    return best.flatMap { $0.score >= 0.75 ? $0 : nil }
}

func compactFloatShape(_ width: Int, _ height: Int) -> Bool {
    height <= 3*width
}

func imagePixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return pixels
}

func changedObjects(_ pixels: [UInt8], reference: [UInt8], width: Int, height: Int) -> [Blob] {
    var mask = [Bool](repeating:false,count:width*height)
    for i in 0..<mask.count {
        let j=i*4
        mask[i] = (0..<3).map { abs(Int(pixels[j+$0])-Int(reference[j+$0])) }.max()! > 35
    }
    // A 3x3 opening removes thin fishing lines and isolated water noise while retaining a compact body.
    var eroded=[Bool](repeating:false,count:mask.count)
    for y in 1..<(height-1) { for x in 1..<(width-1) where mask[y*width+x] {
        var solid=true
        for dy in -1...1 { for dx in -1...1 { if !mask[(y+dy)*width+x+dx] {solid=false} } }
        eroded[y*width+x]=solid
    }}
    mask=[Bool](repeating:false,count:mask.count)
    for y in 1..<(height-1) { for x in 1..<(width-1) where eroded[y*width+x] {
        for dy in -1...1 { for dx in -1...1 {mask[(y+dy)*width+x+dx]=true} }
    }}
    var result = [Blob]()
    func gradient(_ data: [UInt8], _ x0:Int, _ y0:Int, _ x1:Int, _ y1:Int) -> Double {
        func level(_ x:Int,_ y:Int) -> Double {
            let i=(y*width+x)*4
            return (Double(data[i])+Double(data[i+1])+Double(data[i+2]))/3
        }
        var sum=0.0
        for y in y0..<y1 { for x in x0..<x1 {
            if x+1<x1 { sum += abs(level(x+1,y)-level(x,y)) }
            if y+1<y1 { sum += abs(level(x,y+1)-level(x,y)) }
        }}
        return sum
    }
    for start in 0..<mask.count where mask[start] {
        var queue=[start], head=0, minX=width, maxX=0, minY=height, maxY=0
        mask[start]=false
        while head<queue.count {
            let i=queue[head];head+=1
            let x=i%width,y=i/width
            minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
            for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] {
                if nx>=0 && nx<width && ny>=0 && ny<height {
                    let next=ny*width+nx
                    if mask[next] {mask[next]=false;queue.append(next)}
                }
            }
        }
        let w=maxX-minX+1,h=maxY-minY+1
        guard queue.count>=12, queue.count<=500, w>=4,w<=50,h>=4,h<=40,
              w<=h*4,compactFloatShape(w,h),Double(queue.count)/Double(w*h)>0.3 else {continue}
        let x0=max(0,minX-2),x1=min(width,maxX+3),y0=max(0,minY-2),y1=min(height,maxY+3)
        let newEdges=gradient(pixels,x0,y0,x1,y1), oldEdges=gradient(reference,x0,y0,x1,y1)
        guard newEdges>1.25*max(1,oldEdges) else {continue}
        // The lower half anchors the floating body rather than an upper feather/line.
        let lower=queue.filter { $0/width >= minY+h/2 }
        guard !lower.isEmpty else {continue}
        result.append(Blob(x:Double(lower.reduce(0){$0+$1%width})/Double(lower.count),
                           y:Double(lower.reduce(0){$0+$1/width})/Double(lower.count),area:queue.count,novelty:newEdges-oldEdges))
    }
    return result
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
            try runSelfTests(); return
        }
        if let argument = CommandLine.arguments.firstIndex(of: "--inspect-image"), argument+1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[argument+1])
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            guard let argument=CommandLine.arguments.firstIndex(of:"--reference-image"), argument+1<CommandLine.arguments.count else {
                print("Use --inspect-image AFTER --reference-image BEFORE"); return
            }
            let beforeSource=CGImageSourceCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[argument+1]) as CFURL,nil)!
            let before=CGImageSourceCreateImageAtIndex(beforeSource,0,nil)!
            for b in changedObjects(imagePixels(image,width:image.width,height:image.height),
                                    reference:imagePixels(before,width:image.width,height:image.height),width:image.width,height:image.height) {
                print("object x=\(b.x) y=\(b.y) area=\(b.area) novelty=\(b.novelty)")
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
        let jev = execute && !check && CommandLine.arguments.contains("--jev") ? try JevClient() : nil
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
        NSRunningApplication(processIdentifier: pid) != nil else {
            throw NSError(domain: "WoW window not found", code: 2)
        }
        let bounds = window.frame
        inputTargetPID = background ? pid : nil
        inputTargetWindow = background ? window.windowID : nil
        if background { nativeTarget = try routedTarget(pid: pid, window: window.windowID, bounds: bounds) }
        // Search the playfield above the avatar, excluding the main HUD/minimap.
        let crop = CGRect(x: bounds.width * 0.02, y: bounds.height * 0.08,
                          width: bounds.width * 0.83, height: bounds.height * 0.47).integral
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
        var lastGameForeground: Bool?
        func valid() -> Bool {
            let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            if lastGameForeground != foreground {
                emit("focus_observed", ["game_foreground": foreground, "targeted_input": background])
                lastGameForeground = foreground
            }
            // Targeted input preserves the user's focus choice, including watching WoW.
            guard background || foreground else {
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
            func dismissCharacterError(_ screen: CGImage) async throws -> CGImage {
                guard try containsText(section(screen, 0.2, 0.32, 0.6, 0.07), ["Lua錯誤", "Lua 錯誤"]) else { return screen }
                guard valid() else { throw NSError(domain: "Pre-go lost focus or geometry", code: 3) }
                try await clickAt(CGPoint(x: bounds.minX+0.776*bounds.width,
                                         y: bounds.minY+0.349*bounds.height), .left)
                try await Task.sleep(for: .milliseconds(300))
                let after = try await capture()
                guard try !containsText(section(after, 0.2, 0.32, 0.6, 0.07), ["Lua錯誤", "Lua 錯誤"]) else {
                    throw NSError(domain: "Pre-go character error still open", code: 3)
                }
                emit("dismissed_character_beta_error")
                return after
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
            screen = try await dismissCharacterError(screen)
            try await hover(0.0725, 0.460)
            screen = try await capture()
            let equipment = section(screen, 0.075, 0.28, 0.21, 0.19)
            save(equipment, directory.appendingPathComponent("rod.jpg"))
            var rod = try containsText(equipment, ["魚竿", "釣竿", "Fishing Pole"])
            try await press(8) // Close character sheet.
            if !rod {
                emit("pre_go_switching_from_main_weapon")
                // Recognise the rod icon first; tooltip search is the fallback.
                // Verify the tooltip before equipping; never click an unknown item.
                try await press(11) // B: open combined bag.
                screen = try await capture()
                save(screen, directory.appendingPathComponent("bag-before-search.jpg"))
                var bagX = 0.924, bagY = 0.789
                if let match = rodIconCandidate(screen) {
                    bagX = match.x; bagY = match.y
                    emit("pre_go_rod_icon_candidate", ["x": bagX, "y": bagY, "correlation": match.score])
                } else { emit("pre_go_rod_icon_not_found") }
                try await hover(bagX, bagY)
                screen = try await capture()
                var bagItem = section(screen, 0.60, 0.45, 0.32, 0.48)
                if !(try containsText(bagItem, ["魚竿", "釣竿", "Fishing Pole"])) {
                    // Bounded default-layout bag search; all preparation stays local.
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
                guard valid() else { throw NSError(domain: "Pre-go lost focus or geometry", code: 3) }
                try await clickAt(CGPoint(x: bounds.minX+bagX*bounds.width,
                                         y: bounds.minY+bagY*bounds.height), .right)
                try await Task.sleep(for: .milliseconds(400))
                try await press(11) // Close bag.
                try await press(8) // Reopen equipment and verify actual equipped rod.
                screen = try await capture()
                screen = try await dismissCharacterError(screen)
                try await hover(0.0725, 0.460)
                screen = try await capture()
                let equipped = section(screen, 0.075, 0.28, 0.21, 0.19)
                save(equipped, directory.appendingPathComponent("equipped-rod.jpg"))
                rod = try containsText(equipped, ["魚竿", "釣竿", "Fishing Pole"])
                try await press(8)
            }
            guard rod else { emit("pre_go_rod_unconfirmed"); return }
            emit("pre_go_rod_verified")
            try await press(19, .maskShift) // Same configured page for both policies.
            try await hover(0.227, 0.981)
            screen = try await capture()
            let skill = section(screen, 0.82, 0.75, 0.18, 0.2)
            save(skill, directory.appendingPathComponent("skill.jpg"))
            guard try containsText(skill, ["釣魚", "Fishing"]) else {
                emit("pre_go_fishing_slot_unconfirmed"); return
            }
            var page = section(screen, 0.201, 0.950, 0.020, 0.05)
            if !pageIsTwo(page) {
                save(page, directory.appendingPathComponent("page-initial.png"))
                try await Task.sleep(for: .milliseconds(250))
                screen = try await capture()
                page = section(screen, 0.201, 0.950, 0.020, 0.05)
                emit("pre_go_page_recheck", ["confirmed": pageIsTwo(page)])
            }
            save(page, directory.appendingPathComponent("page.jpg"))
            guard pageIsTwo(page) else {
                emit("pre_go_page_two_unconfirmed"); return
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
        emit("ready", ["output": directory.path, "width": width, "height": height,
                       "crop": [crop.minX, crop.minY, crop.width, crop.height],
                       "execute": execute])
        if probe { return }
        let chatConfig = SCStreamConfiguration()
        chatConfig.sourceRect = CGRect(x:bounds.width*0.01,y:bounds.height*0.72,
                                       width:bounds.width*0.30,height:bounds.height*0.20)
        chatConfig.width=Int(bounds.width*0.30); chatConfig.height=Int(bounds.height*0.20)
        chatConfig.showsCursor=false
        let chatBefore = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:chatConfig)
        save(chatBefore,directory.appendingPathComponent("chat-before.jpg"))
        guard valid() else { emit("stopped_before_cast"); return }
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
        let referencePixels = imagePixels(cleared, width: width, height: height)
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
            let full = SCStreamConfiguration()
            full.width = Int(bounds.width); full.height = Int(bounds.height); full.showsCursor = false
            let failed = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
            save(failed, directory.appendingPathComponent("cast-failed.jpg"))
            let words = try readText(section(failed, 0.25, 0.05, 0.50, 0.30)).compactMap { $0.topCandidates(1).first?.string }
            emit("stopped_cast_not_confirmed", ["screen_text": words]); return
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
            var target: Blob?, tracker: FloatTracker?, previous: [UInt8]?, priorImage: CGImage?
            var candidateTracks: [(latest: Blob, origin: Blob, frames: Int)] = []
            var loop = FishingLoop(), missing = 0
            var requested: MotionWindow?, lastSubmitted: Blob?
            var lastRequest = -100.0, lastTimestamp = -1.0
            var submittedChange = false
            func invalidate(_ reason: String) {
                loop.invalidate(); jev?.discardPending(); requested = nil
                lastSubmitted = nil; submittedChange = false
                emit("observation_invalidated", ["reason": reason, "generation": loop.generation])
            }
            while ProcessInfo.processInfo.systemUptime-castAt < 30 {
                guard valid() else { emit("stopped_focus_or_geometry"); return }
                let iterationAt = ProcessInfo.processInfo.systemUptime
                if loop.expired(at: iterationAt) { emit("stopped_bite_not_recovered"); return }
                if target == nil && iterationAt-castAt > 6 {
                    emit("stopped_no_visible_float"); return
                }
                guard let (image, timestamp) = source.latest() else {
                    try await Task.sleep(for: .milliseconds(25)); continue
                }
                let frameAge = CMClockGetTime(CMClockGetHostTimeClock()).seconds-timestamp
                guard frameAge.isFinite, (0..<0.35).contains(frameAge) else {
                    invalidate("stale_capture")
                    try await Task.sleep(for: .milliseconds(100)); continue
                }
                guard timestamp != lastTimestamp else {
                    try await Task.sleep(for: .milliseconds(25)); continue
                }
                defer { priorImage = image }
                lastTimestamp = timestamp
                let captureAt = iterationAt-frameAge
                let pixels = imagePixels(image, width: width, height: height)
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
                background /= Double(max(count, 1)); previous = pixels
                // The acquisition image is no longer valid after a camera change.
                // Stop for review instead of adding a second, guess-based acquisition path.
                guard background <= 8 else { emit("stopped_camera_motion"); return }
                let candidate: Blob?
                if let tracker {
                    candidate = tracker.observe(image)
                } else if iterationAt-castAt > 0.8 {
                    let fresh = changedObjects(pixels, reference: referencePixels, width: width, height: height).filter { item in
                        let x = (crop.minX+item.x*crop.width/Double(width))/bounds.width
                        let y = (crop.minY+item.y*crop.height/Double(height))/bounds.height
                        return !(x > 0.40 && x < 0.60 && y > 0.43)
                    }
                    candidateTracks = fresh.map { item in
                        if let old = candidateTracks.min(by: { distance($0.latest,item) < distance($1.latest,item) }),
                           distance(old.latest,item) < 3, distance(old.origin,item) < 3 {
                            return (item, old.origin, old.frames+1)
                        }
                        return (item, item, 1)
                    }
                    let stable = candidateTracks.filter { $0.frames >= 4 }.sorted { $0.latest.novelty > $1.latest.novelty }
                    candidate = stable.first.flatMap { best in
                        stable.count == 1 || best.latest.novelty > stable[1].latest.novelty*2 ? best.latest : nil
                    }
                } else { candidate = nil }
                let now = ProcessInfo.processInfo.systemUptime
                guard now-captureAt < 0.35 else { invalidate("processing_deadline"); continue }
                if let current = candidate {
                    if target == nil {
                        tracker = try FloatTracker(current, image: image)
                        emit("target_acquired", ["x": current.x, "y": current.y, "area": current.area, "novelty": current.novelty])
                        save(image, directory.appendingPathComponent("acquired.jpg"))
                        emit("post_cast_target_candidate_observed")
                    }
                    if missing > 0 { emit("tracking_restored_waiting_for_stable_history", ["gap_frames": missing]) }
                    target = current; missing = 0
                    let generation = loop.generation
                    loop.observe(current, capturedAt: captureAt, now: now, background: background)
                    if loop.generation != generation {
                        jev?.discardPending(); requested = nil
                        lastSubmitted = nil; submittedChange = false
                        emit("observation_invalidated", ["reason": "capture_discontinuity", "generation": loop.generation])
                    }
                    if let window = loop.window {
                        let drop = window.drop
                        emit("sample", ["x": current.x, "y": current.y, "capture_seconds": captureAt-started,
                                        "drop": drop, "background_change": background,
                                        "pixel_match_correlation": current.matchCorrelation,
                                        "generation": window.generation])
                        var armed = false
                        if let jev {
                            if let answer = jev.take() {
                                emit("jev_response", answer.details)
                                guard answer.action != "ERROR" else { emit("stopped_jev_error"); return }
                                if reelIsSupported(answer), let sent = requested {
                                    armed = loop.arm(sent, now: now)
                                    if !armed { emit("jev_stale_response") }
                                } else if answer.action == "REEL" {
                                    emit("jev_reel_abstained", ["reason": "probability_below_0.85"])
                                }
                                requested = nil
                            }
                            // Change-triggered scheduling, not an A verdict passed to B.
                            if !window.changed { submittedChange = false }
                            let novel = !submittedChange || lastSubmitted.map { distance($0,current) > 1.5 } == true
                            if !loop.armed && !jev.busy && now-lastRequest > 0.2
                                && ((window.changed && novel) || now-lastRequest > 4) {
                                guard jev.calls < jev.limit else { emit("stopped_jev_budget"); return }
                                emit("policy_observation", ["call": jev.calls+1, "generation": window.generation,
                                    "capture_seconds": window.current.capturedAt-started])
                                try jev.start(state: window.state, question: fishingQuestion, emit: emit)
                                requested = window; lastRequest = now; lastSubmitted = current
                                submittedChange = window.changed
                            }
                        } else if window.rulesReel { armed = loop.arm(window, now: now) }
                        if armed {
                            if let tracker {
                                if let patch = image.cropping(to: tracker.crop) { save(patch, directory.appendingPathComponent("signal.jpg")) }
                                if let patch = priorImage?.cropping(to: tracker.crop) { save(patch, directory.appendingPathComponent("pre-signal.jpg")) }
                            }
                            emit("bite_detected_waiting_for_return", ["drop": drop])
                        }
                        if let current = loop.takeClick(at: ProcessInfo.processInfo.systemUptime) {
                            let point = CGPoint(x:bounds.minX+crop.minX+current.x*crop.width/Double(width),
                                                y:bounds.minY+crop.minY+current.y*crop.height/Double(height))
                            emit("bite_candidate", ["drop": drop, "desktop_x": point.x, "desktop_y": point.y])
                            guard valid(), ProcessInfo.processInfo.systemUptime-captureAt < 0.2 else {
                                emit("stopped_before_click"); return
                            }
                            try await clickAt(point, .right)
                            emit("right_click")
                            save(image, directory.appendingPathComponent("bite.jpg"))
                            try await Task.sleep(for: .milliseconds(50))
                            let full = SCStreamConfiguration()
                            full.width = Int(bounds.width); full.height = Int(bounds.height)
                            full.showsCursor = false
                            var after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
                            let lootRect = CGRect(x: max(0, point.x-bounds.minX-280),
                                y: max(0, point.y-bounds.minY-180), width: 800, height: 400)
                                .intersection(CGRect(x: 0, y: 0, width: after.width, height: after.height))
                            var lootImage = after.cropping(to: lootRect)!
                            save(lootImage, directory.appendingPathComponent("after.jpg"))
                            // Observe the early window transition: auto-loot can close it before a delayed check.
                            var visibleLootImage: CGImage?
                            var closedWithoutClick = false
                            for _ in 0..<8 {
                                guard valid() else { emit("stopped_focus_or_geometry"); return }
                                if lootClose(lootImage) != nil {
                                    visibleLootImage = lootImage
                                } else if visibleLootImage != nil {
                                    closedWithoutClick = true; break
                                }
                                try await Task.sleep(for: .milliseconds(80))
                                after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
                                lootImage = after.cropping(to: lootRect)!
                            }
                            if let visibleLootImage { save(visibleLootImage,directory.appendingPathComponent("after.jpg")) }
                            if closedWithoutClick || (visibleLootImage != nil && lootClose(lootImage) == nil) {
                                save(lootImage,directory.appendingPathComponent("collected.jpg"))
                                emit("loot_collected", ["item": "<unreadable>", "labels_observed": [], "loot_clicks": 0,
                                    "completion_method": "observed_window_closed_without_script_click"])
                                return
                            }
                            var layout = try lootLayout(lootImage)
                            guard layout != nil else {
                                save(after,directory.appendingPathComponent("retrieval-failed.jpg"))
                                let text = (try? readText(section(after,0.25,0.05,0.5,0.3))) ?? []
                                let chatAfter = section(after,0.01,0.72,0.30,0.20)
                                save(chatAfter,directory.appendingPathComponent("chat-after.jpg"))
                                let beforeWords=((try? readText(chatBefore)) ?? []).compactMap { $0.topCandidates(1).first?.string }
                                let afterWords=((try? readText(chatAfter)) ?? []).compactMap { $0.topCandidates(1).first?.string }
                                emit("retrieval_unverified", ["screen_text": text.compactMap { $0.topCandidates(1).first?.string },
                                    "chat_before_ocr": beforeWords, "chat_after_ocr": afterWords]); return
                            }
                            var observedLabels = [String]()
                            for index in 1...8 {
                                guard valid(), let row = layout?.rows.first else {
                                    emit("loot_layout_unconfirmed", ["labels_observed": observedLabels]); return
                                }
                                let itemImage = lootImage.cropping(to: row.integral)!
                                save(itemImage,directory.appendingPathComponent("loot-row-\(index).jpg"))
                                let words = ((try? readText(itemImage)) ?? []).compactMap { $0.topCandidates(1).first?.string }
                                let label = words.max { $0.count < $1.count } ?? "<unreadable>"
                                observedLabels.append(label)
                                emit("loot_item_observed", ["label_ocr": label, "ocr_text": words, "click_number": index])
                                // Click the visible item control. No name, language or item-class whitelist.
                                let itemPoint = CGPoint(x: bounds.minX+lootRect.minX+row.midX,
                                                        y: bounds.minY+lootRect.minY+row.midY)
                                guard valid() else { emit("stopped_before_loot_click"); return }
                                try await clickAt(itemPoint,.left)
                                try await Task.sleep(for: .milliseconds(500))
                                after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: full)
                                lootImage = after.cropping(to: lootRect)!
                                save(lootImage,directory.appendingPathComponent("collected.jpg"))
                                layout = try lootLayout(lootImage)
                                if layout == nil {
                                    emit("loot_collected", ["item": observedLabels.joined(separator: ", "),
                                        "labels_observed": observedLabels, "loot_clicks": index])
                                    return
                                }
                            }
                            emit("loot_batch_limit", ["labels_observed": observedLabels])
                            return
                        }
                    }
                } else if target != nil {
                    missing += 1
                    invalidate("tracker_unavailable")
                    emit("tracking_temporarily_unavailable", ["frames": missing, "background_change": background])
                    if missing == 1 { save(image, directory.appendingPathComponent("first-missing.jpg")) }
                    if missing > 3 { emit("stopped_target_lost"); return }
                }
                let remaining = 0.1-(ProcessInfo.processInfo.systemUptime-iterationAt)
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
