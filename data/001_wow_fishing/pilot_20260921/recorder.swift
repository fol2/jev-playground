import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation

final class Frames: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var count=0
    init(_ url:URL) throws {
        writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:1000,AVVideoHeightKey:550,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:2000000,AVVideoMaxKeyFrameIntervalKey:30]])
        input.expectsMediaDataInRealTime=true
        writer.add(input); writer.startWriting()
    }
    func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType) {
        guard type == .screen, sample.isValid, CMSampleBufferGetImageBuffer(sample) != nil else {return}
        guard let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]], let status=attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else {return}
        if count == 0 {writer.startSession(atSourceTime:CMSampleBufferGetPresentationTimeStamp(sample));print("RECORDING");fflush(stdout)}
        if input.isReadyForMoreMediaData {
            if input.append(sample) {count+=1}
            else {print("WRITE ERROR",writer.error as Any)}
        }
    }
}
@main struct Pilot {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard #available(macOS 15.0, *) else { return }
        let seconds = Int(CommandLine.arguments[1])!, url=URL(fileURLWithPath:CommandLine.arguments[2])
        guard (1...45).contains(seconds) else { return }
        let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
        let window=content.windows.filter {$0.owningApplication?.bundleIdentifier == "com.blizzard.worldofwarcraft"}.max {$0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height}!
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let config=SCStreamConfiguration()
        let crop=CGRect(x:750,y:250,width:1000,height:550)
        config.sourceRect=crop; config.width=1000; config.height=550
        config.minimumFrameInterval=CMTime(value:1,timescale:30)
        config.queueDepth=8; config.showsCursor=true; config.capturesAudio=false
        let stream=SCStream(filter:filter,configuration:config,delegate:nil)
        let frames=try Frames(url), queue=DispatchQueue(label:"pilot.frames")
        try stream.addStreamOutput(frames,type:.screen,sampleHandlerQueue:queue)
        let meta:[String:Any] = ["window_id":window.windowID,"window_bounds":NSStringFromRect(window.frame),"crop_window_coordinates":[750,250,1000,550],"output_pixels":[1000,550],"requested_fps":30,"seconds":seconds,"audio":false,"cursor":true,"started_utc":ISO8601DateFormatter().string(from:Date())]
        try JSONSerialization.data(withJSONObject:meta,options:[.prettyPrinted,.sortedKeys]).write(to:url.deletingPathExtension().appendingPathExtension("json"))
        try await stream.startCapture()
        try await Task.sleep(for:.seconds(seconds))
        try await stream.stopCapture()
        queue.sync {frames.input.markAsFinished()}
        await frames.writer.finishWriting()
        print("FRAMES",frames.count,"STATUS",frames.writer.status.rawValue)
        print("Saved \(url.path)")
    }
}
