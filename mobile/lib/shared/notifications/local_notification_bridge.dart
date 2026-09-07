import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'message_notification.dart';

const _channel = MethodChannel('buzz/local_notifications');

typedef LocalNotificationAuthorizer = Future<bool> Function();
typedef MessageNotificationPresenter =
    Future<void> Function(MessageNotification notification);
typedef DeliveredNotificationClearer = Future<void> Function(String channelId);

/// Asks iOS for display permission. Returns whether it was granted.
Future<bool> requestLocalNotificationAuthorization() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return await _channel.invokeMethod<bool>('requestAuthorization') ?? false;
  } on MissingPluginException {
    // Flutter tests and non-Runner embeddings do not install the native bridge.
    return false;
  }
}

/// Shows one message notification through the native presenter.
Future<void> presentMessageNotification(
  MessageNotification notification,
) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await _channel.invokeMethod<void>(
      'presentMessage',
      notification.toArguments(),
    );
  } on MissingPluginException {
    // See above.
  }
}

/// Removes delivered notifications for a channel the user is now reading.
Future<void> clearDeliveredMessageNotifications(String channelId) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await _channel.invokeMethod<void>('clearDelivered', {
      'channelId': channelId,
    });
  } on MissingPluginException {
    // See above.
  }
}
