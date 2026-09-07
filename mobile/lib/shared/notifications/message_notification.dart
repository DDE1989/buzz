import 'package:flutter/widgets.dart';

import '../utils/string_utils.dart';

/// Longest body iOS shows in a banner before truncating anyway.
const messageNotificationBodyLimit = 240;

/// A message notification the app decided to show itself.
///
/// Mirrors `MessageNotificationRequest` in
/// `ios/Runner/LocalNotificationBridge.swift`.
@immutable
class MessageNotification {
  final String eventId;
  final String communityId;
  final String channelId;
  final String senderPubkey;

  /// Sender display name.
  final String title;
  final String body;

  /// Channel name for group conversations; null renders as a direct message.
  final String? conversationName;
  final int recipientCount;

  const MessageNotification({
    required this.eventId,
    required this.communityId,
    required this.channelId,
    required this.senderPubkey,
    required this.title,
    required this.body,
    required this.conversationName,
    required this.recipientCount,
  });

  Map<String, Object?> toArguments() => {
    'eventId': eventId,
    'communityId': communityId,
    'channelId': channelId,
    'senderPubkey': senderPubkey,
    'title': title,
    'body': body,
    'conversationName': conversationName,
    'recipientCount': recipientCount,
  };

  @override
  bool operator ==(Object other) =>
      other is MessageNotification &&
      other.eventId == eventId &&
      other.communityId == communityId &&
      other.channelId == channelId &&
      other.senderPubkey == senderPubkey &&
      other.title == title &&
      other.body == body &&
      other.conversationName == conversationName &&
      other.recipientCount == recipientCount;

  @override
  int get hashCode => Object.hash(
    eventId,
    communityId,
    channelId,
    senderPubkey,
    title,
    body,
    conversationName,
    recipientCount,
  );
}

/// Builds the notification for a live message, or null when there is nothing
/// worth showing (a message with neither text nor attachments).
MessageNotification? buildMessageNotification({
  required String eventId,
  required String communityId,
  required String channelId,
  required String senderPubkey,
  required String? senderName,
  required String content,
  required bool hasAttachments,
  required bool isDm,
  required String channelLabel,
  required int memberCount,
}) {
  final body = messageNotificationBody(content, hasAttachments: hasAttachments);
  if (body.isEmpty) return null;
  final trimmedName = senderName?.trim();
  return MessageNotification(
    eventId: eventId,
    communityId: communityId,
    channelId: channelId,
    senderPubkey: senderPubkey,
    title: trimmedName == null || trimmedName.isEmpty
        ? shortPubkey(senderPubkey)
        : trimmedName,
    body: body,
    conversationName: isDm ? null : channelLabel,
    recipientCount: memberCount > 1 ? memberCount - 1 : 1,
  );
}

final _markdownImage = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _whitespaceRuns = RegExp(r'\s+');

/// Plain, single-line preview of a message body.
String messageNotificationBody(String content, {required bool hasAttachments}) {
  final text = content
      .replaceAll(_markdownImage, ' ')
      .replaceAll(_whitespaceRuns, ' ')
      .trim();
  if (text.isEmpty) return hasAttachments ? 'Sent an attachment' : '';
  if (text.characters.length <= messageNotificationBodyLimit) return text;
  return '${text.characters.take(messageNotificationBodyLimit - 1)}…';
}

/// Whether a message the unread pipeline flagged should also become a banner.
///
/// Notifications are for messages the user is not already looking at: a
/// message in the channel that is open while the app is in the foreground
/// is skipped. Everything else that the community's toggle allows is shown.
bool shouldPresentMessageNotification({
  required bool notificationsEnabled,
  required AppLifecycleState lifecycle,
  required String? visibleChannelId,
  required String channelId,
}) {
  if (!notificationsEnabled) return false;
  if (lifecycle == AppLifecycleState.resumed && visibleChannelId == channelId) {
    return false;
  }
  return true;
}
