import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/cached_backdrop_image.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

/// Below this window width the series detail lays out for a phone: smaller
/// poster, full-width description, narrower episode cards.
const double _kSeriesCompactBreakpoint = 700;
const double _kEpisodeCardWidthWide = 340;
const double _kEpisodeCardWidthCompact = 250;

/// Text area under an episode thumbnail (3-line plot + date + padding).
const double _kEpisodeCardTextHeight = 96;

/// Marks one series episode watched / unwatched for the active viewer.
/// Structurally matches `ContentActions.onMarkEpisodeWatched`.
typedef MarkEpisodeWatched =
    Future<void> Function({
      required int streamId,
      required int seriesId,
      required int seasonNumber,
      required int episodeNumber,
      int? durationSeconds,
      String? seriesName,
      String? episodeTitle,
      required bool watched,
    });

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({
    super.key,
    required this.seriesId,
    required this.seriesName,
    required this.xtreamService,
    this.coverUrl,
    this.viewerId,
    this.onPlay,
    this.progressList = const [],
    this.onMarkEpisodeWatched,
    this.onSidebarActivate,
  });

  final int seriesId;
  final String seriesName;

  /// Cover image URL passed immediately on navigation so something shows
  /// behind the spinner before the series info API call resolves.
  final String? coverUrl;
  final XtreamService xtreamService;

  /// Active viewer ulid. When set, the screen pulls the authoritative
  /// per-series watch progress (`get_series_progress`) instead of relying on
  /// the capped recently-watched list, and the mark-watched affordances are
  /// enabled.
  final String? viewerId;
  final void Function(PlayerArgs)? onPlay;
  final List<Progress> progressList;
  final MarkEpisodeWatched? onMarkEpisodeWatched;
  final VoidCallback? onSidebarActivate;

  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  late final Future<SeriesInfo> _future = widget.xtreamService
      .getSeriesInfo(widget.seriesId)
      .then((info) {
        _seriesInfo = info;
        unawaited(
          _resolveDominantColor(
            info.series.backdropUrl ?? info.series.coverUrl,
          ),
        );
        unawaited(_loadSeriesProgress());
        return info;
      });
  int? _selectedSeason;
  SeriesInfo? _seriesInfo;
  Color? _dominantColor;

  /// Authoritative per-series episode progress from `get_series_progress`.
  /// Null until the first fetch resolves (or forever, when there is no
  /// viewer), in which case the passed-in [SeriesDetailsScreen.progressList]
  /// is the only source.
  List<Progress>? _seriesProgress;

  Future<void> _loadSeriesProgress() async {
    final viewerId = widget.viewerId;
    if (viewerId == null) return;
    try {
      final rows = await widget.xtreamService.getSeriesProgress(
        viewerId,
        widget.seriesId,
      );
      if (!mounted) return;
      setState(() => _seriesProgress = rows);
    } on Object catch (_) {
      // Keep whatever we already have; recently-watched still covers the
      // common case of an actively-watched show.
    }
  }

  /// [_seriesProgress] when available, with any fresher in-memory rows from
  /// [SeriesDetailsScreen.progressList] (optimistic mark-watched updates,
  /// just-finished playback) layered on top by stream id.
  List<Progress> get _effectiveProgress {
    final fetched = _seriesProgress;
    if (fetched == null) return widget.progressList;
    final byId = <int, Progress>{for (final p in fetched) p.streamId: p};
    for (final p in widget.progressList) {
      if (byId.containsKey(p.streamId)) byId[p.streamId] = p;
    }
    return byId.values.toList(growable: false);
  }

  /// Extracts a single dominant tone from the backdrop so the immersive page
  /// can bleed it past the image edge (Nuvio-style). Any failure just leaves
  /// the theme surface as the background.
  Future<void> _resolveDominantColor(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final palette = await PaletteGeneratorMaster.fromImageProvider(
        CachedNetworkImageProvider(url, cacheManager: MediaImageCacheManager()),
        size: const Size(220, 124),
        maximumColorCount: 8,
      );
      if (!mounted) return;
      final swatch =
          palette.darkMutedColor ??
          palette.darkVibrantColor ??
          palette.dominantColor;
      if (swatch != null) setState(() => _dominantColor = swatch.color);
    } on Object catch (_) {
      // Fall back to the theme surface.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ItemDetailScaffold(
      title: widget.seriesName,
      onSidebarActivate: widget.onSidebarActivate,
      body: FutureBuilder<SeriesInfo>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoading(context);
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load episodes: ${snapshot.error}'),
            );
          }
          final info = snapshot.data;
          if (info == null) {
            return const Center(child: Text('No episodes available'));
          }
          return _SeriesDetailsBody(
            info: info,
            selectedSeason: _selectedSeason,
            progressList: _effectiveProgress,
            dominantColor: _dominantColor,
            canMarkWatched: widget.onMarkEpisodeWatched != null,
            onSeasonSelected: (season) =>
                setState(() => _selectedSeason = season),
            onEpisodeSelected: _playEpisode,
            onMarkEpisode: _markEpisode,
            onMarkSeason: _markSeason,
          );
        },
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.coverUrl != null)
          Opacity(opacity: 0.2, child: CachedBackdropImage(widget.coverUrl!)),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  void _playEpisode(Episode episode, {double? startPosition}) {
    final args = episodePlayerArgs(
      episode: episode,
      seriesId: widget.seriesId,
      seriesName: widget.seriesName,
      series: _seriesInfo?.series,
      startPosition: startPosition,
    );
    if (args != null) widget.onPlay?.call(args);
  }

  Future<void> _markEpisode(Episode episode, {required bool watched}) async {
    final mark = widget.onMarkEpisodeWatched;
    final streamId = int.tryParse(episode.id);
    if (mark == null || streamId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    await mark(
      streamId: streamId,
      seriesId: widget.seriesId,
      seasonNumber: episode.seasonNumber,
      episodeNumber: episode.episodeNumber,
      seriesName: widget.seriesName,
      episodeTitle: episode.title,
      watched: watched,
    );
    await _loadSeriesProgress();
    _showMarkedSnack(messenger, l, watched: watched);
  }

  Future<void> _markSeason(
    List<Episode> episodes, {
    required bool watched,
  }) async {
    final mark = widget.onMarkEpisodeWatched;
    if (mark == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    await Future.wait(
      episodes.map((episode) {
        final streamId = int.tryParse(episode.id);
        if (streamId == null) return Future<void>.value();
        return mark(
          streamId: streamId,
          seriesId: widget.seriesId,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
          seriesName: widget.seriesName,
          episodeTitle: episode.title,
          watched: watched,
        );
      }),
    );
    await _loadSeriesProgress();
    _showMarkedSnack(messenger, l, watched: watched);
  }

  void _showMarkedSnack(
    ScaffoldMessengerState messenger,
    AppLocalizations l, {
    required bool watched,
  }) {
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            watched ? l.seriesMarkedWatched : l.seriesMarkedUnwatched,
          ),
        ),
      );
  }
}

