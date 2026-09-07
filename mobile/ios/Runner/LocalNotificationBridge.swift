import BuzzPushKit
import Flutter
import Foundation
import UserNotifications

/// Presents message notifications the running app decided on itself over
/// `buzz/local_notifications`.
///
/// Remote push needs a relay that advertises the push descriptor plus the
/// gateway and App Attest; when that is absent (or the app is simply open with
/// a live socket) Dart already sees every message and can ask iOS to show it.
/// Rendering goes through the same Communication Notifications presenter and
/// navigation target as the push path, so a tap routes into the channel the
/// same way and the banner carries the cached sender avatar.
final class BuzzLocalNotificationBridge {
  private let appGroupIdentifier: String?
  private let presenter = BuzzCommunicationNotificationPresenter()

  init(appGroupIdentifier: String?) {
    self.appGroupIdentifier = appGroupIdentifier
  }

  @discardableResult
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    switch call.method {
    case "requestAuthorization":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "presentMessage":
      guard let arguments = call.arguments as? [String: Any],
        let request = MessageNotificationRequest(arguments)
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "presentMessage expects a complete message notification.",
            details: nil
          )
        )
        return true
      }
      present(request) { error in
        DispatchQueue.main.async {
          if let error {
            result(
              FlutterError(
                code: "present_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          } else {
            result(nil)
          }
        }
      }
    case "clearDelivered":
      guard let arguments = call.arguments as? [String: Any],
        let channelID = arguments["channelId"] as? String
      else {
        result(nil)
        return true
      }
      let center = UNUserNotificationCenter.current()
      center.getDeliveredNotifications { delivered in
        let identifiers = delivered
          .filter { $0.request.content.threadIdentifier == channelID }
          .map(\.request.identifier)
        if !identifiers.isEmpty {
          center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        DispatchQueue.main.async { result(nil) }
      }
    default:
      return false
    }
    return true
  }

  private func present(
    _ request: MessageNotificationRequest,
    completion: @escaping (Error?) -> Void
  ) {
    let content = UNMutableNotificationContent()
    content.title = request.title
    content.body = request.body
    if let conversationName = request.conversationName {
      content.subtitle = conversationName
    }
    content.threadIdentifier = request.channelID
    content.sound = .default
    let target = BuzzPushNavigationTarget(
      eventID: request.eventID,
      communityID: request.communityID,
      channelID: request.channelID
    )
    content.userInfo = [BuzzPushNavigationTarget.userInfoKey: target.userInfoValue]

    let resolution = BuzzPushResolution(
      title: request.title,
      body: request.body,
      subtitle: request.conversationName,
      threadIdentifier: request.channelID,
      navigationTarget: target,
      senderPubkey: request.senderPubkey,
      senderAvatarPNG: cachedAvatar(communityID: request.communityID, pubkey: request.senderPubkey),
      conversationIdentifier: BuzzPushPresentationIdentity.conversation(
        communityID: request.communityID,
        channelID: request.channelID
      ),
      conversationDisplayName: request.conversationName,
      conversationRecipientCount: request.recipientCount
    )
    presenter.present(ordinaryContent: content, resolution: resolution) { specialized in
      let notification = UNNotificationRequest(
        identifier: "buzz.local.\(request.eventID)",
        content: specialized,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(notification, withCompletionHandler: completion)
    }
  }

  /// The app-rendered avatar thumbnail the push path also uses, if cached.
  private func cachedAvatar(communityID: String, pubkey: String) -> Data? {
    guard let appGroupIdentifier,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      ),
      let data = try? Data(
        contentsOf: container.appendingPathComponent(BuzzPushPresentationCacheStore.fileName)
      ),
      data.count <= BuzzPushPresentationCacheStore.maximumSnapshotBytes
    else { return nil }
    let normalized = pubkey.lowercased()
    return BuzzPushPresentationCacheSnapshot.decode(data).profiles
      .first { $0.communityID == communityID && $0.pubkey == normalized }?
      .avatarPNG
  }
}

struct MessageNotificationRequest {
  let eventID: String
  let communityID: String
  let channelID: String
  let senderPubkey: String
  let title: String
  let body: String
  /// Channel name for group conversations; nil renders as a direct message.
  let conversationName: String?
  let recipientCount: Int

  init?(_ arguments: [String: Any]) {
    guard let eventID = arguments["eventId"] as? String, !eventID.isEmpty,
      let communityID = arguments["communityId"] as? String, !communityID.isEmpty,
      let channelID = arguments["channelId"] as? String, !channelID.isEmpty,
      let senderPubkey = arguments["senderPubkey"] as? String, !senderPubkey.isEmpty,
      let title = arguments["title"] as? String, !title.isEmpty,
      let body = arguments["body"] as? String, !body.isEmpty
    else { return nil }
    self.eventID = eventID
    self.communityID = communityID
    self.channelID = channelID
    self.senderPubkey = senderPubkey
    self.title = title
    self.body = body
    let name = arguments["conversationName"] as? String
    conversationName = name?.isEmpty == false ? name : nil
    recipientCount = max(arguments["recipientCount"] as? Int ?? 1, 1)
  }
}
