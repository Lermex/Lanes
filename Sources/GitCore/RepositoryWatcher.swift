import CoreServices
import Foundation

public final class RepositoryWatcher: @unchecked Sendable {
  private var stream: FSEventStreamRef?
  private let queue = DispatchQueue(label: "lanes.repository-watcher")
  private let onChange: @Sendable ([String]) -> Void

  public init(paths: [URL], latency: TimeInterval = 0.3, onChange: @escaping @Sendable ([String]) -> Void) {
    self.onChange = onChange
    var context = FSEventStreamContext()
    context.info = Unmanaged.passUnretained(self).toOpaque()
    let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
      guard let info else { return }
      let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
      let paths = unsafeBitCast(eventPaths, to: NSArray.self).compactMap { $0 as? String }
      watcher.onChange(Array(paths.prefix(count)))
    }
    stream = FSEventStreamCreate(
      nil,
      callback,
      &context,
      paths.map(\.path) as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      latency,
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
    )
    if let stream {
      FSEventStreamSetDispatchQueue(stream, queue)
      FSEventStreamStart(stream)
    }
  }

  deinit {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
  }
}
