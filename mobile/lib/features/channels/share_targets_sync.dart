import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/community/community.dart';
import '../../shared/community/community_provider.dart';
import '../../shared/relay/relay.dart';
import '../../shared/share_inbox/share_inbox_provider.dart';
import '../../shared/share_inbox/share_targets.dart';
import 'channel.dart';
import 'channels_provider.dart';
import 'dm_channel_labels.dart';

/// Publishes the active community's channels to the iOS Share Extension so
/// its picker matches the in-app one. Republishes only when the list
/// actually changed; the state is the fingerprint last published.
class ShareTargetsSyncNotifier extends Notifier<String?> {
  @override
  String? build() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    final community = ref.watch(activeCommunityProvider).value;
    final communities = ref.watch(communityListProvider).value;
    final channels = ref.watch(channelsProvider).value;
    final myPubkey = ref.watch(myPubkeyProvider);
    if (community == null || communities == null || channels == null) {
      return stateOrNull;
    }
    final snapshot = buildShareTargetsSnapshot(
      community: community,
      communities: communities,
      channels: channels,
      currentPubkey: myPubkey,
    );
    final fingerprint = snapshot.fingerprint;
    if (fingerprint != stateOrNull) {
      unawaited(_publish(snapshot));
    }
    return fingerprint;
  }

  Future<void> _publish(ShareTargetsSnapshot snapshot) async {
    try {
      await ref.read(shareTargetsSyncerProvider)(snapshot);
    } catch (error) {
      debugPrint('[ShareTargetsSync] publish failed: $error');
    }
  }
}

final shareTargetsSyncProvider =
    NotifierProvider<ShareTargetsSyncNotifier, String?>(
      ShareTargetsSyncNotifier.new,
    );

/// Member, non-archived channels of [community], newest activity first.
ShareTargetsSnapshot buildShareTargetsSnapshot({
  required Community community,
  required List<Community> communities,
  required List<Channel> channels,
  required String? currentPubkey,
}) {
  final targets = [
    for (final channel in channels)
      if (channel.isMember && !channel.isArchived)
        ShareTarget(
          channelId: channel.id,
          label: resolveDmChannelDisplayLabel(
            channel,
            currentPubkey: currentPubkey,
          ),
          isDm: channel.isDm,
          lastMessageAt: channel.lastMessageAt,
        ),
  ];
  targets.sort((a, b) {
    final aTime = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });
  return ShareTargetsSnapshot(
    communityId: community.id,
    communities: [
      for (final entry in communities)
        ShareTargetCommunity(id: entry.id, name: entry.name),
    ],
    targets: targets,
  );
}
