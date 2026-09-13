import CoreGraphics
import Foundation
import AppKit

let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : ""
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

for w in all {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    let name = (w[kCGWindowName as String] as? String) ?? ""
    guard filter.isEmpty || owner.lowercased().contains(filter) || name.lowercased().contains(filter) else { continue }
    let wid = (w[kCGWindowNumber as String] as? UInt32) ?? 0
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let onscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    let alpha = (w[kCGWindowAlpha as String] as? Double) ?? -1
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    print("id=\(wid) owner=\(owner) name=\(name) bounds=(\(b["X"] ?? 0),\(b["Y"] ?? 0),\(b["Width"] ?? 0),\(b["Height"] ?? 0)) onscreen=\(onscreen) alpha=\(alpha) layer=\(layer)")
}
