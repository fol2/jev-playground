import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import ImageIO
import UniformTypeIdentifiers

@main struct Probe {
    @MainActor static func main() async {
        do { try await run() } catch { print("Probe stopped: \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() else { throw NSError(domain:"Existing permissions required",code:1) }
        let content = try await SCShareableContent.current
        guard let window = content.windows.filter({ $0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.bundleIdentifier == "com.blizzard.worldofwarcraft" }).max(by:{$0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height}),
              let pid = window.owningApplication?.processID else { throw NSError(domain:"WoW unavailable",code:2) }
        let beforePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        guard beforePID != pid else { throw NSError(domain:"WoW must already be in background; no activation attempted",code:3) }
        let beforePointer = CGEvent(source:nil)!.location
        let dir=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("runs/001_wow_fishing/opensource_\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let config=SCStreamConfiguration(); config.width=Int(window.frame.width); config.height=Int(window.frame.height); config.showsCursor=false
        func capture(_ name:String) async throws -> CGImage {
            let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            let dest=CGImageDestinationCreateWithURL(dir.appendingPathComponent(name) as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(dest,image,[kCGImageDestinationLossyCompressionQuality:0.6] as CFDictionary); CGImageDestinationFinalize(dest)
            return image
        }
        func hasLua(_ image:CGImage) throws -> Bool {
            let crop=image.cropping(to:CGRect(x:Double(image.width)*0.2,y:Double(image.height)*0.32,width:Double(image.width)*0.6,height:Double(image.height)*0.07))!
            let r=VNRecognizeTextRequest(); r.recognitionLanguages=["zh-Hant","en-US"]; r.usesLanguageCorrection=false
            try VNImageRequestHandler(cgImage:crop).perform([r])
            let text=(r.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined()
            return text.contains("Lua") && text.contains("錯誤")
        }
        // Open the known character sheet to expose its reproducible beta error.
        let source=CGEventSource(stateID:.privateState)
        let right = CommandLine.arguments.contains("--right")
        if !right {
        CGEvent(keyboardEventSource:source,virtualKey:8,keyDown:true)?.postToPid(pid)
        try await Task.sleep(for:.milliseconds(80))
        CGEvent(keyboardEventSource:source,virtualKey:8,keyDown:false)?.postToPid(pid)
        try await Task.sleep(for:.milliseconds(500))
        }
        let before=try await capture("before.jpg")
        let luaBefore = try hasLua(before)
        guard right ? !luaBefore : luaBefore else { throw NSError(domain:"Unexpected fixture state; no click sent",code:4) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == beforePID else { throw NSError(domain:"Foreground changed before probe",code:5) }
        let b=window.frame
        let dto=ResolvedWindowDTO(pid:pid,bundleID:"com.blizzard.worldofwarcraft",windowNumber:Int(window.windowID),title:"WoW",frameAppKit:FrameDTO(x:b.minX,y:DesktopGeometry.desktopTop()-b.maxY,width:b.width,height:b.height))
        let routing=try NativeWindowServerRoutingResolver().resolve(windowNumber:Int(window.windowID))
        let target=RoutedClickTarget(window:dto,routing:routing)
        let point=CGPoint(x:b.minX+b.width*(right ? 0.268 : 0.776),y:b.minY+b.height*(right ? 0.751 : 0.349))
        print("Dispatching one background \(right ? "right" : "left")-click; output: \(dir.path)"); fflush(stdout)
        let result=try NativeBackgroundClickTransport().dispatch(.init(target:target,eventTapPointTopLeft:point,appKitPoint:point,clickCount:1,mouseButton:right ? .right : .left))
        try await Task.sleep(for:.milliseconds(500))
        let after=try await capture("after.jpg")
        let record:[String:Any]=["upstream_commit":"52116acfe0f2f57174f5e0166881abe944cb6eeb","button":right ? "right" : "left","dispatch_success":result.dispatchSuccess,"events_prepared":result.eventsPrepared,"focus_status":result.focusStatus,"lua_before":luaBefore,"lua_after":try hasLua(after),"foreground_unchanged":NSWorkspace.shared.frontmostApplication?.processIdentifier == beforePID,"foreground_pid_before":beforePID,"foreground_pid_after":NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,"wow_pid":pid,"pointer_unchanged":CGEvent(source:nil)!.location == beforePointer,"output":dir.path]
        let data=try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]); try data.write(to:dir.appendingPathComponent("result.json")); print(String(data:data,encoding:.utf8)!)
    }
}
