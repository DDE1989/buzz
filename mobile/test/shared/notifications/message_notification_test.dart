import 'package:buzz/shared/notifications/message_notification.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('messageNotificationBody', () {
    test('collapses whitespace and strips markdown images', () {
      expect(
        messageNotificationBody(
          'hello\n\n  world ![img](https://x/y.png)',
          hasAttachments: true,
        ),
        'hello world',
      );
    });

    test('falls back for attachment-only messages', () {
      expect(
        messageNotificationBody(
          '![img](https://x/y.png)',
          hasAttachments: true,
        ),
        'Sent an attachment',
      );
      expect(messageNotificationBody('   ', hasAttachments: false), '');
    });

    test('truncates long bodies with an ellipsis', () {
      final body = messageNotificationBody('a' * 500, hasAttachments: false);
      expect(body.length, messageNotificationBodyLimit);
      expect(body.endsWith('…'), isTrue);
    });
  });

  group('buildMessageNotification', () {
    const pubkey =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('renders channels as group conversations', () {
      final notification = buildMessageNotification(
        eventId: 'e1',
        communityId: 'c1',
        channelId: 'ch1',
        senderPubkey: pubkey,
        senderName: 'Ana',
        content: 'hola',
        hasAttachments: false,
        isDm: false,
        channelLabel: 'general',
        memberCount: 4,
      );
      expect(notification, isNotNull);
      expect(notification!.title, 'Ana');
      expect(notification.conversationName, 'general');
      expect(notification.recipientCount, 3);
      expect(notification.toArguments()['channelId'], 'ch1');
    });

    test(
      'renders DMs without a conversation name and short pubkey fallback',
      () {
        final notification = buildMessageNotification(
          eventId: 'e1',
          communityId: 'c1',
          channelId: 'dm1',
          senderPubkey: pubkey,
          senderName: '  ',
          content: 'hola',
          hasAttachments: false,
          isDm: true,
          channelLabel: 'Ana',
          memberCount: 2,
        );
        expect(notification!.title, 'aaaaaaaa…');
        expect(notification.conversationName, isNull);
        expect(notification.recipientCount, 1);
      },
    );

    test('returns null when there is nothing to show', () {
      expect(
        buildMessageNotification(
          eventId: 'e1',
          communityId: 'c1',
          channelId: 'ch1',
          senderPubkey: pubkey,
          senderName: 'Ana',
          content: '',
          hasAttachments: false,
          isDm: false,
          channelLabel: 'general',
          memberCount: 4,
        ),
        isNull,
      );
    });
  });

  group('shouldPresentMessageNotification', () {
    test('skips the visible channel only while in the foreground', () {
      expect(
        shouldPresentMessageNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.resumed,
          visibleChannelId: 'ch1',
          channelId: 'ch1',
        ),
        isFalse,
      );
      expect(
        shouldPresentMessageNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.paused,
          visibleChannelId: 'ch1',
          channelId: 'ch1',
        ),
        isTrue,
      );
      expect(
        shouldPresentMessageNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.resumed,
          visibleChannelId: 'other',
          channelId: 'ch1',
        ),
        isTrue,
      );
    });

    test('respects the community toggle', () {
      expect(
        shouldPresentMessageNotification(
          notificationsEnabled: false,
          lifecycle: AppLifecycleState.paused,
          visibleChannelId: null,
          channelId: 'ch1',
        ),
        isFalse,
      );
    });
  });
}
