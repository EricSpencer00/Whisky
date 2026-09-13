import AppKit
import Foundation
import ScreenCaptureKit

/* screencapture reads the active Space. A Wine window created while another
 * Space was in front comes back fully transparent, which reads as "the app drew
 * nothing" and is wrong. ScreenCaptureKit captures the window itself. */
let args = CommandLine.arguments
guard args.count > 2, let wantedID = UInt32(args[1]) else {
    print("usage: winshot2 <window id> <out.png>")
    exit(2)
}
let outPath = args[2]
_ = NSApplication.shared

func fail(_ message: String) -> Never {
    print("error=\(message)")
    exit(1)
}

SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
    guard let content else { fail(error?.localizedDescription ?? "no shareable content") }
    guard let window = content.windows.first(where: { $0.windowID == wantedID }) else {
        fail("window \(wantedID) not shareable")
    }
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width * 2)
    config.height = Int(window.frame.height * 2)
    config.showsCursor = false
    SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                     configuration: config) { image, err in
        guard let image else { fail(err?.localizedDescription ?? "capture failed") }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { fail("encode failed") }
        do { try data.write(to: URL(fileURLWithPath: outPath)) } catch { fail("\(error)") }
        print("wrote \(outPath) \(image.width)x\(image.height)")
        exit(0)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fail("timed out") }
RunLoop.main.run()
