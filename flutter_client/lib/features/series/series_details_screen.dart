import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_strip.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
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

  /// The season currently shown in the body (user pick or auto-resolved
  /// default), reported back up by [_SeriesDetailsBody] so the AppBar title
  /// can read "Show Name - S2".
  int? _displayedSeason;
  SeriesInfo? _seriesInfo;
  Color? _dominantColor;

  /// True once the palette extraction has resolved (with a colour or not).
  /// Gates the hero's backdrop reveal so the art and its colour-match fade
  /// in together instead of the backdrop popping and the tint snapping after.
  bool _colorMatchResolved = false;
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
    if (!mounted) return;
    setState(() {
      if (color != null) _dominantColor = color;
      _colorMatchResolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _displayedSeason != null
        ? '${widget.seriesName} - S$_displayedSeason'
        : widget.seriesName;
    return ItemDetailScaffold(
      title: title,
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
            colorMatchReady: _colorMatchResolved,
            canMarkWatched: widget.onMarkEpisodeWatched != null,
            playFocusNode: _playFocusNode,
            onSeasonSelected: (season) =>
                setState(() => _selectedSeason = season),
            onSeasonResolved: (season) {
              if (season != _displayedSeason) {
                setState(() => _displayedSeason = season);
              }
            },
            onEpisodeSelected: _playEpisode,
            onMarkEpisode: _markEpisode,
            onMarkSeason: _markSeason,
          );
        },
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    // Plain surface behind the spinner - no blurred-poster wash. The detail
    // hero already holds this same surface colour until the backdrop and its
    // colour-match are ready, so the load reads as one continuous surface
    // rather than poster-wash -> surface -> backdrop.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const Center(child: CircularProgressIndicator()),
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
    required this.colorMatchReady,
    required this.canMarkWatched,
    required this.playFocusNode,
    required this.onSeasonSelected,
    required this.onSeasonResolved,
    required this.onEpisodeSelected,
    required this.onMarkEpisode,
    required this.onMarkSeason,
  });

  final SeriesInfo info;
  final int? selectedSeason;
  final List<Progress> progressList;
  final Color? dominantColor;

  /// Passed straight to [BackdropDetailHero.colorMatchReady] - true once the
  /// palette extraction has resolved, so the hero can fade the backdrop and
  /// its colour-match in together.
  final bool colorMatchReady;
  final bool canMarkWatched;
  final FocusNode playFocusNode;
  final ValueChanged<int> onSeasonSelected;

  /// Fires (post-frame) with the season currently in view - the user's pick
  /// or, before they touch the picker, the auto-resolved default - so the
  /// screen's AppBar title can show which season is active.
  final ValueChanged<int?> onSeasonResolved;
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
    // Phone gets a lighter, more saturated wash - the deep full-bleed tone
    // that reads as "a colour" on a TV just looks black on a small portrait
    // screen where the backdrop is only a short band.
    final bg = dominantColor != null
        ? deepBackdropTone(dominantColor!, vivid: compact)
        : theme.colorScheme.surface;
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: _posterShuffleTransition,
          // Keep the outgoing poster painted on top so it reads as the old
          // card being dealt off the deck to reveal the new one sliding in
          // underneath (the default stacks the incoming child on top).
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ?currentChild,
              ...previousChildren,
            ],
          ),
          child: ResilientMediaImage(
            key: ValueKey<String>(
              'season-$seasonNumber-'
              '${posterChain.isEmpty ? '' : posterChain.first}',
            ),
            imageUrl: posterChain.isEmpty ? null : posterChain.first,
            fallbackImageUrls: posterChain.skip(1).toList(),
            fallbackIcon: Icons.tv,
            borderRadius: MediaBrowsingMetrics.cardRadius,
            fallbackTitle: info.series.name,
          ),
        ),
      ),
    );
    final meta = _seriesMetaInfo(context, target, description, plotMaxWidth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSeasonResolved(seasonNumber);
    });
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

    // poster + meta (with resume progress) and the play / season-picker row
    // form the "upper" block; the episode cards sit directly below it (a
    // horizontal strip on TV, a vertical list on a phone).
    final upper = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 20),
        // Play / Start-from-beginning sit on the same line as the season
        // picker (wrapping to a second run on a phone). On the narrow
        // breakpoint the cast picker chip joins this row beside the
        // season picker.
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
              compact: compact,
              episodeCountFor: _episodeCountFor,
              fallbackPosterUrl: _trimmedOrNull(info.series.coverUrl),
              onSeasonSelected: onSeasonSelected,
              onMarkSeason: (watched) =>
                  onMarkSeason(_episodes(seasonNumber), watched: watched),
            ),
            if (compact &&
                info.series.richCast != null &&
                info.series.richCast!.isNotEmpty)
              CastMemberRow(
                members: info.series.richCast,
                semanticLabel: AppLocalizations.of(context).seriesCast,
                compact: true,
                onShowAll: () => showAllCast(context, info.series.richCast!),
                allCastSemanticLabel: AppLocalizations.of(context).castShowAll,
              ),
          ],
        ),
      ],
    );

    final Widget episodeSection;
    if (episodes.isEmpty) {
      episodeSection = const Align(
        alignment: Alignment.centerLeft,
        child: Text('No episodes available'),
      );
    } else if (compact) {
      episodeSection = _EpisodeStrip(
        episodes: episodes,
        progressList: progressList,
        autofocusFirst: target == null,
        canMarkWatched: canMarkWatched,
        cardWidth: cardWidth,
        horizontal: false,
        onEpisodeSelected: onEpisodeSelected,
        onMarkEpisode: onMarkEpisode,
      );
    } else {
      episodeSection = SizedBox(
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
      );
    }

    // On mobile the backdrop only sets the scene - a full-height image would
    // push the poster/title/episodes below the fold. Cap it to half the
    // viewport and let the rest of the page scroll on solid background
    // colour underneath, like the VOD detail page's narrow layout.
    if (compact) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MediaBrowsingMetrics.pagePadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            upper,
            const SizedBox(height: 12),
            episodeSection,
          ],
        ),
      );
      return _buildCompact(context, bg, backdrop, content);
    }

    // TV / desktop: a fixed header (poster + meta + Play / season row) over a
    // vertical scroll region that stacks the episode strip and, when the
    // server resolved a cast, the cast row. Each row is a single dpad stop
    // (see _EpisodeStrip / _CastStrip) - left/right stay inside the row,
    // up/down hand focus to the neighbouring row and dpad's own padded
    // auto-scroll reveals the newly focused row. There are no per-card focus
    // nodes for dpad's ensure-visible to chase, so horizontal navigation
    // never drags the page - the regression the old pinned-strip layout
    // worked around. The compact cast chip stays on the narrow layout.
    final richCast = info.series.richCast;
    final l = AppLocalizations.of(context);
    final wideContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaBrowsingMetrics.pagePadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          upper,
          const SizedBox(height: 12),
          Expanded(
            child: _RowScrollRegion(
              onExitTop: playFocusNode.requestFocus,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  episodeSection,
                  if (richCast != null && richCast.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      l.seriesCast,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SeriesCastRow(members: richCast),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Scrim over the backdrop. Kept heavy enough that a bright still
    // (near-white kitchen shots etc.) still leaves the body text legible,
    // while the top stays translucent so the art reads through. The hero
    // holds a flat surface until the backdrop has decoded and the dominant
    // colour has resolved, then fades the art + wash + scrim in as one
    // (BackdropDetailHero.colorMatchReady) so nothing snaps in piecemeal.
    return BackdropDetailHero(
      backdropUrl: backdrop,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [
        bg.withValues(alpha: 0.35),
        bg.withValues(alpha: 0.92),
        bg,
      ],
      colorMatchReady: colorMatchReady,
      contentPadding: const EdgeInsets.only(top: 24, bottom: 24),
      content: wideContent,
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
    // wide layout below, just top-aligned instead of bottom-pinned. Lighter
    // top/mid scrim than the wide layout so the real backdrop colour still
    // reads in the band on a portrait screen. Same held-then-fade reveal as
    // the wide layout (BackdropDetailHero.colorMatchReady).
    return BackdropDetailHero(
      backdropUrl: backdrop,
      backdropHeight: bandHeight,
      contentAlignment: Alignment.topLeft,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [
        bg.withValues(alpha: 0.2),
        bg.withValues(alpha: 0.8),
        bg,
      ],
      colorMatchReady: colorMatchReady,
      // Let the poster/title ride well up into the lower half of the
      // backdrop (standard mobile hero look) rather than clearing it.
      contentPadding: EdgeInsets.only(top: bandHeight * 0.44, bottom: 24),
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
      clearLogoUrl: info.series.clearLogoUrl,
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

/// Card-shuffle transition for the season poster. The incoming poster slides
/// up into place from the top-right with a slight counter-rotation and scale
/// settle; run in reverse (the outgoing poster) it deals the old card back
/// off toward the same corner. Mirrors the fade + slide the episode strip
/// plays on a season change so the two move together.
Widget _posterShuffleTransition(Widget child, Animation<double> animation) {
  final eased = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: eased,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.22, -0.16),
        end: Offset.zero,
      ).animate(eased),
      child: RotationTransition(
        turns: Tween<double>(begin: 0.025, end: 0).animate(eased),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(eased),
          child: child,
        ),
      ),
    ),
  );
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
        DpadRegion(
          memoryKey: 'series/mark-watched-dialog-actions',
          // OverflowBar (not Row) so the buttons stack vertically on a narrow
          // dialog instead of overflowing. Same shared-button treatment as the
          // resume and DVR modals.
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              AppButton(
                label: l.cancel,
                onPressed: () => _pop(null),
              ),
              if (preset != true)
                AppButton(
                  label: l.seriesMarkUnwatched,
                  variant: preset == false
                      ? AppButtonVariant.primary
                      : AppButtonVariant.tonal,
                  autofocus: preset == false,
                  onPressed: () => _pop(false),
                ),
              if (preset != false)
                AppButton(
                  label: l.seriesMarkWatched,
                  variant: AppButtonVariant.primary,
                  autofocus: true,
                  onPressed: () => _pop(true),
                ),
            ],
          ),
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
    required this.compact,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.onSeasonSelected,
    required this.onMarkSeason,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;

  /// Phone layout: the picker opens as a bottom sheet instead of a centered
  /// dialog.
  final bool compact;

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

    // Header (title + close affordance) and the season rows live in ONE
    // DpadRegion, so D-pad up from the first row reaches the close button.
    // Traversal stops at the region edges instead of escaping the
    // sheet/dialog. The list is height-capped with a ConstrainedBox (not
    // Flexible) so the layout stays deterministic inside AlertDialog's
    // intrinsic sizing - a Flexible there lets the rows overflow the dialog's
    // clip and drop out of hit-testing.
    //
    // [modalContext] is the sheet/dialog builder's own context: every dismiss
    // (close button, a season pick) must pop through it, NOT the outer
    // `_showPicker` context, which resolves to the screen's navigator and
    // would pop the whole route while leaving the modal on the root navigator.
    Widget pickerBody(
      BuildContext modalContext, {
      required EdgeInsetsGeometry listPadding,
      required double maxListHeight,
      bool showThumb = false,
    }) {
      return DpadRegion(
        verticalEdge: DpadEdgeBehavior.stop,
        horizontalEdge: DpadEdgeBehavior.stop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.seriesSeasons,
                      style: Theme.of(modalContext).textTheme.titleLarge,
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close,
                    dense: true,
                    tooltip: l.cancel,
                    onPressed: () => Navigator.of(modalContext).pop(),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: Scrollbar(
                thumbVisibility: showThumb,
                child: ListView(
                  shrinkWrap: true,
                  // Inset so a focused row's gradient border sits clear of the
                  // container edge and the scrollbar.
                  padding: listPadding,
                  children: seasons
                      .map(
                        (season) => _seasonTile(
                          modalContext,
                          season,
                          autofocus: season.number == focusSeason,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;

    if (compact) {
      // Phone: a bottom sheet reads more naturally than a centered dialog and
      // keeps the tap targets in thumb reach.
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: pickerBody(
              sheetContext,
              listPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              maxListHeight: viewportHeight * 0.7,
            ),
          ),
        ),
      );
      return;
    }

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          clipBehavior: Clip.antiAlias,
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          content: SizedBox(
            width: 460,
            child: pickerBody(
              dialogContext,
              listPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              maxListHeight: viewportHeight * 0.65,
              showThumb: true,
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

class _EpisodeStripState extends State<_EpisodeStrip>
    with SingleTickerProviderStateMixin
    implements _LockedRow {
  final ScrollController _controller = ScrollController();

  // Drives the fade + slight rightward slide the strip plays on first build
  // and each time the season (and with it the whole episode list) changes,
  // so the new episodes ease in rather than snapping over the old ones.
  late final AnimationController _seasonAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _seasonFade = CurvedAnimation(
    parent: _seasonAnim,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _seasonSlide =
      Tween<Offset>(
        begin: const Offset(0.05, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: _seasonAnim, curve: Curves.easeOutCubic),
      );

  // TV / desktop only: the whole strip is one focus stop. `_focusedIndex` is
  // the highlighted card; `_hasFocus` mirrors the strip node so the cards
  // only paint a border while the row actually holds focus.
  final FocusNode _focusNode = FocusNode(debugLabel: 'episodeStrip');
  final _SelectHold _selectHold = _SelectHold();
  int _focusedIndex = 0;
  bool _hasFocus = false;

  /// Set on the wide layout: the enclosing scroll region this strip is a row
  /// of. Drives both the into-view reveal and up/down row hops. Null on the
  /// phone layout (plain page scroll, no region).
  _RowScrollRegionState? _region;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    unawaited(_seasonAnim.forward());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.horizontal) return;
    final region = _RowScrollRegion.of(context);
    if (region != _region) {
      _region?.unregisterRow(this);
      _region = region;
      _region?.registerRow(this);
    }
  }

  @override
  void didUpdateWidget(_EpisodeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A season switch swaps the episode list under the row; keep the cursor
    // in range so the next left/right starts from a real card, and replay the
    // ease-in so the new season's episodes animate over the old ones instead
    // of snapping.
    if (!identical(oldWidget.episodes, widget.episodes)) {
      unawaited(_seasonAnim.forward(from: 0));
    }
    if (_focusedIndex >= widget.episodes.length) {
      _focusedIndex = widget.episodes.isEmpty ? 0 : widget.episodes.length - 1;
    }
  }

  @override
  void dispose() {
    _region?.unregisterRow(this);
    _selectHold.dispose();
    _seasonAnim.dispose();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      // Focus can also arrive from outside the region (autofocus on load, or
      // down from the Play button via dpad traversal). Centre the cursor and
      // reveal the strip either way; focusRow() does the same when the hop
      // comes from a sibling row.
      _centerFocused(animate: false);
      _region?.reveal(context);
    }
  }

  @override
  void focusRow() {
    _focusNode.requestFocus();
    _centerFocused(animate: false);
    _region?.reveal(context);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_SelectHold.isSelectKey(key)) {
      return _selectHold.handle(
        event,
        isActive: () => mounted,
        onTap: _selectFocused,
        onLongPress: widget.canMarkWatched ? _longSelectFocused : null,
      );
    }
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isDown) _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isDown) _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final region = _region;
      if (region == null) return KeyEventResult.ignored;
      if (isDown) region.navigateVertical(this, up: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final region = _region;
      if (region == null) return KeyEventResult.ignored;
      if (isDown) region.navigateVertical(this, up: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double get _itemExtent => widget.cardWidth + MediaBrowsingMetrics.itemGap;

  /// Scroll the row's OWN controller so the focused card is centered. This is
  /// the only place the strip scrolls horizontally and it never walks an
  /// ancestor scrollable - the reason left/right navigation no longer drags
  /// the page. (dpad's focus-follow reveal only ever pulled the page when
  /// each card was its own focus node.)
  ///
  /// KNOWN ISSUE (not yet bullet-proof - needs more device testing): under
  /// aggressive fast left/right key-repeat this `animateTo` can still land its
  /// `DrivenScrollActivity` goBallistic -> goIdle transition inside the
  /// semantics flush, tripping Flutter's
  /// `!attached || !owner!._debugDoingSemantics` assertion storm
  /// (`ScrollableState.setIgnorePointer` -> `RenderIgnorePointer.ignoring=` ->
  /// `markNeedsSemanticsUpdate`). It is visually harmless (debug-only assert)
  /// and self-recovers, but the real fix is still open. A
  /// `FrameSafeScrollController` that deferred/collapsed these jumps out of the
  /// frame pipeline killed the asserts but broke normal recenter (focus
  /// advanced, scroll lagged a frame and sometimes never landed), so it was
  /// reverted. Candidate directions to try next: gate the recenter to
  /// KeyDown-only (skip KeyRepeat), debounce `_centerFocused`, or drop the
  /// tween for an unconditional `jumpTo` on repeat.
  void _centerFocused({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final target =
          (_focusedIndex * _itemExtent +
                  widget.cardWidth / 2 -
                  position.viewportDimension / 2)
              .clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      if (animate) {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ),
        );
      } else {
        position.jumpTo(target);
      }
    });
  }

  void _moveFocus(int delta) {
    if (widget.episodes.isEmpty) return;
    final target = (_focusedIndex + delta).clamp(0, widget.episodes.length - 1);
    if (target == _focusedIndex) return;
    setState(() => _focusedIndex = target);
    _centerFocused();
  }

  Episode? get _focusedEpisode =>
      (_focusedIndex >= 0 && _focusedIndex < widget.episodes.length)
      ? widget.episodes[_focusedIndex]
      : null;

  void _selectFocused() {
    final episode = _focusedEpisode;
    if (episode != null) widget.onEpisodeSelected(episode);
  }

  void _longSelectFocused() {
    final episode = _focusedEpisode;
    if (episode == null) return;
    final streamId = int.tryParse(episode.id);
    final progress = streamId == null
        ? null
        : widget.progressList.firstWhereOrNull((p) => p.streamId == streamId);
    unawaited(
      _confirmEpisode(episode, watched: !(progress?.completed ?? false)),
    );
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
      // Horizontal (TV/desktop): the strip owns focus, the card only shows the
      // border when it is the current index. Vertical (phone): each card owns
      // its focus node, so the first one autofocuses.
      focused: widget.horizontal && _hasFocus && index == _focusedIndex,
      autofocus: !widget.horizontal && widget.autofocusFirst && index == 0,
      onTap: () => widget.onEpisodeSelected(episode),
      onLongTap: widget.canMarkWatched
          ? () => unawaited(_confirmEpisode(episode, watched: !completed))
          : null,
    );
  }

  /// Wraps the strip in the fade + slide the season transition plays.
  Widget _withSeasonTransition(Widget child) => FadeTransition(
    opacity: _seasonFade,
    child: SlideTransition(position: _seasonSlide, child: child),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.horizontal) {
      // Phone: a plain vertical column - the page's own scroll view drives it,
      // so no inner ListView / ScrollController.
      return _withSeasonTransition(
        DpadRegion(
          verticalEdge: DpadEdgeBehavior.stop,
          child: Column(
            children: [
              for (var i = 0; i < widget.episodes.length; i++) ...[
                if (i > 0) const SizedBox(height: MediaBrowsingMetrics.itemGap),
                _card(context, i),
              ],
            ],
          ),
        ),
      );
    }
    // TV / desktop: a "locked focus" row, modelled on Plezy. The whole strip
    // is ONE plain Focus stop whose onKeyEvent handles every arrow + select
    // key itself and always consumes them - so nothing ever reaches dpad's
    // directional traversal / "scroll for more" retry, which was leaving
    // focus a row behind and the strip clipped on tvOS. left/right move an
    // internal index and scroll this row's own controller; up/down go to the
    // enclosing _RowScrollRegion.
    // No Scrollbar wrapper: it reacts to every scroll-position change and,
    // under fast key-repeat, its interplay with the ListView's own
    // ignore-pointer toggling during scroll-activity transitions throws the
    // `!_debugDoingSemantics` assertion storm. The cast row (identical minus
    // the Scrollbar) never races - so the strip drops it too. Desktop still
    // scrolls the ListView with the mouse wheel directly.
    return _withSeasonTransition(
      Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocusFirst,
        descendantsAreFocusable: false,
        onKeyEvent: _handleKeyEvent,
        // Desktop mouse users get hover arrows (the scrollbar is hidden); TV /
        // phone pass straight through and D-pad / touch drive the scroll.
        child: HoverScrollArrows(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: widget.episodes.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(
                right: MediaBrowsingMetrics.itemGap,
              ),
              child: _card(context, index),
            ),
          ),
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
    this.focused = false,
  });

  final Episode episode;
  final double width;
  final bool completed;
  final double? progressFraction;
  final String? dateLabel;

  /// Vertical (phone) only: this card owns its focus node and grabs focus on
  /// first build.
  final bool autofocus;

  /// Horizontal (TV/desktop) only: the parent [_EpisodeStrip] owns focus and
  /// tells this card when it is the highlighted one, so it paints its border.
  final bool focused;
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

    final radius = BorderRadius.circular(MediaBrowsingMetrics.cardRadius);
    // Not focusable on its own: the enclosing _EpisodeStrip is the single dpad
    // stop and passes `focused` down. The Material + InkWell keep the pointer
    // ripple; the border is painted by the same GradientBorderEffect a
    // DpadInkWell would apply.
    Widget body = Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongTap,
        borderRadius: radius,
        canRequestFocus: false,
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
    body = GradientBorderEffect(borderRadius: radius).build(
      context,
      DpadFocusState(focused: focused, pressed: false),
      body,
    );
    return SizedBox(width: width, child: body);
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

