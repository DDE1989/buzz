import Flutter
import Foundation

/// Exposes the Share Extension inbox to Dart over `buzz/share_inbox`.
///
/// `takePendingShare` returns the newest staged payload (or nil) and
/// `discardShare` removes its manifest once the composer has taken ownership
/// of the copied files.
final class BuzzShareInboxBridge {
  private let appGroupIdentifier: String?
  private let queue = DispatchQueue(label: "xyz.block.buzz.share-inbox", qos: .userInitiated)

  init(appGroupIdentifier: String?) {
    self.appGroupIdentifier = appGroupIdentifier
  }

  @discardableResult
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    switch call.method {
    case "takePendingShare":
      queue.async { [appGroupIdentifier] in
        let payload = BuzzShareInbox.takePending(appGroupIdentifier: appGroupIdentifier)
        DispatchQueue.main.async { result(payload?.flutterArguments) }
      }
    case "discardShare":
      guard let arguments = call.arguments as? [String: Any],
        let id = arguments["id"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "discardShare expects a payload id.",
            details: nil
          )
        )
        return true
      }
      queue.async { [appGroupIdentifier] in
        BuzzShareInbox.discard(id: id, appGroupIdentifier: appGroupIdentifier)
        DispatchQueue.main.async { result(nil) }
      }
    default:
      return false
    }
    return true
  }
}
