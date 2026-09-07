import UIKit
import UniformTypeIdentifiers
import os.log

private let shareLog = Logger(subsystem: "xyz.block.buzz.share", category: "handoff")

/// Receives items from the iOS share sheet, stages them in the App Group
/// inbox, and hands off to the main app through `buzz://share?id=<id>`.
///
/// The extension deliberately has no channel picker of its own: it never holds
/// the signing key or a relay session, so the app does the actual posting.
final class ShareViewController: UIViewController {
  private let statusLabel = UILabel()
  private var didFinish = false

  private var appGroupIdentifier: String? {
    Bundle.main.object(forInfoDictionaryKey: "BuzzAppGroupIdentifier") as? String
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    statusLabel.text = "Sending to Buzz…"
    statusLabel.font = .preferredFont(forTextStyle: .body)
    statusLabel.textColor = .secondaryLabel
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { await stageAndHandOff() }
  }

  private func stageAndHandOff() async {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
      .flatMap { $0.attachments ?? [] } ?? []
    guard !providers.isEmpty else {
      cancel(message: "Nothing to share")
      return
    }
    do {
      let (id, directory) = try BuzzShareInbox.makePayloadDirectory(
        appGroupIdentifier: appGroupIdentifier
      )
      var items: [BuzzShareInbox.Item] = []
      for provider in providers.prefix(BuzzShareInbox.maximumItems) {
        if let item = await ShareItemLoader.load(provider, into: directory) {
          items.append(item)
        }
      }
      guard !items.isEmpty else {
        try? FileManager.default.removeItem(at: directory)
        cancel(message: "Unsupported content")
        return
      }
      let payload = BuzzShareInbox.Payload(
        id: id,
        createdAt: Date().timeIntervalSince1970,
        items: items
      )
      try BuzzShareInbox.writeManifest(payload, in: directory)
      openContainerApp(payloadID: id)
    } catch {
      cancel(message: "Could not share to Buzz")
    }
  }

  private func openContainerApp(payloadID: String) {
    var components = URLComponents()
    components.scheme = "buzz"
    components.host = "share"
    components.queryItems = [URLQueryItem(name: "id", value: payloadID)]
    guard let url = components.url else {
      finish()
      return
    }
    // `NSExtensionContext.open` is only guaranteed for Today widgets; share
    // extensions usually get `false` back, so fall back to the responder
    // chain. Either way the payload stays in the inbox, and the app also
    // checks it on every foreground resume, so a failed hand-off is recovered
    // the next time the user opens Buzz.
    extensionContext?.open(url) { [weak self] opened in
      shareLog.info("extensionContext.open returned \(opened, privacy: .public)")
      DispatchQueue.main.async {
        if !opened {
          self?.openViaResponderChain(url)
        }
        self?.finish()
      }
    }
  }

  /// Extensions cannot call `UIApplication.open` directly, but the
  /// application object still sits at the end of the responder chain. The
  /// legacy `openURL:` selector is a no-op from an extension on current iOS,
  /// so invoke `open:options:completionHandler:` through its implementation.
  private func openViaResponderChain(_ url: URL) {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    // Only the application object may open the URL. The hosted UIScene that
    // precedes it in an extension's chain also answers this selector but
    // forwards to an unimplemented target and aborts.
    guard let applicationClass = NSClassFromString("UIApplication") else { return }
    var responder: UIResponder? = self
    while let current = responder {
      if current.isKind(of: applicationClass), current.responds(to: selector),
        let implementation = class_getMethodImplementation(type(of: current), selector)
      {
        typealias OpenFunction = @convention(c) (
          AnyObject, Selector, URL, NSDictionary, (@convention(block) (Bool) -> Void)?
        ) -> Void
        let open = unsafeBitCast(implementation, to: OpenFunction.self)
        open(current, selector, url, [:]) { success in
          shareLog.info("open:options:completionHandler: success=\(success, privacy: .public)")
        }
        return
      }
      responder = current.next
    }
    shareLog.error("no responder able to open the container app")
  }

  private func cancel(message: String) {
    statusLabel.text = message
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self, !self.didFinish else { return }
      self.didFinish = true
      self.extensionContext?.cancelRequest(
        withError: NSError(domain: "xyz.block.buzz.share", code: 1)
      )
    }
  }

  private func finish() {
    guard !didFinish else { return }
    didFinish = true
    // Give the URL open a moment to reach the system before tearing down.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
  }
}

/// Resolves one `NSItemProvider` into a staged inbox item.
enum ShareItemLoader {
  static func load(
    _ provider: NSItemProvider,
    into directory: URL
  ) async -> BuzzShareInbox.Item? {
    // Order matters: a photo from Photos also conforms to public.url on some
    // hosts, and a page shared from Safari carries plain text alongside the URL.
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      return await loadFile(provider, type: .image, into: directory)
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      return await loadFile(provider, type: .movie, into: directory)
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      return await loadFileURL(provider, into: directory)
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      if let url = await loadObject(provider, type: .url) as? URL {
        if url.isFileURL {
          return copyFile(at: url, into: directory)
        }
        return BuzzShareInbox.Item(
          kind: .url, value: url.absoluteString, path: nil, name: nil, mimeType: nil
        )
      }
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      if let text = await loadObject(provider, type: .plainText) as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return BuzzShareInbox.Item(
          kind: .text, value: text, path: nil, name: nil, mimeType: nil
        )
      }
    }
    if let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: {
      $0.conforms(to: .data)
    }) {
      return await loadFile(provider, type: type, into: directory)
    }
    return nil
  }

  private static func loadObject(_ provider: NSItemProvider, type: UTType) async -> Any? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
        continuation.resume(returning: item)
      }
    }
  }

  private static func loadFileURL(
    _ provider: NSItemProvider,
    into directory: URL
  ) async -> BuzzShareInbox.Item? {
    let item = await loadObject(provider, type: .fileURL)
    let url: URL?
    if let direct = item as? URL {
      url = direct
    } else if let data = item as? Data {
      url = URL(dataRepresentation: data, relativeTo: nil)
    } else {
      url = nil
    }
    guard let url else { return nil }
    return copyFile(at: url, into: directory)
  }

  private static func loadFile(
    _ provider: NSItemProvider,
    type: UTType,
    into directory: URL
  ) async -> BuzzShareInbox.Item? {
    await withCheckedContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        // The URL is only valid inside this closure; copy synchronously.
        guard let url else {
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: copyFile(at: url, into: directory, fallbackType: type))
      }
    }
  }

  private static func copyFile(
    at source: URL,
    into directory: URL,
    fallbackType: UTType? = nil
  ) -> BuzzShareInbox.Item? {
    let type = UTType(filenameExtension: source.pathExtension) ?? fallbackType
    var name = sanitizedFileName(source.lastPathComponent)
    if name.isEmpty { name = "shared" }
    if (name as NSString).pathExtension.isEmpty, let ext = type?.preferredFilenameExtension {
      name += ".\(ext)"
    }
    var destination = directory.appendingPathComponent(name)
    var suffix = 1
    while FileManager.default.fileExists(atPath: destination.path) {
      let base = (name as NSString).deletingPathExtension
      let ext = (name as NSString).pathExtension
      let candidate = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
      destination = directory.appendingPathComponent(candidate)
      suffix += 1
    }
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      return nil
    }
    return BuzzShareInbox.Item(
      kind: .file,
      value: nil,
      path: destination.path,
      name: destination.lastPathComponent,
      mimeType: type?.preferredMIMEType
    )
  }

  private static func sanitizedFileName(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
  }
}