class _SeriesDetailsBody extends StatelessWidget {
  const _SeriesDetailsBody({
    required this.info,
    required this.selectedSeason,
    required this.progressList,
    required this.dominantColor,
    required this.canMarkWatched,
    required this.onSeasonSelected,
    required this.onEpisodeSelected,
    required this.onMarkEpisode,
    required this.onMarkSeason,
  });

  final SeriesInfo info;
  final int? selectedSeason;
  final List<Progress> progressList;
  final Color? dominantColor;
  final bool canMarkWatched;
  final ValueChanged<int> onSeasonSelected;
  final void Function(Episode episode, {double? startPosition})
  onEpisodeSelected;
  final void Function(Episode episode, {required bool watched}) onMarkEpisode;
  final void Function(List<Episode> episodes, {required bool watched})
  onMarkSeason;

  List<int> get _seasonNumbers {
    final numbers = <int>{
      ...info.seasons.map((s) => s.number),
      ...info.episodesBySeason.keys,
    }.toList()..sort();
    return numbers;
  }

  int? get _lowestSeasonNumber =>
      _seasonNumbers.isEmpty ? null : _seasonNumbers.first;

  /// Season shown when the user has not touched the picker: the season of the
  /// episode the hero button auto-targets (furthest-along in the series), or
  /// the lowest season when nothing has been watched.
  int? get _resolvedSeason =>
      selectedSeason ??
      _autoTarget?.episode.seasonNumber ??
      _lowestSeasonNumber;

