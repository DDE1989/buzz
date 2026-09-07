import Foundation

/// App Group hand-off between the Share Extension and the main app.
///
/// The extension copies every shared item into
/// `<app group>/Library/Caches/share-inbox/<id>/` and writes a `manifest.json`
/// next to the copies. The app takes the newest manifest, hands the files to
/// the composer, and discards the manifest once it has been consumed. This file
/// is compiled into both targets; keep it dependency-free.
enum BuzzShareInbox {
  static let directoryName = "share-inbox"
  static let manifestName = "manifest.json"
  static let maximumItems = 10
  /// Payloads older than this are pruned on the next read.
  static let staleInterval: TimeInterval = 24 * 60 * 60

  struct Item: Codable, Equatable {
    enum Kind: String, Codable {
      case text
      case url
      case file
    }

    let kind: Kind
    /// Text body or URL string. Nil for files.
    let value: String?
    /// Absolute path of the copied file inside the payload directory.
    let path: String?
    let name: String?
    let mimeType: String?

    var flutterArguments: [String: Any] {
      var map: [String: Any] = ["kind": kind.rawValue]
      if let value { map["value"] = value }
      if let path { map["path"] = path }
      if let name { map["name"] = name }
      if let mimeType { map["mimeType"] = mimeType }
      return map
    }
  }

  struct Payload: Codable, Equatable {
    let id: String
    let createdAt: TimeInterval
    let items: [Item]

    var flutterArguments: [String: Any] {
      [
        "id": id,
        "createdAt": createdAt,
        "items": items.map(\.flutterArguments),
      ]
    }
  }

  static func inboxURL(appGroupIdentifier: String?) -> URL? {
    guard let appGroupIdentifier, !appGroupIdentifier.isEmpty,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )
    else { return nil }
    return
      container
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Caches", isDirectory: true)
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  /// Creates a fresh, empty payload directory and returns it with its id.
  static func makePayloadDirectory(appGroupIdentifier: String?) throws -> (id: String, url: URL) {
    guard let inbox = inboxURL(appGroupIdentifier: appGroupIdentifier) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let id = UUID().uuidString.lowercased()
    let directory = inbox.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return (id, directory)
  }

  static func writeManifest(_ payload: Payload, in directory: URL) throws {
    let data = try JSONEncoder().encode(payload)
    try data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
  }

  /// Returns the newest pending payload, pruning stale directories first.
  static func takePending(appGroupIdentifier: String?) -> Payload? {
    guard let inbox = inboxURL(appGroupIdentifier: appGroupIdentifier) else { return nil }
    let fileManager = FileManager.default
    guard
      let directories = try? fileManager.contentsOfDirectory(
        at: inbox,
        includingPropertiesForKeys: nil
      )
    else { return nil }
    let now = Date().timeIntervalSince1970
    var newest: Payload?
    for directory in directories {
      let manifest = directory.appendingPathComponent(manifestName)
      guard let data = try? Data(contentsOf: manifest),
        let payload = try? JSONDecoder().decode(Payload.self, from: data)
      else {
        // A directory without a readable manifest was either consumed or
        // abandoned mid-write; drop it once it is old enough.
        prune(directory, olderThan: now - staleInterval)
        continue
      }
      if now - payload.createdAt > staleInterval {
        try? fileManager.removeItem(at: directory)
        continue
      }
      if newest == nil || payload.createdAt > newest!.createdAt {
        newest = payload
      }
    }
    return newest
  }

  /// Removes the manifest so the payload is not surfaced again. Copied files
  /// stay in place until the composer deletes them after upload.
  static func discard(id: String, appGroupIdentifier: String?) {
    guard let inbox = inboxURL(appGroupIdentifier: appGroupIdentifier),
      isSafeIdentifier(id)
    else { return }
    let directory = inbox.appendingPathComponent(id, isDirectory: true)
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(manifestName))
  }

  private static func prune(_ directory: URL, olderThan cutoff: TimeInterval) {
    let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
    let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    if modified < cutoff {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private static func isSafeIdentifier(_ id: String) -> Bool {
    !id.isEmpty && id.allSatisfy { $0.isHexDigit || $0 == "-" }
  }
}
