// Direct image correspondence. Correlation measures appearance agreement, not bite probability.
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct PixelMotion {
    let dx: Double
    let dy: Double
    let correlation: Double
    let separation: Double
}

#if canImport(CoreGraphics) && !CORE_TESTS
func greyPixels(_ image: CGImage) -> [Double] {
    let pixels=imagePixels(image,width:image.width,height:image.height)
    return (0..<image.width*image.height).map {
        let i=$0*4
        return 0.299*Double(pixels[i])+0.587*Double(pixels[i+1])+0.114*Double(pixels[i+2])
    }
}

#endif

func supportsMotionTemplate(_ centre: CGPoint, width: Int, height: Int) -> Bool {
    centre.x.isFinite && centre.y.isFinite && centre.x >= 10 && centre.y >= 10
        && centre.x.rounded()+10 <= Double(width) && centre.y.rounded()+10 <= Double(height)
}

func pixelMotion(previous: [Double], current: [Double], width: Int, height: Int,
                 centre: CGPoint) -> PixelMotion? {
    guard width >= 20, height >= 20, width <= Int.max/height,
          centre.x.isFinite, centre.y.isFinite,
          supportsMotionTemplate(centre, width: width, height: height) else { return nil }
    let half=10, radius=12, cx=Int(centre.x.rounded()), cy=Int(centre.y.rounded())
    guard previous.count==width*height,current.count==previous.count,
          cx>=half,cy>=half,cx+half<=width,cy+half<=height else {return nil}
    var template=[Double]()
    for y in cy-half..<cy+half {for x in cx-half..<cx+half {template.append(previous[y*width+x])}}
    let count=Double(template.count), mean=template.reduce(0,+)/count
    template=template.map {$0-mean}
    let norm=sqrt(template.reduce(0){$0+$1*$1})
    guard norm>1 else {return nil}
    template=template.map {$0/norm}
    var scores=[(value:Double,dx:Int,dy:Int)]()
    let side = radius*2+1
    var surface = [Double](repeating: -.infinity, count: side*side)
    for dy in -radius...radius {for dx in -radius...radius {
        let x0=cx-half+dx,y0=cy-half+dy
        guard x0>=0,y0>=0,x0+half*2<=width,y0+half*2<=height else {continue}
        var sum=0.0,squared=0.0,dot=0.0,index=0
        for y in y0..<y0+half*2 {for x in x0..<x0+half*2 {
            let value=current[y*width+x]
            sum+=value;squared+=value*value;dot+=value*template[index];index+=1
        }}
        let correlation=dot/sqrt(max(1,squared-sum*sum/count))
        scores.append((correlation,dx,dy))
        surface[(dy+radius)*side+dx+radius] = correlation
    }}
    guard let best=scores.max(by:{$0.value<$1.value}) else {return nil}
    // Compare distinct local maxima, not the shoulder of the same broad peak.
    func peak(_ candidate: (value: Double, dx: Int, dy: Int)) -> Bool {
        for dy in -1...1 { for dx in -1...1 {
            let x=candidate.dx+radius+dx, y=candidate.dy+radius+dy
            if x>=0 && x<side && y>=0 && y<side && surface[y*side+x]>candidate.value { return false }
        }}
        return true
    }
    let alternative=scores.filter {abs($0.dx-best.dx)+abs($0.dy-best.dy)>3 && peak($0)}.map(\.value).max() ?? 0
    // A peak at the search boundary may be a clipped larger movement, not a location.
    guard best.value>=0.55,best.value-alternative>=0.10,
          abs(best.dx)<radius,abs(best.dy)<radius else {return nil}
    func refine(_ horizontal:Bool) -> Double {
        let left=scores.first {$0.dx==best.dx-(horizontal ? 1:0) && $0.dy==best.dy-(horizontal ? 0:1)}?.value
        let right=scores.first {$0.dx==best.dx+(horizontal ? 1:0) && $0.dy==best.dy+(horizontal ? 0:1)}?.value
        guard let left,let right else {return 0}
        let divisor=left-2*best.value+right
        guard abs(divisor)>0.0001 else {return 0}
        return max(-0.5,min(0.5,0.5*(left-right)/divisor))
    }
    return PixelMotion(dx:Double(best.dx)+refine(true),dy:Double(best.dy)+refine(false),
                       correlation:min(1,best.value),separation:best.value-alternative)
}