  Season? get _selectedSeasonObj {
    final n = _resolvedSeason;
    if (n == null) return null;
    return info.seasons.firstWhereOrNull((s) => s.number == n);
  }

  List<Episode> _episodes(int? seasonNumber) => seasonNumber == null
      ? const <Episode>[]
      : info.episodesBySeason[seasonNumber] ?? const <Episode>[];

  List<Episode> _sortedEpisodes(int? seasonNumber) =>
      _episodes(seasonNumber).toList()
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));

  Episode? _episodeByStreamId(int streamId) {
    for (final list in info.episodesBySeason.values) {
      for (final episode in list) {
        if (int.tryParse(episode.id) == streamId) return episode;
      }
    }
    return null;
  }

  Episode? get _firstEpisode {
    for (final key in _seasonNumbers) {
      final list = _sortedEpisodes(key);
      if (list.isNotEmpty) return list.first;
    }
    return null;
  }

  /// Watch-progress rows that belong to this series, matched by resolving the
  /// stream id against the loaded episode list. Deliberately does NOT depend
  /// on `Progress.seriesId` - recently-watched rows saved from the Continue
  /// Watching row can have a null series id, which used to make the hero
  /// button fall back to S1E1 for a show that was mid-watch.
  List<({Episode episode, Progress progress})> get _seriesProgressPairs {
    final pairs = <({Episode episode, Progress progress})>[];
    for (final p in progressList) {
      // "Mark unwatched" zeroes a row (completed:false, position:0) rather
      // than deleting it - treat that as no progress so the hero button
      // regresses when the furthest-watched episode is un-marked.
      if (!p.completed && p.positionSeconds <= 0) continue;
      final episode = _episodeByStreamId(p.streamId);
      if (episode != null) pairs.add((episode: episode, progress: p));
    }
    return pairs;
  }

  Progress? _progressFor(Episode? episode) {
    if (episode == null) return null;
    final id = int.tryParse(episode.id);
    if (id == null) return null;
    for (final p in progressList) {
      if (p.streamId == id) return p;
    }
    return null;
  }

  bool _isWatched(Episode episode) => _progressFor(episode)?.completed ?? false;

  int _order(int season, int episode) => season * 100000 + episode;

  /// The episode furthest along in the series that has any watch progress
  /// (in-progress or completed), by (season, episode) order.
  ({Episode episode, Progress progress})? get _anchor {
    ({Episode episode, Progress progress})? best;
    for (final pair in _seriesProgressPairs) {
      final s = pair.progress.seasonNumber ?? pair.episode.seasonNumber;
      final e = pair.progress.episodeNumber ?? pair.episode.episodeNumber;
      if (best == null) {
        best = pair;
        continue;
      }
      final bs = best.progress.seasonNumber ?? best.episode.seasonNumber;
      final be = best.progress.episodeNumber ?? best.episode.episodeNumber;
      if (_order(s, e) > _order(bs, be)) best = pair;
    }
    return best;
  }

  /// Hero-button target when the user has not manually picked a season:
  /// resume the furthest-along episode if it is mid-watch, otherwise the next
  /// episode after it, otherwise the very first episode.
  ({Episode episode, Progress? progress})? get _autoTarget {
    final anchor = _anchor;
    if (anchor == null) {
      final first = _firstEpisode;
      return first == null ? null : (episode: first, progress: null);
    }
    final ap = anchor.progress;
    if (!ap.completed && ap.positionSeconds > 0) {
      return (episode: anchor.episode, progress: ap);
    }
    final season = ap.seasonNumber ?? anchor.episode.seasonNumber;
    final number = ap.episodeNumber ?? anchor.episode.episodeNumber;
    final next = nextEpisodeInSeries(
      info,
      seasonNumber: season,
      episodeNumber: number,
    );
    if (next != null) {
      final np = _progressFor(next);
      final resumable = np != null && !np.completed && np.positionSeconds > 0
          ? np
          : null;
      return (episode: next, progress: resumable);
    }
    // End of the series - offer the anchor episode again.
    return (episode: anchor.episode, progress: null);
  }

  /// The episode the hero button targets. `progress` is the matching watch
  /// progress when this is a mid-episode resume (drives the inline progress
  /// bar + "start over" button), null when starting a fresh episode.
  ///
  /// With no manual season selection this follows [_autoTarget] (furthest
  /// along in the whole series). Once the user picks a season from the
  /// dropdown it becomes season-contextual: resume an in-progress episode in
  /// that season, else the next unwatched one, else that season's opener.
  ({Episode episode, Progress? progress})? get _primaryTarget {
    if (selectedSeason == null) return _autoTarget;

    final seasonNumber = _resolvedSeason;
    final seasonEpisodes = _sortedEpisodes(seasonNumber);

    final resumeInSeason = seasonEpisodes.firstWhereOrNull((e) {
      final p = _progressFor(e);
      return p != null && !p.completed && p.positionSeconds > 0;
    });
    if (resumeInSeason != null) {
      return (episode: resumeInSeason, progress: _progressFor(resumeInSeason));
    }

    final lastWatchedNum = seasonEpisodes.where(_isWatched).fold<int?>(null, (
      max,
      e,
    ) {
      final n = e.episodeNumber;
      return max == null || n > max ? n : max;
    });
    if (lastWatchedNum != null) {
      final nextInSeason = seasonEpisodes.firstWhereOrNull(
        (e) => e.episodeNumber > lastWatchedNum,
      );
      if (nextInSeason != null) {
        return (episode: nextInSeason, progress: null);
      }
      final crossSeason = nextEpisodeInSeries(
        info,
        seasonNumber: seasonNumber,
        episodeNumber: lastWatchedNum,
      );
      if (crossSeason != null) return (episode: crossSeason, progress: null);
    }

    if (seasonEpisodes.isNotEmpty) {
      return (episode: seasonEpisodes.first, progress: null);
    }
    final first = _firstEpisode;
    return first == null ? null : (episode: first, progress: null);
  }

  double? _progressFraction(Progress? p) {
    final duration = p?.durationSeconds;
    if (p == null || duration == null || duration <= 0) return null;
    return (p.positionSeconds / duration).clamp(0.0, 1.0);
  }

  String? _timeLeftLabel(BuildContext context, Progress? p) {
    final duration = p?.durationSeconds;
    if (p == null || duration == null || duration <= 0) return null;
    final remaining = (duration - p.positionSeconds).clamp(0, duration);
    final totalMinutes = (remaining / 60).ceil().clamp(1, duration);
    final l = AppLocalizations.of(context);
    if (totalMinutes < 60) return l.vodTimeLeftMinutes(totalMinutes);
    return l.vodTimeLeftHoursMinutes(totalMinutes ~/ 60, totalMinutes % 60);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = dominantColor ?? theme.colorScheme.surface;
    final season = _selectedSeasonObj;
    final seasonNumber = _resolvedSeason;
    final episodes = _episodes(seasonNumber);
    final backdrop = info.series.backdropUrl;
    final poster = (season?.coverUrl?.isNotEmpty ?? false)
        ? season!.coverUrl
        : info.series.coverUrl;
    var description = (season?.overview?.trim().isNotEmpty ?? false)
        ? season!.overview!.trim()
        : (info.series.plot ?? '');
    if (description.length > 260) {
      description = '${description.substring(0, 257)}...';
    }
    final target = _primaryTarget;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < _kSeriesCompactBreakpoint;
    final posterWidth = compact ? 120.0 : 200.0;
    // Keep the synopsis to a comfortable measure on TV/desktop (Nuvio-style);
    // let it run full width on a phone.
    final plotMaxWidth = compact ? double.infinity : screenWidth * 0.6;
    final cardWidth = compact
        ? _kEpisodeCardWidthCompact
        : _kEpisodeCardWidthWide;
    final stripHeight = cardWidth * 9 / 16 + _kEpisodeCardTextHeight;

    // Bottom-aligned over a full-bleed backdrop, mirroring the VOD detail
    // page: poster + meta (with resume progress) on top, season picker, then
    // a horizontal strip of episode thumbnail cards.
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaBrowsingMetrics.pagePadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: posterWidth,
                child: AspectRatio(
                  aspectRatio: 0.68,
                  child: ResilientMediaImage(
                    imageUrl: poster,
                    fallbackIcon: Icons.tv,
                    borderRadius: MediaBrowsingMetrics.cardRadius,
                    fallbackTitle: info.series.name,
                  ),
                ),
              ),
              const SizedBox(width: MediaBrowsingMetrics.pagePadding),
              Expanded(
                child: _seriesMetaInfo(
                  context,
                  target,
                  description,
                  plotMaxWidth,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SeasonPicker(
            seasons: info.seasons,
            selectedSeason: seasonNumber,
            canMarkWatched: canMarkWatched && episodes.isNotEmpty,
            onSeasonSelected: onSeasonSelected,
            onMarkSeason: (watched) =>
                onMarkSeason(_episodes(seasonNumber), watched: watched),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: stripHeight,
            child: episodes.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No episodes available'),
                  )
                : _EpisodeStrip(
                    episodes: episodes,
                    progressList: progressList,
                    autofocusFirst: target == null,
                    canMarkWatched: canMarkWatched,
                    cardWidth: cardWidth,
                    onEpisodeSelected: onEpisodeSelected,
                    onMarkEpisode: onMarkEpisode,
                  ),
          ),
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: bg),
        if (backdrop != null) CachedBackdropImage(backdrop),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                bg.withValues(alpha: 0.1),
                bg.withValues(alpha: 0.85),
                bg,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Bottom-aligned when it fits; scrolls up when the content is taller
        // than the viewport (short windows) so the poster/title stay reachable.
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 24,
                    bottom: constraints.maxHeight * 0.05,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _seriesMetaInfo(
    BuildContext context,
    ({Episode episode, Progress? progress})? target,
    String description,
    double plotMaxWidth,
  ) {
    final l = AppLocalizations.of(context);
    final seasonCount = info.seasons.isNotEmpty
        ? info.seasons.length
        : info.episodesBySeason.length;
    final avgRuntime = _averageRuntimeLabel;
    final chips = <String>[
      if (seasonCount > 0) '$seasonCount ${l.seriesSeasons}',
      if (info.series.rating != null) '★ ${info.series.rating}',
      ?avgRuntime,
    ];

    if (target == null) {
      return ItemMetaInfo(
        name: info.series.name,
        chips: chips,
        buttonLabel: l.seriesPlayEpisode(1, 1),
        onPlay: null,
        plot: description,
        plotMaxWidth: plotMaxWidth,
      );
    }

    final progress = target.progress;
    final progressValue = _progressFraction(progress);
    final s = target.episode.seasonNumber;
    final e = target.episode.episodeNumber;
    final buttonLabel = progressValue != null
        ? (_timeLeftLabel(context, progress) ?? l.seriesResumeEpisode(s, e))
        : l.seriesPlayEpisode(s, e);

    return ItemMetaInfo(
      name: info.series.name,
      chips: chips,
      buttonLabel: buttonLabel,
      onPlay: () => onEpisodeSelected(
        target.episode,
        startPosition: progress?.positionSeconds.toDouble(),
      ),
      onStartOver: progressValue == null
          ? null
          : () => onEpisodeSelected(target.episode, startPosition: 0),
      progressValue: progressValue,
      plot: description,
      plotMaxWidth: plotMaxWidth,
    );
  }

  /// Mean episode runtime across the whole series, rendered as a "~45m" chip.
  /// Null when no episode carries a parseable duration.
  String? get _averageRuntimeLabel {
    final minutes = <int>[];
    for (final list in info.episodesBySeason.values) {
      for (final episode in list) {
        final value = _durationTextToMinutes(episode.duration);
        if (value != null && value > 0) minutes.add(value);
      }
    }
    if (minutes.isEmpty) return null;
    final avg = (minutes.reduce((a, b) => a + b) / minutes.length).round();
    if (avg >= 60) {
      final h = avg ~/ 60;
      final m = avg % 60;
      return m == 0 ? '~${h}h' : '~${h}h ${m}m';
    }
    return '~${avg}m';
  }
}