/// A locked-focus row that lives inside a [_RowScrollRegion]: the whole row is
/// one focus stop, left/right move an internal index, and up/down are routed
/// to the region (which focuses the adjacent row or hands off above).
// ignore: one_member_abstracts
abstract class _LockedRow {
  /// Take focus, park the internal cursor, and scroll self into view.
  void focusRow();
}

/// The wide series-detail vertical scroll region (episode strip + cast strip).
///
/// This is modelled on Plezy's TV detail: every row is a plain `Focus` widget
/// whose `onKeyEvent` handles left/right/up/down/select itself and *always*
/// consumes them, so no key ever reaches a traversal policy. dpad's directional
/// traversal + "scroll for more" retry were what left focus stuck a row behind
/// (needing 2-3 presses) and the strip clipped on tvOS.
///
///  * **Row hop** - a row's up/down calls `navigateVertical`, which focuses the
///    adjacent registered row directly (or `onExitTop` at the top, wired to the
///    Play button).
///  * **Reveal** - `reveal` scrolls a row fully into view, computed against
///    this region's own box + controller and run over two frames so a slower
///    tvOS layout pass cannot strand it.
class _RowScrollRegion extends StatefulWidget {
  const _RowScrollRegion({required this.child, this.onExitTop});

  final Widget child;

