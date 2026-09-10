import Sparkle
import SwiftUI

/// Sparkle wiring: one updater for the app, checking the feed in Info.plist once a day.
@MainActor
enum Updates {
  static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: feedOverride, userDriverDelegate: nil)
  private static let feedOverride = FeedOverride()

  /// `LANES_UPDATE_FEED` points the updater at another appcast, for trying updates locally.
  private final class FeedOverride: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
      ProcessInfo.processInfo.environment["LANES_UPDATE_FEED"]
    }
  }
}

/// The "Check for Updates…" menu item, enabled whenever Sparkle can run a check.
struct CheckForUpdatesButton: View {
  @State private var canCheck = false

  var body: some View {
    Button("Check for Updates…") { Updates.controller.updater.checkForUpdates() }
      .disabled(!canCheck)
      .onReceive(Updates.controller.updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
  }
}