/// Parses the loose runtime strings the editor emits ("45m", "1h 2m",
/// "45:00", "2700", "45 min") into whole minutes. Null when nothing usable.
int? _durationTextToMinutes(String? raw) {
  if (raw == null) return null;
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;
  final h = RegExp(r'(\d+)\s*h').firstMatch(text);
  final m = RegExp(r'(\d+)\s*m').firstMatch(text);
  if (h != null || m != null) {
    return (int.tryParse(h?.group(1) ?? '0') ?? 0) * 60 +
        (int.tryParse(m?.group(1) ?? '0') ?? 0);
  }
  if (text.contains(':')) {
    final parts = text.split(':').map(int.tryParse).toList();
    if (!parts.contains(null)) {
      final nums = parts.cast<int>();
      if (nums.length == 3) return nums[0] * 60 + nums[1];
      if (nums.length == 2) return nums[0];
    }
  }
  return int.tryParse(text); // bare number: assume minutes
}

/// Formats an episode air date ("2025-10-01") as "Oct 1, 2025". Falls back to
/// the raw string when it will not parse.
String? _formatEpisodeDate(String? raw, String localeTag) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return raw.trim();
  try {
    return DateFormat.yMMMd(localeTag).format(parsed);
  } on Object catch (_) {
    return DateFormat.yMMMd().format(parsed);
  }
}

