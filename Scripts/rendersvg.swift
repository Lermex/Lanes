import AppKit
import WebKit

// rendersvg <in.svg> <out.png> [size]: rasterises an SVG with WebKit (full filter support) on a
// transparent canvas, sized to the given pixel width regardless of the display's scale factor.
let arguments = CommandLine.arguments
let size = arguments.count > 3 ? Int(arguments[3])! : 1024
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

final class Renderer: NSObject, WKNavigationDelegate {
  let window: NSWindow
  let web: WKWebView

  override init() {
    let frame = NSRect(x: -10000, y: -10000, width: size, height: size)
    window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    web = WKWebView(frame: NSRect(origin: .zero, size: frame.size))
    super.init()
    web.setValue(false, forKey: "drawsBackground")
    web.navigationDelegate = self
    window.contentView = web
    window.orderFrontRegardless()
  }

  func start() {
    web.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let configuration = WKSnapshotConfiguration()
    configuration.rect = NSRect(x: 0, y: 0, width: size, height: size)
    configuration.snapshotWidth = NSNumber(value: size)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      webView.takeSnapshot(with: configuration) { image, error in
        guard let image else {
          print("snapshot failed: \(error.map { "\($0)" } ?? "no image")")
          exit(1)
        }
        // the snapshot carries the display's scale factor; resample to exactly `size` pixels
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
        print("rendered \(bitmap.pixelsWide)")
        exit(0)
      }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    print("load failed: \(error)")
    exit(1)
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.start()
app.run()