  /// Called when up is pressed on the top row - focus the Play button.
  final VoidCallback? onExitTop;

  /// Never returns null spuriously the way an inherited-widget lookup can when
  /// the scope is not wired yet (a tvOS-vs-desktop tree-timing difference that
  /// left `focusRow` and `reveal` no-ops).
  static _RowScrollRegionState? of(BuildContext context) =>
      context.findAncestorStateOfType<_RowScrollRegionState>();

  @override
  State<_RowScrollRegion> createState() => _RowScrollRegionState();
}

class _RowScrollRegionState extends State<_RowScrollRegion> {
  final ScrollController _controller = ScrollController();

  /// Rows in registration order, which is mount order, which is top-to-bottom
  /// (the episode strip builds before the cast strip).
  final List<_LockedRow> _rows = [];

  void registerRow(_LockedRow row) {
    if (!_rows.contains(row)) _rows.add(row);
  }

  void unregisterRow(_LockedRow row) => _rows.remove(row);

  /// Route an up/down press from [from]. Always "handled" from the caller's
  /// point of view - focus either lands on the adjacent row, hands off above
  /// the region, or (nothing below) stays put.
  void navigateVertical(_LockedRow from, {required bool up}) {
    final index = _rows.indexOf(from);
    if (index < 0) return;
    final targetIndex = index + (up ? -1 : 1);
    if (targetIndex < 0) {
      widget.onExitTop?.call();
      return;
    }
    if (targetIndex >= _rows.length) return;
    _rows[targetIndex].focusRow();
  }