/// Shared confirmation modal for the mark-watched long-press affordances.
/// Resolves to the chosen watched state, or null when dismissed. Pass
/// [presetWatched] to offer only that single action (episode toggle); leave it
/// null to offer both watched and unwatched (season bulk action).
Future<bool?> _confirmMarkWatched(
  BuildContext context, {
  required String title,
  required String message,
  bool? presetWatched,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmMarkDialog(
      title: title,
      message: message,
      presetWatched: presetWatched,
    ),
  );
}

class _ConfirmMarkDialog extends StatefulWidget {
  const _ConfirmMarkDialog({
    required this.title,
    required this.message,
    this.presetWatched,
  });

  final String title;
  final String message;
  final bool? presetWatched;

  @override
  State<_ConfirmMarkDialog> createState() => _ConfirmMarkDialogState();
}

class _ConfirmMarkDialogState extends State<_ConfirmMarkDialog> {
  // The D-pad long-press that opens this dialog is still physically held; on
  // release the package routes a phantom "select" to whichever button now has
  // focus, which would instantly confirm. Ignore every action until a short
  // arm delay has passed (matches the guard style in `dpad_ink_well.dart`).
  bool _armed = false;
  Timer? _armTimer;

  @override
  void initState() {
    super.initState();
    _armTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  void _pop(bool? result) {
    if (!_armed) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final preset = widget.presetWatched;
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
        TextButton(
          onPressed: () => _pop(null),
          child: Text(l.cancel),
        ),
        if (preset != true)
          TextButton(
            onPressed: () => _pop(false),
            child: Text(l.seriesMarkUnwatched),
          ),
        if (preset != false)
          FilledButton(
            onPressed: () => _pop(true),
            child: Text(l.seriesMarkWatched),
          ),
      ],
    );
  }
}

