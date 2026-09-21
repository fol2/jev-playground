// Language-independent loot controls. OCR is optional metadata, never an action gate.
import Foundation
import CoreGraphics
import ImageIO
import Vision

func lootClose(_ image: CGImage) -> CGPoint? {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("loot-close.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
          let reference = CGImageSourceCreateImageAtIndex(source,0,nil) else { return nil }
    func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0,count: image.width*image.height*4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress,width:image.width,height:image.height,
                bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return pixels
    }
    func grey(_ pixels: [UInt8], _ i: Int) -> Double {
        (Double(pixels[i])+Double(pixels[i+1])+Double(pixels[i+2]))/3
    }
    let ref=rgba(reference), pixels=rgba(image), width=image.width, height=image.height
    guard width>=24, height>=24 else { return nil }
    var expected = [Double]()
    for y in stride(from:0,to:24,by:2) {
        for x in stride(from:0,to:24,by:2) { expected.append(grey(ref,(y*24+x)*4)) }
    }
    let mean=expected.reduce(0,+)/144
    expected=expected.map { $0-mean }
    let norm=sqrt(expected.reduce(0) { $0+$1*$1 })
    expected=expected.map { $0/max(1,norm) }
    func score(_ x: Int, _ y: Int) -> Double {
        var sum=0.0, squares=0.0, dot=0.0, index=0
        for dy in stride(from:0,to:24,by:2) {
            for dx in stride(from:0,to:24,by:2) {
                let value=grey(pixels,((y+dy)*width+x+dx)*4)
                sum+=value; squares+=value*value; dot+=value*expected[index]; index+=1
            }
        }
        return dot/sqrt(max(1,squares-sum*sum/144))
    }
    var best=(x:0,y:0,score:0.0)
    for y in stride(from:0,through:height-24,by:2) {
        for x in stride(from:0,through:width-24,by:2) {
            let i=((y+12)*width+x+12)*4
            guard Int(pixels[i])-Int(pixels[i+1])>35, Int(pixels[i])-Int(pixels[i+2])>35 else { continue }
            let value=score(x,y)
            if value>best.score { best=(x,y,value) }
        }
    }
    let coarse=best
    for y in max(0,coarse.y-2)...min(height-24,coarse.y+2) {
        for x in max(0,coarse.x-2)...min(width-24,coarse.x+2) {
            let value=score(x,y)
            if value>best.score { best=(x,y,value) }
        }
    }
    guard best.score>=0.8 else { return nil }
    return CGPoint(x:best.x+12,y:best.y+12)
}

func lootLayout(_ image: CGImage) throws -> (close: CGPoint, rows: [CGRect])? {
    guard let close=lootClose(image) else { return nil }
    let width=image.width, height=image.height
    let request=VNDetectRectanglesRequest()
    request.minimumAspectRatio=0.15; request.maximumAspectRatio=0.4
    request.minimumSize=0.03; request.minimumConfidence=0.6
    request.quadratureTolerance=20; request.maximumObservations=12
    try VNImageRequestHandler(cgImage:image).perform([request])
    var rows = [CGRect]()
    for observation in request.results ?? [] {
        let r=observation.boundingBox
        let rect=CGRect(x:r.minX*CGFloat(width),y:(1-r.maxY)*CGFloat(height),
                        width:r.width*CGFloat(width),height:r.height*CGFloat(height))
        if rect.width>=120 && rect.width<=320 && rect.height>=28 && rect.height<=95
            && rect.midX>close.x-270 && rect.midX<close.x-15
            && rect.midY>close.y+20 && rect.midY<close.y+280 { rows.append(rect) }
    }
    rows.sort { $0.midY < $1.midY }
    return (close,rows)
}