  /// Scroll so [target]'s render box sits fully inside the viewport with [pad]
  /// px clear of whichever edge clipped it. No-op when it already is.
  ///
  /// Runs the correction next frame and again the frame after, so a relayout
  /// from the same focus change (or a slower tvOS pipeline) cannot strand the
  /// first pass. Geometry comes from this region's own render box and
  /// [_controller] - never an ambiguous ancestor-viewport lookup.
  void reveal(BuildContext target, {double pad = 16}) {
    void pass() {
      if (!mounted || !_controller.hasClients) return;
      final box = target.findRenderObject();
      final regionBox = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      if (regionBox is! RenderBox || !regionBox.hasSize) return;
      final position = _controller.position;
      final viewportHeight = position.viewportDimension;
      final topInRegion = box
          .localToGlobal(Offset.zero, ancestor: regionBox)
          .dy;
      final bottomInRegion = topInRegion + box.size.height;

      double delta;
      if (topInRegion < pad) {
        delta = topInRegion - pad; // clipped at top -> scroll up
      } else if (bottomInRegion > viewportHeight - pad) {
        delta = bottomInRegion - (viewportHeight - pad); // clipped at bottom
        final maxDelta = topInRegion - pad; // don't push our own top off
        if (delta > maxDelta) delta = maxDelta;
      } else {
        return; // already fully visible
      }
      if (delta.abs() < 0.5) return;
      final to = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((to - position.pixels).abs() < 0.5) return;
      unawaited(
        position.animateTo(
          to,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      pass();
      WidgetsBinding.instance.addPostFrameCallback((_) => pass());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(controller: _controller, child: widget.child);
  }
}

/// Tracks the D-pad SELECT key for a locked-focus row: a short press fires
/// `onTap` on key up, a hold past `_holdDuration` fires `onLongPress`.
/// Every select event is consumed so it never reaches a platform handler.
class _SelectHold {
  static const _holdDuration = Duration(milliseconds: 500);

  Timer? _timer;
  bool _down = false;
  bool _longFired = false;

  static final Set<LogicalKeyboardKey> _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  static bool isSelectKey(LogicalKeyboardKey key) => _selectKeys.contains(key);

  KeyEventResult handle(
    KeyEvent event, {
    required bool Function() isActive,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    if (onLongPress == null) {
      if (event is KeyDownEvent) onTap();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (!_down) {
        _down = true;
        _longFired = false;
        _timer?.cancel();
        _timer = Timer(_holdDuration, () {
          if (!isActive() || !_down) return;
          _longFired = true;
          onLongPress();
        });
      }
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    // KeyUpEvent: short press if the hold timer had not fired yet.
    _timer?.cancel();
    if (_down && !_longFired) onTap();
    _down = false;
    return KeyEventResult.handled;
  }

  void dispose() => _timer?.cancel();
}

/// Bridges the shared [CastStrip] to the series detail's [_RowScrollRegion]:
/// registers as a [_LockedRow] so the episode strip can hop down into it (and
/// it can hop back up), and routes the strip's reveal through the region.
class _SeriesCastRow extends StatefulWidget {
  const _SeriesCastRow({required this.members});

  final List<CastMember> members;

  @override
  State<_SeriesCastRow> createState() => _SeriesCastRowState();
}

class _SeriesCastRowState extends State<_SeriesCastRow> implements _LockedRow {
  final GlobalKey<CastStripState> _stripKey = GlobalKey<CastStripState>();
  _RowScrollRegionState? _region;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final region = _RowScrollRegion.of(context);
    if (region != _region) {
      _region?.unregisterRow(this);
      _region = region;
      _region?.registerRow(this);
    }
  }

  @override
  void dispose() {
    _region?.unregisterRow(this);
    super.dispose();
  }

  @override
  void focusRow() => _stripKey.currentState?.focusRow();

  @override
  Widget build(BuildContext context) {
    return CastStrip(
      key: _stripKey,
      members: widget.members,
      onNavigateUp: () => _region?.navigateVertical(this, up: true),
      // Consume down so focus never escapes below the cast row.
      onNavigateDown: () => _region?.navigateVertical(this, up: false),
      onReveal: (ctx) => _region?.reveal(ctx),
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