class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.seasons,
    required this.selectedSeason,
    required this.canMarkWatched,
    required this.onSeasonSelected,
    required this.onMarkSeason,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<bool> onMarkSeason;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final current = selectedSeason;
    return SizedBox(
      height: 44,
      child: AppButton(
        label: current != null ? l.homeSeason(current) : l.seriesSeasons,
        icon: Icons.arrow_drop_down,
        onPressed: () => _showPicker(context),
        onLongPress: canMarkWatched && current != null
            ? () => unawaited(_showMarkSeasonSheet(context, current))
            : null,
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final l = AppLocalizations.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.seriesSeasons),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  shrinkWrap: true,
                  children: seasons
                      .map(
                        (season) => ListTile(
                          title: Text(
                            season.name.isNotEmpty
                                ? season.name
                                : l.homeSeason(season.number),
                          ),
                          selected: season.number == selectedSeason,
                          onTap: () {
                            onSeasonSelected(season.number);
                            Navigator.of(context).pop();
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMarkSeasonSheet(
    BuildContext context,
    int seasonNumber,
  ) async {
    final l = AppLocalizations.of(context);
    final choice = await _confirmMarkWatched(
      context,
      title: l.homeSeason(seasonNumber),
      message: l.seriesMarkSeasonPrompt(seasonNumber),
    );
    if (choice != null) onMarkSeason(choice);
  }
}

/// Horizontal strip of episode thumbnail cards: a 16:9 still with the title,
/// SxEy, rating and runtime overlaid, the plot synopsis below, and a progress
/// bar / watched check when the viewer has history. Long-pressing a card
/// toggles its watched state.
class _EpisodeStrip extends StatefulWidget {
  const _EpisodeStrip({
    required this.episodes,
    required this.progressList,
    required this.onEpisodeSelected,
    required this.onMarkEpisode,
    required this.cardWidth,
    this.canMarkWatched = false,
    this.autofocusFirst = true,
  });

  final List<Episode> episodes;
  final List<Progress> progressList;
  final void Function(Episode episode, {double? startPosition})
  onEpisodeSelected;
  final void Function(Episode episode, {required bool watched}) onMarkEpisode;
  final double cardWidth;
  final bool canMarkWatched;
  final bool autofocusFirst;

  @override
  State<_EpisodeStrip> createState() => _EpisodeStripState();
}

class _EpisodeStripState extends State<_EpisodeStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmEpisode(
    Episode episode, {
    required bool watched,
  }) async {
    final choice = await _confirmMarkWatched(
      context,
      title: 'S${episode.seasonNumber}E${episode.episodeNumber}',
      message: episode.title,
      presetWatched: watched,
    );
    if (choice != null) widget.onMarkEpisode(episode, watched: choice);
  }

  Widget _card(BuildContext context, int index) {
    final episode = widget.episodes[index];
    final streamId = int.tryParse(episode.id);
    final progress = streamId == null
        ? null
        : widget.progressList.firstWhereOrNull((p) => p.streamId == streamId);
    final completed = progress?.completed ?? false;
    final fraction =
        (progress != null &&
            progress.durationSeconds != null &&
            progress.durationSeconds! > 0 &&
            !completed)
        ? (progress.positionSeconds / progress.durationSeconds!).clamp(0.0, 1.0)
        : null;

    return _EpisodeCard(
      episode: episode,
      width: widget.cardWidth,
      completed: completed,
      progressFraction: fraction,
      dateLabel: _formatEpisodeDate(
        episode.releaseDate,
        Localizations.localeOf(context).toLanguageTag(),
      ),
      autofocus: widget.autofocusFirst && index == 0,
      onTap: () => widget.onEpisodeSelected(episode),
      onLongTap: widget.canMarkWatched
          ? () => unawaited(_confirmEpisode(episode, watched: !completed))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: widget.episodes.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: MediaBrowsingMetrics.itemGap),
          itemBuilder: _card,
        ),
      ),
    );
  }
}

