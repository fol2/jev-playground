// Frozen reference from eb6356385b5853ab61a00de31641051c0cb55c34/motion.swift.
// Differential tests protect localisation/abstention, not catch-rate claims.
// The two decision constants are parameters here, defaulting to the frozen values, so the
// suite can prove it still holds cases that those constants actually decide. Called with
// defaults this is byte-for-byte the original behaviour.
import Foundation
func referenceMotion(previous: [Double], current: [Double], width: Int, height: Int,
                 centre: CGPoint, accept: Double = 0.55, margin: Double = 0.10) -> PixelMotion? {
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
    guard best.value>=accept,best.value-alternative>=margin,
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

struct Generator {
    var seed: UInt64 = 0x4a4556
    mutating func byte() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 32) & 255)
    }
}

@main struct MotionChecks {
    static func main() throws {
        var checks = 0, accepted = 0, rejected = 0, random = Generator()
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            precondition(condition, message)
        }
        func equal(_ a: PixelMotion?, _ b: PixelMotion?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (a?, b?):
                return abs(a.dx-b.dx) < 1e-8 && abs(a.dy-b.dy) < 1e-8
                    && abs(a.correlation-b.correlation) < 1e-8 && abs(a.separation-b.separation) < 1e-8
            default: return false
            }
        }
        var examples: [([Double], [Double], Int, Int, CGPoint)] = []
        for n in 0..<160 {
            let w = [20, 32, 44, 64, 160][n % 5], h = w+3
            let before = (0..<w*h).map { _ in random.byte() }
            var after = (0..<w*h).map { _ in random.byte() }
            let dx = n % 29-14, dy = (n*7) % 29-14
            for y in 0..<h { for x in 0..<w {
                let nx = x+dx, ny = y+dy
                if nx >= 0 && nx < w && ny >= 0 && ny < h {
                    after[ny*w+nx] = before[y*w+x]*0.9+5+random.byte()/255
                }
            }}
            let centre = CGPoint(x: [10.0, Double(w)/2+0.25, Double(w)-10][n % 3],
                                 y: [10.0, Double(h)/2, Double(h)-10][(n/3) % 3])
            examples.append((before, after, w, h, centre))
        }
        for (before, after, w, h, centre) in examples {
            let old = referenceMotion(previous: before, current: after, width: w, height: h, centre: centre)
            let new = pixelMotion(previous: before, current: after, width: w, height: h, centre: centre)
            check(equal(old, new), "differential mismatch at case \(checks)")
            if new == nil { rejected += 1 } else { accepted += 1 }
        }
        // Cases the two decision constants actually decide. Without these the corpus is
        // bimodal, near-ideal matches or structural rejections, and either threshold can be
        // moved without a single check reacting. The coverage assertions below fail if that
        // ever becomes true again, so the sweep cannot silently drift out of the band.
        var decidedByAccept = 0, decidedByMargin = 0
        for step in 0..<24 {
            let side = 64, cx = 32, cy = 32
            var noise = Generator()
            let previous = (0..<side*side).map { _ in noise.byte() }
            var next = (0..<side*side).map { _ in noise.byte() }
            let anchor = CGPoint(x: Double(cx), y: Double(cy))
            if step < 12 {
                // Signal blended toward noise: sweeps correlation down through the accept threshold.
                let alpha = 0.28+Double(step)*0.02
                for y in 0..<side { for x in 0..<side {
                    let nx = x+3, ny = y-2
                    if nx >= 0 && nx < side && ny >= 0 && ny < side {
                        next[ny*side+nx] = previous[y*side+x]*alpha+noise.byte()*(1-alpha)
                    }
                }}
            } else {
                // Two distinct non-overlapping in-radius copies of the anchor: a confident match
                // with a real rival, which sweeps the ambiguity margin through its threshold.
                let beta = 0.66+Double(step-12)*0.02
                for (offset, gain) in [(11, 1.0), (-11, beta)] {
                    for y in -10..<10 { for x in -10..<10 {
                        next[(cy+y)*side+cx+x+offset] = previous[(cy+y)*side+cx+x]*gain+noise.byte()*(1-gain)
                    }}
                }
            }
            let old = referenceMotion(previous: previous, current: next, width: side, height: side, centre: anchor)
            let new = pixelMotion(previous: previous, current: next, width: side, height: side, centre: anchor)
            check(equal(old, new), "degraded differential mismatch at case \(checks)")
            if new == nil { rejected += 1 } else { accepted += 1 }
            func acts(_ accept: Double, _ margin: Double) -> Bool {
                referenceMotion(previous: previous, current: next, width: side, height: side,
                                centre: anchor, accept: accept, margin: margin) != nil
            }
            if acts(0.50, 0.10) != acts(0.55, 0.10) { decidedByAccept += 1 }
            if acts(0.55, 0.02) != acts(0.55, 0.10) { decidedByMargin += 1 }
        }
        check(decidedByAccept > 0, "no differential case is decided by the 0.55 accept threshold")
        check(decidedByMargin > 0, "no differential case is decided by the 0.10 ambiguity margin")

        let w = 64, centre = CGPoint(x: 32, y: 32)
        let before = (0..<w*w).map { _ in random.byte() }
        let flat = [Double](repeating: 42, count: w*w)
        for image in [flat, (0..<w*w).map { Double(($0 % 4)*60) }] {
            check(pixelMotion(previous: image, current: image, width: w, height: w, centre: centre) == nil,
                  "textureless/repeated evidence must abstain")
        }
        for bad in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude] {
            var invalid = before; invalid[32*w+32] = bad
            check(pixelMotion(previous: before, current: invalid, width: w, height: w, centre: centre) == nil,
                  "non-finite/overflowing search evidence must abstain")
            check(pixelMotion(previous: invalid, current: before, width: w, height: w, centre: centre) == nil,
                  "non-finite/overflowing anchor evidence must abstain")
        }
        check(pixelMotion(previous: before, current: [], width: w, height: w, centre: centre) == nil, "bad count")
        check(pixelMotion(previous: [], current: [], width: Int.max, height: 20, centre: centre) == nil, "overflow dimensions")
        check(pixelMotion(previous: before, current: before, width: w, height: w,
                          centre: CGPoint(x: Double.nan, y: 32)) == nil, "invalid centre")
        check(accepted > 0 && rejected > 0, "exercise accepted and abstained matches")
        print("\(checks) motion checks passed; \(accepted) accepted / \(rejected) abstained differential cases; no capture/input/provider.")
        if CommandLine.arguments.contains("--benchmark") {
            // Non-gating microbenchmark: alternate order, compare medians, never assert a speed ratio.
            let example = examples.last!
            let testCentre = CGPoint(x: 80, y: 80)
            var checksum = 0.0
            func elapsed(_ old: Bool) -> Double {
                let start = ProcessInfo.processInfo.systemUptime
                for _ in 0..<1000 {
                    let m = old ? referenceMotion(previous: example.0, current: example.0, width: example.2,
                                                  height: example.3, centre: testCentre)
                                : pixelMotion(previous: example.0, current: example.0, width: example.2,
                                              height: example.3, centre: testCentre)
                    checksum += m?.correlation ?? 0
                }
                return ProcessInfo.processInfo.systemUptime-start
            }
            _ = elapsed(true); _ = elapsed(false)
            var oldTimes = [Double](), newTimes = [Double]()
            for round in 0..<7 {
                if round % 2 == 0 { oldTimes.append(elapsed(true)); newTimes.append(elapsed(false)) }
                else { newTimes.append(elapsed(false)); oldTimes.append(elapsed(true)) }
            }
            let result: [String: Any] = ["kind": "synthetic-matcher-microbenchmark", "iterations_per_sample": 1000,
                "old_seconds": oldTimes, "new_seconds": newTimes, "checksum": checksum,
                "median_speedup": oldTimes.sorted()[3]/newTimes.sorted()[3]]
            print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
        }
    }
}
