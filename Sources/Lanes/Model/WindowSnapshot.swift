import AppKit

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
