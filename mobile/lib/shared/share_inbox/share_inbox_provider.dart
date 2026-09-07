import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../relay/app_lifecycle_provider.dart';
import 'share_inbox_bridge.dart';
import 'shared_payload.dart';

final sharedPayloadReaderProvider = Provider<SharedPayloadReader>(
  (ref) => takePendingSharedPayload,
);

final sharedPayloadDiscarderProvider = Provider<SharedPayloadDiscarder>(
  (ref) => discardSharedPayload,
);

/// The share-sheet payload waiting for the user to pick a destination.
///
/// The Share Extension stages items in the App Group inbox and asks iOS to
/// open `buzz://share?id=…`. That open is best-effort, so besides reacting to
/// the link the notifier re-checks the inbox every time the app returns to the
/// foreground: a share that could not launch the app is picked up as soon as
/// the user opens Buzz themselves.
class PendingSharedPayloadNotifier extends Notifier<SharedPayload?> {
  Future<void>? _inFlight;

  @override
  SharedPayload? build() {
    ref.listen(appLifecycleProvider, (previous, next) {
      if (previous != AppLifecycleState.resumed &&
          next == AppLifecycleState.resumed) {
        unawaited(sync());
      }
    });
    unawaited(sync());
    return null;
  }

  /// Pull the newest staged payload from native, if one exists.
  Future<void> sync() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final run = _sync().whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<void> _sync() async {
    final payload = await ref.read(sharedPayloadReaderProvider)();
    if (!ref.mounted || payload == null) return;
    state = payload;
  }

  /// Release the current payload once a destination has taken its contents.
  Future<void> consume() async {
    final payload = state;
    if (payload == null) return;
    state = null;
    await ref.read(sharedPayloadDiscarderProvider)(payload.id);
  }

  /// Drop the current payload without using it (user dismissed the picker).
  Future<void> dismiss() => consume();
}

final pendingSharedPayloadProvider =
    NotifierProvider<PendingSharedPayloadNotifier, SharedPayload?>(
      PendingSharedPayloadNotifier.new,
    );
