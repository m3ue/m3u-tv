import 'dart:math' as math;

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/channel_rows.dart';

/// [ChannelRows] over channels already in memory, every row resolved: lets
/// guide tests skip the catalog.
class ListChannelRows implements ChannelRows {
  ListChannelRows(this.channels);

  final List<Channel> channels;

  @override
  int get length => channels.length;

  @override
  Channel operator [](int index) => channels[index];

  @override
  void ensureLoaded(int index, int count) {}

  @override
  late final int maxCatchupDays = channels
      .map(
        (channel) => EpgService.effectiveCatchupRetentionDays(
          channel.catchupSupported,
          channel.catchupDays,
        ),
      )
      .fold(0, math.max);
}
