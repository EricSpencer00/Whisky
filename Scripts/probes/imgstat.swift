import AppKit
import Foundation

/* Reports how much a captured window actually contains. A blank window and a
 * rendered one are otherwise indistinguishable from a script. */
guard CommandLine.arguments.count > 1,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("verdict=unreadable")
    exit(1)
}
let width = cg.width, height = cg.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("verdict=unreadable")
    exit(1)
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

var colours = Set<UInt32>()
var sum = [Double](repeating: 0, count: 3)
var sumsq = [Double](repeating: 0, count: 3)
let count = Double(width * height)
for i in stride(from: 0, to: pixels.count, by: 4) {
    let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
    colours.insert(UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
    for (c, v) in [r, g, b].enumerated() {
        sum[c] += Double(v); sumsq[c] += Double(v) * Double(v)
    }
}
var maxStdDev = 0.0
for c in 0..<3 {
    let mean = sum[c] / count
    maxStdDev = max(maxStdDev, (sumsq[c] / count - mean * mean).squareRoot())
}
let mean = sum.reduce(0, +) / (count * 3)
let verdict = colours.count <= 4 ? "blank" : (maxStdDev < 3.0 ? "near-blank" : "renders")
print(String(format: "verdict=%@ size=%dx%d colours=%d stddev=%.1f mean=%.0f r=%.0f g=%.0f b=%.0f",
             verdict, width, height, colours.count, maxStdDev, mean,
             sum[0] / count, sum[1] / count, sum[2] / count))
