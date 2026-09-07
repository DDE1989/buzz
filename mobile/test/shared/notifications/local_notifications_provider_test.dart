import 'package:buzz/shared/community/community.dart';
import 'package:buzz/shared/community/community_provider.dart';
import 'package:buzz/shared/notifications/local_notifications_provider.dart';
import 'package:buzz/shared/notifications/message_notification.dart';
import 'package:buzz/shared/relay/app_lifecycle_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _pubkey =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Community _community({required bool notificationsEnabled}) => Community(
  id: 'community-1',
  name: 'Tecnocracia',
  relayUrl: 'wss://relay.example',
  pushNotificationsEnabled: notificationsEnabled,
  addedAt: DateTime.utc(2026),
);

ProviderContainer _container({
  required bool notificationsEnabled,
  required List<MessageNotification> presented,
  required List<String> cleared,
}) {
  final container = ProviderContainer(
    overrides: [
      appLifecycleProvider.overrideWith(_TestAppLifecycleNotifier.new),
      activeCommunityProvider.overrideWith(
        (ref) async => _community(notificationsEnabled: notificationsEnabled),
      ),
      messageNotificationPresenterProvider.overrideWithValue(
        (notification) async => presented.add(notification),
      ),
      deliveredNotificationClearerProvider.overrideWithValue(
        (channelId) async => cleared.add(channelId),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _notify(ProviderContainer container, {String channelId = 'ch1'}) =>
    container
        .read(localMessageNotifierProvider)
        .notify(
          eventId: 'e1',
          channelId: channelId,
          senderPubkey: _pubkey,
          senderName: 'Ana',
          content: 'hola',
          hasAttachments: false,
          isDm: false,
          channelLabel: 'general',
          memberCount: 3,
        );

void main() {
  test('presents live messages for channels that are not on screen', () async {
    final presented = <MessageNotification>[];
    final container = _container(
      notificationsEnabled: true,
      presented: presented,
      cleared: [],
    );
    await container.read(activeCommunityProvider.future);

    await _notify(container);

    expect(presented, hasLength(1));
    expect(presented.single.communityId, 'community-1');
    expect(presented.single.title, 'Ana');
    expect(presented.single.conversationName, 'general');
  });

  test(
    'skips the visible channel while resumed and clears its banners',
    () async {
      final presented = <MessageNotification>[];
      final cleared = <String>[];
      final container = _container(
        notificationsEnabled: true,
        presented: presented,
        cleared: cleared,
      );
      await container.read(activeCommunityProvider.future);

      container.read(visibleChannelProvider.notifier).enter('ch1');
      await _notify(container);
      expect(presented, isEmpty);
      expect(cleared, ['ch1']);

      await _notify(container, channelId: 'ch2');
      expect(presented, hasLength(1));

      final lifecycle =
          container.read(appLifecycleProvider.notifier)
              as _TestAppLifecycleNotifier;
      lifecycle.setState(AppLifecycleState.paused);
      await _notify(container);
      expect(presented, hasLength(2));

      container.read(visibleChannelProvider.notifier).leave('ch1');
      expect(container.read(visibleChannelProvider), isNull);
    },
  );

  test('stays silent when the community toggle is off', () async {
    final presented = <MessageNotification>[];
    final container = _container(
      notificationsEnabled: false,
      presented: presented,
      cleared: [],
    );
    await container.read(activeCommunityProvider.future);

    await _notify(container);

    expect(presented, isEmpty);
  });
}

class _TestAppLifecycleNotifier extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void setState(AppLifecycleState value) => state = value;
}
