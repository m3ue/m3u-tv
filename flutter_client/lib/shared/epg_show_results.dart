import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Key for grouping EPG show search results. One row per (show, channelId)
/// pair: two airings of the same show on different channels belong to separate
/// rows; two airings of the same show on the same channel collapse into one
/// row whose airing list grows. Keyed on the `EpgShow` instance itself
/// (identity equality, not `normalizedTitle`) - the server can omit
/// `normalized_title`, and two distinct shows both falling back to `''` must
/// not merge into one row.
typedef ShowResultKey = ({EpgShow show, int channelId});

/// One row in the unified search-results list. On Now rows carry exactly
/// one episode (the one currently airing); Upcoming rows carry 1+ future
/// episodes on this show+channel, soonest first.
class ShowResultEntry {
  const ShowResultEntry({
    required this.show,
    required this.channelId,
    required this.episodes,
    required this.isOnNow,
  });

  final EpgShow show;
  final int channelId;
  final List<EpgShowEpisode> episodes;
  final bool isOnNow;
}

/// Combines the `airingNow` and `recentEpisodes` of each show into a single
/// deduped list of result rows, partitioned by On Now vs Upcoming and grouped
/// by (show, channelId) - keeps the same shape LiveTvScreen has rendered
/// since #212.
///
/// The `channels` lookup must be built from the **full** channel list, not a
/// search-filtered channel list - searching for a show name does not filter
/// channels by name, so the lookup must include every channel a programme
/// could be airing on.
({
  List<ShowResultEntry> all,
  List<ShowResultEntry> onNow,
  List<ShowResultEntry> upcoming,
  List<Channel> onNowChannels,
})
buildShowResultEntries(
  List<EpgShow> shows,
  Map<int, Channel> channelsById,
) {
  final now = DateTime.now().toUtc();

  // On Now: one entry per (show, channelId) currently airing. The channel
  // lookup is built from the **full** channel list, not the
  // search-filtered list - searching for a show name does not filter
  // channels by name, so the lookup must include every channel a
  // programme could be airing on.
  final onNowKeys = <ShowResultKey>{};
  final onNowEntries = <ShowResultEntry>[];
  final onNowChannelIds = <int>{};
  final onNowChannels = <Channel>[];
  for (final show in shows) {
    for (final episode in show.airingNow) {
      final channel = channelsById[episode.channelId];
      if (channel == null) continue;
      final key = (show: show, channelId: episode.channelId);
      if (!onNowKeys.add(key)) continue;
      onNowEntries.add(
        ShowResultEntry(
          show: show,
          channelId: episode.channelId,
          episodes: [episode],
          isOnNow: true,
        ),
      );
      if (onNowChannelIds.add(channel.id)) onNowChannels.add(channel);
    }
  }

  // Upcoming: future airings grouped by (show, channelId) - a single show
  // repeating on one network used to render a wall of identical rows (40
  // future airings of "Grace and Frankie" on one channel produced 12
  // identical rows); grouping collapses duplicates into one row that
  // shows up to 3 airing times plus a "+N more" affordance pointing at
  // the show detail screen, which already lists every airing. Skips any
  // (show, channelId) already covered by On Now.
  final groups = <ShowResultKey, List<EpgShowEpisode>>{};
  for (final show in shows) {
    for (final episode in show.recentEpisodes) {
      if (episode.displayTitle.isEmpty) continue;
      if (!episode.startTime.isAfter(now)) continue;
      final key = (show: show, channelId: episode.channelId);
      if (onNowKeys.contains(key)) continue;
      groups.putIfAbsent(key, () => <EpgShowEpisode>[]).add(episode);
    }
  }
  final upcomingEntries =
      groups.entries.map((entry) {
        final episodes = entry.value
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        return ShowResultEntry(
          show: entry.key.show,
          channelId: entry.key.channelId,
          episodes: episodes,
          isOnNow: false,
        );
      }).toList()..sort(
        (a, b) => a.episodes.first.startTime.compareTo(
          b.episodes.first.startTime,
        ),
      );

  return (
    all: [...onNowEntries, ...upcomingEntries],
    onNow: onNowEntries,
    upcoming: upcomingEntries,
    onNowChannels: onNowChannels,
  );
}

