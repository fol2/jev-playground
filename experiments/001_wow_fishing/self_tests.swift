// Offline historical/image regressions; never starts capture, input or a provider request.
import AppKit
import ImageIO
import Vision

func runSelfTests() throws {
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
    guard !isBite(submerged, returned, 1.7, missingFrames: 2, missingSeconds: 0.33, missingBackground: 1.68),
          !isBite(submerged, returned, 1.7, missingFrames: 2, missingSeconds: 0.33, missingBackground: 12),
          !isBite(submerged, returned, 1.7, missingFrames: 2, missingSeconds: 2, missingBackground: 1),
          !isBite(submerged, returned, 1.7) else {
        throw NSError(domain: "Regression: tracking gaps cannot establish submersion", code: 13)
    }
    guard !compactFloatShape(2, 24), compactFloatShape(8, 10) else {
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
    func floatFixture(_ green: Bool, _ feather: Bool) -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(red: green ? 0.3 : 0.6, green: 0.5, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 32, y: 32, width: 8, height: 8))
        if feather {
            context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.05, alpha: 1))
            context.fill(CGRect(x: 22, y: 42, width: 10, height: 2))
        }
        return context.makeImage()!
    }
    let blankContext=CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    blankContext.setFillColor(CGColor(red:0.1,green:0.2,blue:0.4,alpha:1))
    blankContext.fill(CGRect(x:0,y:0,width:64,height:64))
    let blankPixels=imagePixels(blankContext.makeImage()!,width:64,height:64)
    for (green,feather) in [(true,true),(false,true),(true,false)] {
        let image=floatFixture(green,feather)
        guard changedObjects(imagePixels(image,width:64,height:64),reference:blankPixels,width:64,height:64).count == 1 else {
            print("Regression: colour-independent new object recognition");exit(1)
        }
    }
    guard changedObjects(blankPixels,reference:blankPixels,width:64,height:64).isEmpty else {exit(1)}
    for stem in ["split-bobber","bobber-no-red"] {
        func fixture(_ suffix:String) -> CGImage {
            let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent(stem+suffix+".png")
            return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!
        }
        let after=fixture(""),before=fixture("-before")
        guard changedObjects(imagePixels(after,width:after.width,height:after.height),
            reference:imagePixels(before,width:after.width,height:after.height),width:after.width,height:after.height).count == 1 else {
            print("Regression: new float not uniquely detected in \(stem)");exit(1)
        }
    }
    let lootURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("loot-layout.png")
    let lootSource = CGImageSourceCreateWithURL(lootURL as CFURL,nil)!
    let loot = CGImageSourceCreateImageAtIndex(lootSource,0,nil)!
    guard try lootLayout(loot)?.rows.count == 1 else { print("Regression: loot row missing"); exit(1) }
    let textless = CGContext(data:nil,width:loot.width,height:loot.height,bitsPerComponent:8,
        bytesPerRow:loot.width*4,space:CGColorSpaceCreateDeviceRGB(),
        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    textless.draw(loot,in:CGRect(x:0,y:0,width:loot.width,height:loot.height))
    textless.setFillColor(CGColor(red:0.12,green:0.125,blue:0.12,alpha:1))
    textless.fill(CGRect(x:83,y:22,width:166,height:52))
    guard try lootLayout(textless.makeImage()!)?.rows.count == 1,
          try lootLayout(floatFixture(true,false)) == nil else {
        print("Regression: loot actions depend on text or accept a non-window"); exit(1)
    }
    let ordinaryDip = [
        Blob(x:601.9228,y:208.2571,area:50), Blob(x:601.8868,y:208.4219,area:51),
        Blob(x:601.8494,y:208.6081,area:51), Blob(x:601.6584,y:208.9519,area:51),
        Blob(x:601.5415,y:209.3058,area:51), Blob(x:601.6612,y:209.7750,area:51)]
    guard !isBite(ordinaryDip,Blob(x:601.4184,y:211.8466,area:52),3.5066) else {
        print("Regression: user-labelled ordinary dip triggered REEL"); exit(1)
    }
    let confidenceDropout = [Blob(x:614.87494659,y:170.13040113,area:36),
        Blob(x:614.90395355,y:169.92368650,area:36),
        Blob(x:614.94909668,y:169.75995684,area:36),
        Blob(x:614.92971802,y:171.05411434,area:36),
        Blob(x:614.93563080,y:170.87884283,area:36),
        Blob(x:614.83502102,y:170.68083429,area:37)]
    guard !isBite(confidenceDropout, Blob(x:614.89324522,y:170.42967510,area:38), 2.9698, missingFrames:1, missingSeconds:0.1071, missingBackground:2.7358) else {
        print("Regression: tracker confidence dropout treated as submersion"); exit(1)
    }
    let motionURL=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("motion-fixtures.png")
    let motionSource=CGImageSourceCreateWithURL(motionURL as CFURL,nil)!
    let motionImage=CGImageSourceCreateImageAtIndex(motionSource,0,nil)!
    for (row,expected) in [8.0,4.0,0.0,0.0].enumerated() {
        let before=motionImage.cropping(to:CGRect(x:0,y:row*64,width:64,height:64))!
        let after=motionImage.cropping(to:CGRect(x:64,y:row*64,width:64,height:64))!
        guard let motion=pixelMotion(previous:greyPixels(before),current:greyPixels(after),
            width:64,height:64,centre:CGPoint(x:32,y:32)), abs(motion.dy-expected)<0.6 else {
            print("Regression: pixel motion disagrees with labelled fixture \(row)");exit(1)
        }
    }
    print("Thirty-two local decision and acquisition checks passed; no UI, capture or provider calls.")
}
