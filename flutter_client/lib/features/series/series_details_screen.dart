import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/series_detail_widgets.dart';

/// Below this window width the series detail lays out for a phone: smaller
/// poster, full-width description, narrower episode cards. The episode-card
/// metrics live in `series_detail_widgets.dart` (kEpisodeCardWidth*).
const double _kSeriesCompactBreakpoint = 700;

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

  /// Owned here (rather than inside the shared body) so the AppBar back
  /// button - which lives outside the scrollable page entirely - can also
  /// snap it back to top on focus.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _playFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
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
      onBackButtonFocused: _scrollToTop,
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
            scrollController: _scrollController,
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
    this.scrollController,
  });

  final SeriesInfo info;
  final int? selectedSeason;
  final List<Progress> progressList;
  final Color? dominantColor;

  /// Passed straight to the shared body's colour-match reveal - true once the
  /// palette extraction has resolved, so the hero can fade the backdrop and
  /// its colour-match in together.
  final bool colorMatchReady;
  final bool canMarkWatched;
  final FocusNode playFocusNode;
  final ScrollController? scrollController;
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
    final season = _selectedSeasonObj;
    final seasonNumber = _resolvedSeason;
    final episodes = _episodes(seasonNumber);
    final backdrop = info.series.backdropUrl;
    // Season poster first, then the series poster, then the backdrop. Passed
    // as a chain so a season cover that 404s falls through at load time (not
    // just when it's null) rather than sticking on a placeholder.
    final posterChain = <String>[
      ?trimmedOrNull(season?.coverUrl),
      ?trimmedOrNull(info.series.coverUrl),
      ?trimmedOrNull(backdrop),
    ];
    final description = (season?.overview?.trim().isNotEmpty ?? false)
        ? season!.overview!.trim()
        : (info.series.plot ?? '');
    final target = _primaryTarget;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < _kSeriesCompactBreakpoint;
    // Keep the synopsis to a comfortable measure on TV/desktop (Nuvio-style);
    // full width on a phone.
    final plotMaxWidth = compact ? double.infinity : screenWidth * 0.6;

    return SeriesDetailBody(
      seriesName: info.series.name,
      posterChain: posterChain,
      backdropUrl: backdrop,
      seasons: info.seasons,
      selectedSeason: selectedSeason,
      resolvedSeason: seasonNumber,
      episodes: episodes,
      episodeCountFor: _episodeCountFor,
      fallbackPosterUrl: trimmedOrNull(info.series.coverUrl),
      meta: _seriesMetaInfo(context, target, description, plotMaxWidth),
      primaryActions: _primaryActions(context, target),
      richCast: info.series.richCast,
      castSemanticLabel: AppLocalizations.of(context).seriesCast,
      progressList: progressList,
      canMarkWatched: canMarkWatched,
      emptyEpisodesLabel: 'No episodes available',
      dominantColor: dominantColor,
      colorMatchReady: colorMatchReady,
      autofocusFirstEpisode: target == null,
      onSeasonSelected: onSeasonSelected,
      onSeasonResolved: onSeasonResolved,
      onEpisodeSelected: onEpisodeSelected,
      onMarkEpisode: onMarkEpisode,
      onMarkSeason: onMarkSeason,
      onExitTop: playFocusNode.requestFocus,
      scrollController: scrollController,
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

extension _IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
