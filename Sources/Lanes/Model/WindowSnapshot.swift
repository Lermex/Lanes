import AppKit
import ScreenCaptureKit

enum WindowSnapshot {
  static var directory: URL? {
    ProcessInfo.processInfo.environment["LANES_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  @MainActor
  static func capture(window chosen: NSWindow? = nil) {
    guard let directory,
      let window = chosen ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
      let content = window.contentView
    else { return }
    let view = content.superview ?? content
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    let composed = NSImage(size: view.bounds.size, flipped: false) { rect in
      NSColor.windowBackgroundColor.setFill()
      rect.fill()
      rep.draw(in: rect)
      return true
    }
    guard let tiff = composed.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else { return }
    let url = directory.appending(path: "snapshot-\(Int(Date().timeIntervalSince1970 * 10)).png")
    try? png.write(to: url)
    debugLog("snapshot \(url.path)")
  }
}

extension WindowSnapshot {
  /// The window as the window server composes it, glass and vibrancy included, which `capture`
  /// cannot render. Goes through ScreenCaptureKit, so the app needs Screen Recording access;
  /// asking for it first also registers the process, without which a granted app is still refused.
  @MainActor
  static func captureComposited(window chosen: NSWindow? = nil) async {
    guard let directory, let window = chosen ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
    let number = CGWindowID(window.windowNumber)
    guard CGRequestScreenCaptureAccess() else {
      debugLog("screenshot: Screen Recording access not granted")
      return
    }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      guard let target = content.windows.first(where: { $0.windowID == number }) else {
        debugLog("screenshot: window \(number) is not shareable")
        return
      }
      let configuration = SCStreamConfiguration()
      let scale = window.backingScaleFactor
      configuration.width = Int(target.frame.width * scale)
      configuration.height = Int(target.frame.height * scale)
      configuration.showsCursor = false
      configuration.ignoreShadowsSingleWindow = true
      configuration.captureResolution = .best
      let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appending(path: "screenshot-\(Int(Date().timeIntervalSince1970)).png")
      guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
      try data.write(to: url)
      debugLog("screenshot \(url.path) \(image.width)x\(image.height)")
    } catch {
      debugLog("screenshot failed (screen recording allowed: \(CGPreflightScreenCaptureAccess())): \(error)")
    }
  }
}