/// A single episode card: 16:9 still with title + SxEy + rating + runtime
/// overlaid over a bottom-up scrim, plot synopsis (max 3 lines) and air date
/// beneath.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.width,
    required this.completed,
    required this.progressFraction,
    required this.dateLabel,
    required this.autofocus,
    required this.onTap,
    this.onLongTap,
  });

  final Episode episode;
  final double width;
  final bool completed;
  final double? progressFraction;
  final String? dateLabel;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback? onLongTap;

  Widget _pill(BuildContext context, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: child,
    ),
  );

  Widget _pillText(BuildContext context, String text) => _pill(
    context,
    Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageHeight = width * 9 / 16;
    final runtime = episode.duration;

    return SizedBox(
      width: width,
      child: DpadInkWell(
        autofocus: autofocus,
        onTap: onTap,
        onLongTap: onLongTap,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: width,
              height: imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ResilientMediaImage(
                    imageUrl: episode.thumbnailUrl,
                    fallbackIcon: Icons.tv,
                    width: width,
                    height: imageHeight,
                    fallbackTitle: episode.title,
                    borderRadius: 0,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Color(0xE0000000),
                        ],
                        stops: [0.0, 0.35, 1.0],
                      ),
                    ),
                  ),
                  if (completed)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _pill(
                        context,
                        const Icon(
                          Icons.check,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: progressFraction != null ? 8 : 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          episode.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            shadows: const [
                              Shadow(
                                blurRadius: 4,
                                color: Colors.black87,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _pillText(
                              context,
                              'S${episode.seasonNumber}E${episode.episodeNumber}',
                            ),
                            if (episode.rating != null)
                              _pillText(
                                context,
                                '★ ${episode.rating!.toStringAsFixed(1)}',
                              ),
                            if (runtime != null && runtime.isNotEmpty)
                              _pillText(context, runtime),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (progressFraction != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progressFraction,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (episode.plot != null && episode.plot!.trim().isNotEmpty)
                      Flexible(
                        child: Text(
                          episode.plot!.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (dateLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
