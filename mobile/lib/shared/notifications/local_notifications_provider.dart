import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../community/community_provider.dart';
import '../relay/app_lifecycle_provider.dart';
import 'local_notification_bridge.dart';
import 'message_notification.dart';

final localNotificationAuthorizerProvider =
    Provider<LocalNotificationAuthorizer>(
      (ref) => requestLocalNotificationAuthorization,
    );

final messageNotificationPresenterProvider =
    Provider<MessageNotificationPresenter>((ref) => presentMessageNotification);

final deliveredNotificationClearerProvider =
    Provider<DeliveredNotificationClearer>(
      (ref) => clearDeliveredMessageNotifications,
    );

/// The channel whose timeline is currently on screen, if any.
///
/// Set by the channel page on mount and cleared on dispose. Live messages for
/// this channel are never turned into banners while the app is in the
/// foreground, and opening a channel clears the banners it already earned.
class VisibleChannelNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void enter(String channelId) {
    // Callers defer past build/dispose; the container may be gone by then.
    if (!ref.mounted) return;
    state = channelId;
    unawaited(ref.read(deliveredNotificationClearerProvider)(channelId));
  }

  void leave(String channelId) {
    if (!ref.mounted) return;
    if (state == channelId) state = null;
  }
}

final visibleChannelProvider =
    NotifierProvider<VisibleChannelNotifier, String?>(
      VisibleChannelNotifier.new,
    );

/// Turns live messages the unread pipeline already flagged into iOS banners.
///
/// This is the app-side counterpart of remote push: it only covers messages
/// that reach the running app over its socket, which is exactly the case
/// remote push cannot see. Both paths render through the same native
/// presenter and navigation target.
class LocalMessageNotifier {
  LocalMessageNotifier(this._ref);

  final Ref _ref;

  Future<void> notify({
    required String eventId,
    required String channelId,
    required String senderPubkey,
    required String? senderName,
    required String content,
    required bool hasAttachments,
    required bool isDm,
    required String channelLabel,
    required int memberCount,
  }) async {
    final community = _ref.read(activeCommunityProvider).value;
    if (community == null) return;
    final shouldPresent = shouldPresentMessageNotification(
      notificationsEnabled: community.pushNotificationsEnabled,
      lifecycle: _ref.read(appLifecycleProvider),
      visibleChannelId: _ref.read(visibleChannelProvider),
      channelId: channelId,
    );
    if (!shouldPresent) return;
    final notification = buildMessageNotification(
      eventId: eventId,
      communityId: community.id,
      channelId: channelId,
      senderPubkey: senderPubkey,
      senderName: senderName,
      content: content,
      hasAttachments: hasAttachments,
      isDm: isDm,
      channelLabel: channelLabel,
      memberCount: memberCount,
    );
    if (notification == null) return;
    try {
      await _ref.read(messageNotificationPresenterProvider)(notification);
    } catch (error) {
      debugPrint('[LocalMessageNotifier] present failed: $error');
    }
  }
}

final localMessageNotifierProvider = Provider<LocalMessageNotifier>(
  LocalMessageNotifier.new,
);
