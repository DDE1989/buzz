import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../community/community_provider.dart';
import '../relay/app_lifecycle_provider.dart';
import 'share_inbox_bridge.dart';
import 'shared_payload.dart';

final sharedPayloadReaderProvider = Provider<SharedPayloadReader>(
  (ref) => takePendingSharedPayload,
);

final sharedPayloadDiscarderProvider = Provider<SharedPayloadDiscarder>(
  (ref) => discardSharedPayload,
);

final shareTargetsSyncerProvider = Provider<ShareTargetsSyncer>(
  (ref) => syncShareTargets,
);

enum SharedPayloadCommunityPreparation { ready, switched, unavailable, failed }

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

  /// Makes the community a targeted payload names the active one.
  Future<SharedPayloadCommunityPreparation> prepareCommunity(
    String communityId,
  ) async {
    try {
      final communities = await ref.read(communityListProvider.future);
      if (!communities.any((community) => community.id == communityId)) {
        return SharedPayloadCommunityPreparation.unavailable;
      }
      final active = await ref.read(activeCommunityProvider.future);
      if (active?.id == communityId) {
        return SharedPayloadCommunityPreparation.ready;
      }
      await ref
          .read(communityListProvider.notifier)
          .switchCommunity(communityId);
      return SharedPayloadCommunityPreparation.switched;
    } catch (error) {
      debugPrint(
        'share-inbox: failed to switch to community $communityId: $error',
      );
      return SharedPayloadCommunityPreparation.failed;
    }
  }
}

final pendingSharedPayloadProvider =
    NotifierProvider<PendingSharedPayloadNotifier, SharedPayload?>(
      PendingSharedPayloadNotifier.new,
    );
