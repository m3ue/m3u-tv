import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cached_backdrop_image.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Below this window width the series detail lays out for a phone: smaller
/// poster, full-width description, narrower episode cards.
const double _kSeriesCompactBreakpoint = 700;
const double _kEpisodeCardWidthWide = 340;
const double _kEpisodeCardWidthCompact = 250;

/// Text area under an episode thumbnail (3-line plot + date + padding).
const double _kEpisodeCardTextHeight = 96;

/// Marks one series episode watched / unwatched for the active viewer.
/// Structurally matches `ContentActions.onMarkEpisodeWatched`. Resolves to
/// whether the server write succeeded (local state updates regardless).
typedef MarkEpisodeWatched =
    Future<bool> Function({
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
        // The body (and its play button) only mounts once this resolves, by
        // which point the scaffold back button has already taken default
        // focus - move it to the play/resume action instead.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playFocusNode.requestFocus();
        });
        return info;
      });
  int? _selectedSeason;
  SeriesInfo? _seriesInfo;
  Color? _dominantColor;
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'seriesPlayButton');

  @override
  void dispose() {
    _playFocusNode.dispose();
    super.dispose();
  }

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
    final color = await resolveDominantBackdropColor(url);
    if (color != null && mounted) setState(() => _dominantColor = color);
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
            playFocusNode: _playFocusNode,
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

  Future<bool> _markOne(
    MarkEpisodeWatched mark,
    Episode episode, {
    required bool watched,
  }) {
    final streamId = int.tryParse(episode.id);
    if (streamId == null) return Future.value(false);
    return mark(
      streamId: streamId,
      seriesId: widget.seriesId,
      seasonNumber: episode.seasonNumber,
      episodeNumber: episode.episodeNumber,
      seriesName: widget.seriesName,
      episodeTitle: episode.title,
      watched: watched,
    );
  }

  Future<void> _markEpisode(Episode episode, {required bool watched}) async {
    final mark = widget.onMarkEpisodeWatched;
    if (mark == null || int.tryParse(episode.id) == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final ok = await _markOne(mark, episode, watched: watched);
    await _loadSeriesProgress();
    _showMarkedSnack(messenger, l, watched: watched, failed: !ok);
  }

  Future<void> _markSeason(
    List<Episode> episodes, {
    required bool watched,
  }) async {
    final mark = widget.onMarkEpisodeWatched;
    if (mark == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    // Sequential, not Future.wait: a 20+ episode season would otherwise fire
    // that many concurrent progress writes at the editor at once.
    var failures = 0;
    for (final episode in episodes) {
      if (!await _markOne(mark, episode, watched: watched)) failures++;
    }
    await _loadSeriesProgress();
    _showMarkedSnack(messenger, l, watched: watched, failed: failures > 0);
  }

  void _showMarkedSnack(
    ScaffoldMessengerState messenger,
    AppLocalizations l, {
    required bool watched,
    required bool failed,
  }) {
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            failed
                ? l.seriesMarkSyncFailed
                : (watched ? l.seriesMarkedWatched : l.seriesMarkedUnwatched),
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
    required this.playFocusNode,
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
  final FocusNode playFocusNode;
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

  /// Episode tally for a season: the loaded episode list when we have it,
  /// otherwise the count the provider reported on the season record.
  int _episodeCountFor(int seasonNumber) {
    final loaded = _episodes(seasonNumber).length;
    if (loaded > 0) return loaded;
    return info.seasons
            .firstWhereOrNull((s) => s.number == seasonNumber)
            ?.episodeCount ??
        0;
  }

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
    // Season poster first, then the series poster, then the backdrop. Passed
    // as a chain so a season cover that 404s actually falls through at load
    // time (not just when it's null) rather than sticking on a placeholder.
    final posterChain = <String>[
      ?_trimmedOrNull(season?.coverUrl),
      ?_trimmedOrNull(info.series.coverUrl),
      ?_trimmedOrNull(backdrop),
    ];
    final description = (season?.overview?.trim().isNotEmpty ?? false)
        ? season!.overview!.trim()
        : (info.series.plot ?? '');
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

    final poster = SizedBox(
      width: posterWidth,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: ResilientMediaImage(
          imageUrl: posterChain.isEmpty ? null : posterChain.first,
          fallbackImageUrls: posterChain.skip(1).toList(),
          fallbackIcon: Icons.tv,
          borderRadius: MediaBrowsingMetrics.cardRadius,
          fallbackTitle: info.series.name,
        ),
      ),
    );
    final meta = _seriesMetaInfo(context, target, description, plotMaxWidth);
    // Phone: poster stacked above the title / chips / description. TV and
    // desktop: poster beside them.
    final header = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [poster, const SizedBox(height: 16), meta],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              poster,
              const SizedBox(width: MediaBrowsingMetrics.pagePadding),
              Expanded(child: meta),
            ],
          );

    // Bottom-aligned over a full-bleed backdrop, mirroring the VOD detail
    // page: poster + meta (with resume progress) on top, season picker, then
    // the episode cards (a horizontal strip on TV, a vertical list on a phone).
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaBrowsingMetrics.pagePadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: 20),
          // Play / Start-from-beginning sit on the same line as the season
          // picker (wrapping to a second run on a phone).
          Wrap(
            spacing: MediaBrowsingMetrics.itemGap,
            runSpacing: MediaBrowsingMetrics.chipGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ..._primaryActions(context, target),
              _SeasonPicker(
                seasons: info.seasons,
                selectedSeason: seasonNumber,
                canMarkWatched: canMarkWatched && episodes.isNotEmpty,
                episodeCountFor: _episodeCountFor,
                fallbackPosterUrl: _trimmedOrNull(info.series.coverUrl),
                onSeasonSelected: onSeasonSelected,
                onMarkSeason: (watched) =>
                    onMarkSeason(_episodes(seasonNumber), watched: watched),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (episodes.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No episodes available'),
            )
          else if (compact)
            _EpisodeStrip(
              episodes: episodes,
              progressList: progressList,
              autofocusFirst: target == null,
              canMarkWatched: canMarkWatched,
              cardWidth: cardWidth,
              horizontal: false,
              onEpisodeSelected: onEpisodeSelected,
              onMarkEpisode: onMarkEpisode,
            )
          else
            SizedBox(
              height: stripHeight,
              child: _EpisodeStrip(
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

    // On mobile the backdrop only sets the scene - a full-height image would
    // push the poster/title/episodes below the fold. Cap it to half the
    // viewport and let the rest of the page scroll on solid background
    // colour underneath, like the VOD detail page's narrow layout.
    if (compact) {
      return _buildCompact(context, bg, backdrop, content);
    }

    // Scrim over the backdrop. Kept heavy enough that a bright still
    // (near-white kitchen shots etc.) still leaves the body text legible,
    // while the top stays translucent so the art reads through. Bottom-
    // aligned when it fits; scrolls up when the content is taller than the
    // viewport (short windows) so the poster/title stay reachable.
    return BackdropDetailHero(
      backdropUrl: backdrop,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      scrollWhenTall: true,
      contentPaddingBuilder: (constraints) => EdgeInsets.only(
        top: 24,
        bottom: constraints.maxHeight * 0.05,
      ),
      content: content,
    );
  }

  Widget _buildCompact(
    BuildContext context,
    Color bg,
    String? backdrop,
    Widget content,
  ) {
    final bandHeight = MediaQuery.sizeOf(context).height * 0.5;
    // The band stays fixed (it lives outside the scroll view, not stacked
    // above it) while `content` scrolls over/past it - same mechanic as the
    // wide layout below, just top-aligned instead of bottom-pinned.
    return BackdropDetailHero(
      backdropUrl: backdrop,
      backdropHeight: bandHeight,
      contentAlignment: Alignment.topLeft,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      // Let the poster/title ride well up into the lower half of the
      // backdrop (standard mobile hero look) rather than clearing it.
      contentPadding: EdgeInsets.only(top: bandHeight * 0.55, bottom: 24),
      content: content,
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

    // The play / start-over buttons are rendered separately (on the season
    // picker's line), so this only carries title + chips + synopsis.
    return ItemMetaInfo(
      name: info.series.name,
      chips: chips,
      hidePrimaryAction: true,
      buttonLabel: '',
      onPlay: null,
      plot: description,
      plotMaxWidth: plotMaxWidth,
      plotMaxLines: 4,
    );
  }

  /// The play/resume + start-from-beginning buttons, laid out on the season
  /// picker's line. Mirrors what `ItemMetaInfo` renders on the VOD screen.
  List<Widget> _primaryActions(
    BuildContext context,
    ({Episode episode, Progress? progress})? target,
  ) {
    final l = AppLocalizations.of(context);
    if (target == null) {
      return [
        AppButton(
          focusNode: playFocusNode,
          variant: AppButtonVariant.primaryInverted,
          icon: Icons.play_arrow,
          label: l.seriesPlayEpisode(1, 1),
          onPressed: null,
        ),
      ];
    }

    final progress = target.progress;
    final progressValue = _progressFraction(progress);
    final s = target.episode.seasonNumber;
    final e = target.episode.episodeNumber;
    final label = progressValue != null
        ? (_timeLeftLabel(context, progress) ?? l.seriesResumeEpisode(s, e))
        : l.seriesPlayEpisode(s, e);

    return [
      AppButton(
        focusNode: playFocusNode,
        autofocus: true,
        variant: AppButtonVariant.primaryInverted,
        icon: Icons.play_arrow,
        label: label,
        inlineProgressValue: progressValue,
        onPressed: () => onEpisodeSelected(
          target.episode,
          startPosition: progress?.positionSeconds.toDouble(),
        ),
      ),
      if (progressValue != null)
        AppButton(
          icon: Icons.replay,
          label: l.playerStartFromBeginning,
          onPressed: () => onEpisodeSelected(target.episode, startPosition: 0),
        ),
    ];
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

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Parses the loose runtime strings the editor emits ("45m", "1h 2m",
/// "45 min", "45:00", "01:02:00", "2700") into whole minutes. Null when
/// nothing usable.
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
  final bare = int.tryParse(text);
  if (bare == null) return null;
  // Match `_durationText`'s own convention (domain_models.dart): a bare count
  // over 300 is seconds, otherwise minutes.
  return bare > 300 ? (bare / 60).round() : bare;
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
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.onSeasonSelected,
    required this.onMarkSeason,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;

  /// Episode tally for a given season number (0 when unknown).
  final int Function(int seasonNumber) episodeCountFor;

  /// Series poster, shown in the pick-list when a season has no art of its own.
  final String? fallbackPosterUrl;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<bool> onMarkSeason;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final current = selectedSeason;
    final count = current != null ? episodeCountFor(current) : 0;
    // No size overrides - shares AppButton's default metrics so it lines up
    // with the play / start-over buttons beside it.
    return AppButton(
      label: current != null ? l.homeSeason(current) : l.seriesSeasons,
      icon: Icons.arrow_drop_down,
      badgeCount: count > 0 ? count : null,
      // Muted, not the default error red - this is an episode tally, not an
      // unwatched/new alert.
      badgeColor: scheme.surfaceContainerHighest,
      badgeTextColor: scheme.onSurfaceVariant,
      onPressed: () => _showPicker(context),
      onLongPress: canMarkWatched && current != null
          ? () => unawaited(_showMarkSeasonSheet(context, current))
          : null,
    );
  }

  void _showPicker(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Focus lands on the current season (or the first one) so the list is
    // immediately drivable by D-pad.
    final focusSeason = selectedSeason ?? seasons.first.number;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          clipBehavior: Clip.antiAlias,
          title: Text(l.seriesSeasons),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          content: SizedBox(
            width: 460,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.65,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                // Contain D-pad traversal to the list - up/down moves between
                // rows and stops at the ends instead of escaping the dialog.
                child: DpadRegion(
                  verticalEdge: DpadEdgeBehavior.stop,
                  horizontalEdge: DpadEdgeBehavior.stop,
                  child: ListView(
                    shrinkWrap: true,
                    // Inset so a focused row's gradient border sits inside the
                    // dialog's rounded corners and clear of the scrollbar.
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    children: seasons
                        .map(
                          (season) => _seasonTile(
                            context,
                            season,
                            autofocus: season.number == focusSeason,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seasonTile(
    BuildContext context,
    Season season, {
    required bool autofocus,
  }) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = episodeCountFor(season.number);
    final seasonCover = _trimmedOrNull(season.coverUrl);
    final overview = _trimmedOrNull(season.overview);
    final selected = season.number == selectedSeason;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DpadInkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        onTap: () {
          onSeasonSelected(season.number);
          Navigator.of(context).pop();
        },
        // Poster + text laid out by hand (not a ListTile) so nothing gets
        // crushed to fit a short two-line row.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: AspectRatio(
                  aspectRatio: 0.68,
                  child: ResilientMediaImage(
                    imageUrl: seasonCover ?? fallbackPosterUrl,
                    fallbackImageUrls:
                        seasonCover != null && fallbackPosterUrl != null
                        ? <String>[fallbackPosterUrl!]
                        : const <String>[],
                    fallbackIcon: Icons.tv,
                    borderRadius: 6,
                    fallbackTitle: season.name,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        season.name.isNotEmpty
                            ? season.name
                            : l.homeSeason(season.number),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (count > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l.seriesEpisodeCount(count),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (overview != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            overview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // A plain checkmark (not primary-tinted text) marks the active
              // season, so it reads as "this one is selected" rather than
              // being mistaken for the D-pad cursor.
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Icon(Icons.check, size: 22, color: scheme.primary),
                ),
            ],
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
    this.horizontal = true,
  });

  final List<Episode> episodes;
  final List<Progress> progressList;
  final void Function(Episode episode, {double? startPosition})
  onEpisodeSelected;
  final void Function(Episode episode, {required bool watched}) onMarkEpisode;
  final double cardWidth;
  final bool canMarkWatched;
  final bool autofocusFirst;

  /// Horizontal thumbnail strip (TV/desktop) vs. a vertical list (phone).
  final bool horizontal;

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
      horizontal: widget.horizontal,
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
    if (!widget.horizontal) {
      // Phone: a plain vertical column - the page's own scroll view drives it,
      // so no inner ListView / ScrollController.
      return DpadRegion(
        verticalEdge: DpadEdgeBehavior.stop,
        child: Column(
          children: [
            for (var i = 0; i < widget.episodes.length; i++) ...[
              if (i > 0) const SizedBox(height: MediaBrowsingMetrics.itemGap),
              _card(context, i),
            ],
          ],
        ),
      );
    }
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

/// A single episode card. Horizontal (TV/desktop): a fixed-width 16:9 still
/// with title + SxEy + rating + runtime overlaid over a bottom-up scrim, plot
/// synopsis and air date beneath. Vertical (phone): a full-width row with a
/// small thumbnail on the left and the title / meta / plot / date beside it.
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
    this.horizontal = true,
  });

  final Episode episode;
  final double width;
  final bool completed;
  final double? progressFraction;
  final String? dateLabel;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback? onLongTap;
  final bool horizontal;

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
    final runtime = episode.duration;

    if (!horizontal) {
      return _buildVertical(context, theme, colorScheme, runtime);
    }

    final imageHeight = width * 9 / 16;
    final titleBase = theme.textTheme.titleSmall;
    // ~60% larger than the stock card title.
    final titleStyle = titleBase?.copyWith(
      fontSize: (titleBase.fontSize ?? 14) * 1.6,
      height: 1.15,
      color: Colors.white,
      fontWeight: FontWeight.w700,
      shadows: const [
        Shadow(blurRadius: 4, color: Colors.black87, offset: Offset(0, 1)),
      ],
    );

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
                          style: titleStyle,
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

  Widget _buildVertical(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    String? runtime,
  ) {
    const thumbWidth = 132.0;
    const thumbHeight = thumbWidth * 9 / 16;
    final metaParts = <String>[
      'S${episode.seasonNumber}E${episode.episodeNumber}',
      if (episode.rating != null) '★ ${episode.rating!.toStringAsFixed(1)}',
      if (runtime != null && runtime.isNotEmpty) runtime,
    ];

    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      onLongTap: onLongTap,
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: thumbWidth,
                height: thumbHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ResilientMediaImage(
                      imageUrl: episode.thumbnailUrl,
                      fallbackIcon: Icons.tv,
                      width: thumbWidth,
                      height: thumbHeight,
                      fallbackTitle: episode.title,
                      borderRadius: 0,
                    ),
                    if (completed)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _pill(
                          context,
                          const Icon(
                            Icons.check,
                            size: 12,
                            color: Colors.white,
                          ),
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metaParts.join('  ·  '),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (episode.plot != null &&
                      episode.plot!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      episode.plot!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