/// Single row style shared by On Now and Upcoming results so the merged
/// "All" tab reads as one consistent list rather than mixed layouts. On
/// Now rows tap straight to the channel (skip-previous/next then stays
/// within the On Now channel set); Upcoming rows open the show detail
/// screen, which has the recording actions.
class ShowResultRow extends StatelessWidget {
  const ShowResultRow({
    super.key,
    required this.entry,
    required this.channel,
    required this.onNowChannels,
    required this.onChannelSelect,
    this.onChannelContextChanged,
    this.onShowSelect,
    required this.languageTag,
    this.autofocus = false,
  });

  final ShowResultEntry entry;
  final Channel? channel;
  final List<Channel> onNowChannels;
  final void Function(Channel) onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(EpgShow)? onShowSelect;
  final String languageTag;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final firstEpisode = entry.episodes.first;
    final channelName = firstEpisode.channelName;
    final String? subtitle;
    final String trailingText;
    if (entry.isOnNow) {
      subtitle = _formatOnNowSubtitle(firstEpisode, channelName);
      trailingText = l10n.liveTvAiringUntil(
        DateFormat.jm(languageTag).format(firstEpisode.endTime.toLocal()),
      );
    } else {
      subtitle = channelName;
      final times = <String>[];
      for (final episode in entry.episodes.take(3)) {
        times.add(_formatUpcomingTime(episode.startTime, languageTag, l10n));
      }
      final remainder = entry.episodes.length - times.length;
      if (remainder > 0) {
        times.add(l10n.liveTvMoreAirings(remainder));
      }
      trailingText = times.join(' · ');
    }

    // Capture a non-nullable local so the tap closure can call
    // onChannelSelect without a flow-analysis-into-closure issue. On Now
    // rows whose channel wasn't in the channel list stay non-focusable
    // (DpadInkWell with `onTap: null` is disabled) - preserves the
    // pre-extraction behavior from live_tv_screen.dart exactly.
    final onNowChannel = channel;
    final onTap = entry.isOnNow
        ? (onNowChannel == null
              ? null
              : () {
                  onChannelContextChanged?.call(onNowChannels);
                  onChannelSelect(onNowChannel);
                })
        : () => onShowSelect?.call(entry.show);

    return DpadInkWell(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(8),
      color: colorScheme.surfaceContainerHigh,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
        child: Row(
          children: [
            ResilientMediaImage(
              imageUrl: channel?.logoUrl,
              fallbackIcon: Icons.tv,
              width: MediaBrowsingMetrics.logoSize,
              height: MediaBrowsingMetrics.logoSize,
              fit: BoxFit.contain,
              backgroundColor: Colors.transparent,
            ),
            const SizedBox(width: MediaBrowsingMetrics.itemGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.show.displayTitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.itemGap),
            Flexible(
              child: Text(
                trailingText,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// R6: episode name first (the higher-value token), channel second. Both
/// are optional and either may be absent.
///
/// Deliberately allowed to ellipsise. Round 4 moved the airing time out
/// of the subtitle line precisely so a long value here costs nothing
/// important - the time now lives in the trailing time text and is
/// immune, and channel identity is carried redundantly by the station
/// logo. Do NOT re-add the time here.
///
/// Returns null (not empty string) when both are absent - empty string
/// would render a phantom 11px row in the result row.
String? _formatOnNowSubtitle(EpgShowEpisode episode, String? channelName) {
  final ep = episode.subtitle;
  final hasEp = ep != null && ep.trim().isNotEmpty;
  final hasCh = channelName != null && channelName.trim().isNotEmpty;
  if (hasEp && hasCh) return '$ep · $channelName';
  if (hasEp) return ep;
  if (hasCh) return channelName;
  return null;
}

String _formatUpcomingTime(
  DateTime startTime,
  String languageTag,
  AppLocalizations l10n,
) {
  final local = startTime.toLocal();
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  final time = DateFormat.jm(languageTag).format(local);
  if (sameDay(local, now)) return time;
  if (sameDay(local, tomorrow)) return l10n.liveTvAiringTomorrow(time);
  return DateFormat.MMMd(languageTag).add_jm().format(local);
}
