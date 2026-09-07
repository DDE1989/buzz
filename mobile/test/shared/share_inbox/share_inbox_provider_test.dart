import 'dart:async';

import 'package:buzz/shared/relay/app_lifecycle_provider.dart';
import 'package:buzz/shared/share_inbox/share_inbox_provider.dart';
import 'package:buzz/shared/share_inbox/shared_payload.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _payload = SharedPayload(
  id: 'p1',
  items: [SharedItem(kind: SharedItemKind.text, value: 'hi')],
);

void main() {
  test(
    'surfaces a staged payload on build and releases it on consume',
    () async {
      final queue = <SharedPayload?>[_payload, null];
      final discarded = <String>[];
      final container = ProviderContainer(
        overrides: [
          appLifecycleProvider.overrideWith(_TestAppLifecycleNotifier.new),
          sharedPayloadReaderProvider.overrideWithValue(
            () async => queue.isEmpty ? null : queue.removeAt(0),
          ),
          sharedPayloadDiscarderProvider.overrideWithValue((id) async {
            discarded.add(id);
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(pendingSharedPayloadProvider), isNull);
      await _pump();
      expect(container.read(pendingSharedPayloadProvider), _payload);

      await container.read(pendingSharedPayloadProvider.notifier).consume();
      expect(container.read(pendingSharedPayloadProvider), isNull);
      expect(discarded, ['p1']);
    },
  );

  test('re-checks the inbox when the app returns to the foreground', () async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        appLifecycleProvider.overrideWith(_TestAppLifecycleNotifier.new),
        sharedPayloadReaderProvider.overrideWithValue(() async {
          reads += 1;
          return reads == 2 ? _payload : null;
        }),
        sharedPayloadDiscarderProvider.overrideWithValue((_) async {}),
      ],
    );
    addTearDown(container.dispose);

    container.read(pendingSharedPayloadProvider);
    await _pump();
    expect(reads, 1);
    expect(container.read(pendingSharedPayloadProvider), isNull);

    final lifecycle =
        container.read(appLifecycleProvider.notifier)
            as _TestAppLifecycleNotifier;
    lifecycle.setState(AppLifecycleState.paused);
    lifecycle.setState(AppLifecycleState.resumed);
    await _pump();
    expect(reads, 2);
    expect(container.read(pendingSharedPayloadProvider), _payload);
  });

  test('coalesces overlapping sync calls', () async {
    final gate = Completer<SharedPayload?>();
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        appLifecycleProvider.overrideWith(_TestAppLifecycleNotifier.new),
        sharedPayloadReaderProvider.overrideWithValue(() {
          reads += 1;
          return gate.future;
        }),
        sharedPayloadDiscarderProvider.overrideWithValue((_) async {}),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(pendingSharedPayloadProvider.notifier);
    final first = notifier.sync();
    final second = notifier.sync();
    expect(reads, 1);
    gate.complete(_payload);
    await Future.wait([first, second]);
    expect(container.read(pendingSharedPayloadProvider), _payload);
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _TestAppLifecycleNotifier extends AppLifecycleNotifier {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  void setState(AppLifecycleState value) => state = value;
}
