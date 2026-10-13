import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart'
    show HoverIntentCallback;

/// What the rich Home's spotlight hero is currently describing: the card
/// that last took focus in one of the rows below it.
sealed class HomeSpotlightTarget {
  const HomeSpotlightTarget();

  /// Stable identity, so re-focusing the same item (or a rebuilt card for
  /// it) doesn't restart the hero's transitions.
  String get key;
}

class VodSpotlightTarget extends HomeSpotlightTarget {
  const VodSpotlightTarget(this.item);

  final VodItem item;

  @override
  String get key => 'vod:${item.id}';
}

class SeriesSpotlightTarget extends HomeSpotlightTarget {
  const SeriesSpotlightTarget(this.series);

  final Series series;

  @override
  String get key => 'series:${series.id}';
}

class ChannelSpotlightTarget extends HomeSpotlightTarget {
  const ChannelSpotlightTarget(this.channel);

  final Channel channel;

  @override
  String get key => 'channel:${channel.id}';
}

class ProgressSpotlightTarget extends HomeSpotlightTarget {
  const ProgressSpotlightTarget(this.progress);

  final Progress progress;

  @override
  String get key =>
      'progress:${progress.contentType.name}:${progress.streamId}'
      ':${progress.upNext}';
}

/// A non-media card (DVR shortcut, "See all"): title and a line of text.
class StaticSpotlightTarget extends HomeSpotlightTarget {
  const StaticSpotlightTarget({
    required this.id,
    required this.title,
    this.description,
  });

  final String id;
  final String title;
  final String? description;

  @override
  String get key => 'static:$id';
}

/// Everything the hero renders for one target, already resolved and
/// localized. Built by [resolveHomeSpotlight].
@immutable
class HomeSpotlight {
  const HomeSpotlight({
    required this.key,
    required this.title,
    this.clearLogoUrl,
    this.backdropUrl,
    this.toneUrl,
    this.badge,
    this.kicker,
    this.kickerLogoUrl,
    this.secondaryTitle,
    this.chips = const [],
    this.progress,
    this.progressLabel,
    this.plot,
    this.footnote,
    this.endsAt,
    this.playLength,
  });

  final String key;
  final String title;
  final String? clearLogoUrl;

  /// Full-bleed landscape art behind the hero. Null shows the colour wash
  /// alone.
  final String? backdropUrl;

  /// Image the colour wash is extracted from: the backdrop when there is
  /// one, otherwise a poster/logo so art-less items still get a tint.
  final String? toneUrl;

  /// Small primary-coloured badge above the title ("LIVE", "Up next").
  final String? badge;

  /// Muted text beside [badge] (the channel name for live items).
  final String? kicker;
  final String? kickerLogoUrl;

  /// Line under the title: episode numbering and name.
  final String? secondaryTitle;
  final List<String> chips;

  /// 0-1 bar under the chips (live programme or watch progress).
  final double? progress;
  final String? progressLabel;
  final String? plot;

  /// Trailing muted line (the next programme for live items).
  final String? footnote;

  /// Fixed end time of what playing this would show (a live programme's
  /// end). Takes precedence over [playLength].
  final DateTime? endsAt;

  /// How long playing this would run from now (movie runtime, or what is
  /// left of a resume point); the hero clock adds it to the current time.
  final Duration? playLength;
}

/// Parses the runtime text the Xtream payloads carry ("01:40:09", "2h 50m",
/// "50m", "95 min", or bare minutes) into a [Duration]. Null when it can't
/// tell.
Duration? parseRuntimeText(String? text) {
  final value = text?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  if (value.contains(':')) {
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.any((part) => part == null)) return null;
    final numbers = parts.cast<int>();
    final duration = switch (numbers.length) {
      3 => Duration(
        hours: numbers[0],
        minutes: numbers[1],
        seconds: numbers[2],
      ),
      2 => Duration(hours: numbers[0], minutes: numbers[1]),
      _ => null,
    };
    return duration == null || duration <= Duration.zero ? null : duration;
  }
  final minutesOnly = int.tryParse(value);
  if (minutesOnly != null) {
    return minutesOnly > 0 ? Duration(minutes: minutesOnly) : null;
  }
  final hours = RegExp(r'(\d+)\s*h').firstMatch(value);
  final minutes = RegExp(r'(\d+)\s*m').firstMatch(value);
  if (hours == null && minutes == null) return null;
  final duration = Duration(
    hours: hours == null ? 0 : int.parse(hours.group(1)!),
    minutes: minutes == null ? 0 : int.parse(minutes.group(1)!),
  );
  return duration > Duration.zero ? duration : null;
}

/// Debounces focus changes into the hero. A D-pad held down steps through a
/// row every ~50-100ms; without the settle delay every step would decode a
/// backdrop and extract its palette. The first selection applies at once so
/// the hero is never blank on arrival.
///
/// Mouse hover (desktop) goes through [hover] instead: the hero follows the
/// pointer only once it rests on a card for [hoverDelay], and the caller's
/// `onRest` then moves D-pad focus there too, so switching between mouse and
/// remote/keyboard carries on from the same card. Every pointer move restarts
/// the wait, so sweeping across a row changes nothing until it stops.
///
/// A pending hover is cancelled by [cancelHover] (a key press: the keyboard
/// wins) or by leaving the card - not by [select]. Focus also changes for
/// reasons other than the user, such as the shell restoring content focus
/// when the pointer leaves the sidebar, and those must not discard a hover
/// that is about to land.
class HomeSpotlightController extends ValueNotifier<HomeSpotlightTarget?> {
  HomeSpotlightController({
    this.settleDelay = const Duration(milliseconds: 150),
    this.hoverDelay = const Duration(milliseconds: 500),
  }) : super(null);

  final Duration settleDelay;
  final Duration hoverDelay;
  Timer? _settle;
  Timer? _hover;
  String? _hoverKey;

  void select(HomeSpotlightTarget target) {
    _settle?.cancel();
    if (value == null || settleDelay == Duration.zero) {
      _apply(target);
      return;
    }
    _settle = Timer(settleDelay, () => _apply(target));
  }

  void hover(HomeSpotlightTarget target, {VoidCallback? onRest}) {
    cancelHover();
    _hoverKey = target.key;
    _hover = Timer(hoverDelay, () {
      _hoverKey = null;
      _apply(target);
      onRest?.call();
    });
  }

  /// The pointer left [target]'s card before its hover delay elapsed.
  void endHover(HomeSpotlightTarget target) {
    if (_hoverKey == target.key) cancelHover();
  }

  void cancelHover() {
    _hover?.cancel();
    _hover = null;
    _hoverKey = null;
  }

  /// Forgets the current item, so the next selection shows immediately
  /// (e.g. after the Home layout is switched and its rows remount).
  void reset() {
    _settle?.cancel();
    cancelHover();
    value = null;
  }

  /// Clears the current item if it is still [key] (e.g. its Continue
  /// Watching entry was just removed). Unlike [reset], pending selections
  /// are kept, so a card that re-announced itself in the gone item's place
  /// still lands.
  void forget(String key) {
    if (value?.key == key) value = null;
  }

  void _apply(HomeSpotlightTarget target) {
    if (value?.key == target.key) {
      // Same item, possibly a fresher object (e.g. reloaded catalog).
      if (!identical(value, target)) value = target;
      return;
    }
    value = target;
  }

  @override
  void dispose() {
    _settle?.cancel();
    _hover?.cancel();
    super.dispose();
  }
}

/// Wiring for a card's `onHoverChanged`: a rested hover shows the item and
/// moves D-pad focus to its card.
extension HomeSpotlightHover on HomeSpotlightController {
  HoverIntentCallback hoverHandler(HomeSpotlightTarget target) =>
      ({required hovered, required focusCard}) =>
          hovered ? hover(target, onRest: focusCard) : endHover(target);
}

/// Lazily fetched extras the list payloads don't carry: `get_vod_info` for
/// movies (backdrop, plot, runtime, clearlogo) and the catalog's [Series]
/// row for Continue Watching episodes. Small LRU caches with in-flight
/// dedupe, owned by the Home screen so revisits are instant.
class HomeSpotlightEnricher {
  HomeSpotlightEnricher({this.fetchVodInfo, this.lookupSeries});

  final Future<VodInfo?> Function(int vodId)? fetchVodInfo;
  final Future<Series?> Function(int seriesId)? lookupSeries;

  static const int _maxEntries = 64;
  final LinkedHashMap<int, VodInfo?> _vodInfo = LinkedHashMap();
  final LinkedHashMap<int, Series?> _series = LinkedHashMap();
  final Map<int, Future<void>> _vodPending = {};
  final Map<int, Future<void>> _seriesPending = {};

  VodInfo? vodInfo(int id) => _vodInfo[id];
  Series? series(int id) => _series[id];

  /// Whether [target] still has extras to fetch.
  bool needsFetch(HomeSpotlightTarget target) => switch (target) {
    VodSpotlightTarget(:final item) =>
      fetchVodInfo != null && !_vodInfo.containsKey(item.id),
    ProgressSpotlightTarget(:final progress) => switch (progress.contentType) {
      ContentType.vod =>
        fetchVodInfo != null && !_vodInfo.containsKey(progress.streamId),
      ContentType.episode =>
        lookupSeries != null &&
            progress.seriesId != null &&
            !_series.containsKey(progress.seriesId),
      _ => false,
    },
    _ => false,
  };

  Future<void> fetch(HomeSpotlightTarget target) async {
    switch (target) {
      case VodSpotlightTarget(:final item):
        await _fetchVod(item.id);
      case ProgressSpotlightTarget(:final progress)
          when progress.contentType == ContentType.vod:
        await _fetchVod(progress.streamId);
      case ProgressSpotlightTarget(:final progress)
          when progress.contentType == ContentType.episode &&
              progress.seriesId != null:
        await _fetchSeries(progress.seriesId!);
      default:
        return;
    }
  }

  Future<void> _fetchVod(int id) {
    final fetch = fetchVodInfo;
    if (fetch == null || _vodInfo.containsKey(id)) return Future.value();
    return _vodPending[id] ??= () async {
      VodInfo? info;
      try {
        info = await fetch(id);
      } on Object catch (_) {
        // Remembered as null so a failing title isn't re-requested on every
        // focus; the hero just keeps the list-level data.
      }
      _remember(_vodInfo, id, info);
      // remove() hands back the stored Future; nothing awaits it here.
      // ignore: unawaited_futures
      _vodPending.remove(id);
    }();
  }

  Future<void> _fetchSeries(int id) {
    final lookup = lookupSeries;
    if (lookup == null || _series.containsKey(id)) return Future.value();
    return _seriesPending[id] ??= () async {
      Series? series;
      try {
        series = await lookup(id);
      } on Object catch (_) {}
      _remember(_series, id, series);
      // ignore: unawaited_futures
      _seriesPending.remove(id);
    }();
  }

  void _remember<T>(LinkedHashMap<int, T?> cache, int id, T? value) {
    cache.remove(id);
    if (cache.length >= _maxEntries) cache.remove(cache.keys.first);
    cache[id] = value;
  }
}

String? _notEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String _ratingLabel(double rating) =>
    '★ ${rating == rating.roundToDouble() ? rating.toStringAsFixed(0) : rating.toStringAsFixed(1)}';

/// Formatting hooks [resolveHomeSpotlight] needs from the widget layer, kept
/// as plain functions so the resolver stays testable without a context.
class HomeSpotlightFormat {
  const HomeSpotlightFormat({
    required this.l10n,
    required this.timeOfDay,
    required this.duration,
  });

  final AppLocalizations l10n;
  final String Function(DateTime time) timeOfDay;
  final String Function(Duration duration) duration;
}

HomeSpotlight resolveHomeSpotlight(
  HomeSpotlightTarget target, {
  required HomeSpotlightFormat format,
  required HomeSpotlightEnricher enricher,
  EpgCurrentNext? Function(Channel channel)? epgLookup,
  required DateTime now,
}) {
  switch (target) {
    case VodSpotlightTarget(:final item):
      final info = enricher.vodInfo(item.id);
      final backdrop = _notEmpty(info?.backdropUrl);
      final rating = info?.rating ?? item.rating;
      return HomeSpotlight(
        key: target.key,
        title: _notEmpty(info?.name) ?? item.name,
        clearLogoUrl: _notEmpty(info?.clearLogoUrl),
        backdropUrl: backdrop,
        toneUrl: backdrop ?? _notEmpty(info?.coverUrl) ?? item.logoUrl,
        chips: [
          ?(_notEmpty(info?.year) ?? item.year),
          ?_notEmpty(info?.contentRating),
          ?_notEmpty(info?.genre),
          ?_notEmpty(info?.duration),
          if (rating != null && rating > 0) _ratingLabel(rating),
        ],
        plot: _notEmpty(info?.plot),
        playLength: parseRuntimeText(info?.duration),
      );

    case SeriesSpotlightTarget(:final series):
      final backdrop = _notEmpty(series.backdropUrl);
      final rating = series.rating;
      return HomeSpotlight(
        key: target.key,
        title: series.name,
        clearLogoUrl: _notEmpty(series.clearLogoUrl),
        backdropUrl: backdrop,
        toneUrl: backdrop ?? series.coverUrl,
        chips: [
          ?series.year,
          ?_notEmpty(series.contentRating),
          if (rating != null && rating > 0) _ratingLabel(rating),
        ],
        plot: _notEmpty(series.plot),
      );

    case ChannelSpotlightTarget(:final channel):
      return _channelSpotlight(
        target,
        channel,
        epgLookup?.call(channel),
        format,
        now,
      );

    case ProgressSpotlightTarget(:final progress):
      return _progressSpotlight(target, progress, enricher, format);

    case StaticSpotlightTarget(:final title, :final description):
      return HomeSpotlight(key: target.key, title: title, plot: description);
  }
}

HomeSpotlight _channelSpotlight(
  ChannelSpotlightTarget target,
  Channel channel,
  EpgCurrentNext? epg,
  HomeSpotlightFormat format,
  DateTime now,
) {
  final l = format.l10n;
  final program = epg?.current;
  final hasInfo = program != null && !program.isPlaceholder;
  if (!hasInfo) {
    return HomeSpotlight(
      key: target.key,
      title: channel.name,
      toneUrl: channel.logoUrl,
      badge: l.epgLiveBadge,
      kickerLogoUrl: channel.logoUrl,
      plot: l.epgNoData,
    );
  }
  final backdrop = _notEmpty(program.backdropUrl) ?? _notEmpty(program.iconUrl);
  final remaining = program.end.difference(now);
  final next = epg!.next;
  final episodeLabel = _episodeLabel(l, program);
  final subtitle = _notEmpty(program.subtitle);
  final secondary = [
    ?episodeLabel,
    if (subtitle != null && subtitle != program.title.trim()) subtitle,
  ].join(' - ');
  return HomeSpotlight(
    key: target.key,
    title: _notEmpty(program.title) ?? channel.name,
    backdropUrl: backdrop,
    toneUrl: backdrop ?? _notEmpty(program.posterUrl) ?? channel.logoUrl,
    badge: l.epgLiveBadge,
    kicker: channel.name,
    kickerLogoUrl: channel.logoUrl,
    secondaryTitle: secondary.isEmpty ? null : secondary,
    chips: [
      if (program.isNew) l.epgBadgeNew,
      if (program.isPremiere) l.epgBadgePremiere,
      ?_notEmpty(program.category),
      if (program.year != null) '${program.year}',
      ?_notEmpty(program.rating),
    ],
    progress: epg.progress,
    progressLabel:
        '${format.timeOfDay(program.start)} - ${format.timeOfDay(program.end)}'
        '${remaining.isNegative ? '' : '  ·  ${l.epgTimeLeft(format.duration(remaining))}'}',
    plot: _notEmpty(program.description),
    footnote: next == null || next.isPlaceholder
        ? null
        : '${l.homeUpNext}: ${format.timeOfDay(next.start)}  '
              '${next.displayTitle}',
    endsAt: program.end,
  );
}

HomeSpotlight _progressSpotlight(
  ProgressSpotlightTarget target,
  Progress progress,
  HomeSpotlightEnricher enricher,
  HomeSpotlightFormat format,
) {
  final l = format.l10n;
  final fraction =
      !progress.upNext &&
          progress.durationSeconds != null &&
          progress.durationSeconds! > 0
      ? (progress.positionSeconds / progress.durationSeconds!).clamp(0.0, 1.0)
      : null;
  final timeLeft = fraction == null ? null : _timeLeft(l, progress);
  final totalSeconds = progress.durationSeconds;
  final playLength = totalSeconds != null && totalSeconds > 0
      ? Duration(
          seconds: progress.upNext
              ? totalSeconds
              : (totalSeconds - progress.positionSeconds).clamp(
                  0,
                  totalSeconds,
                ),
        )
      : parseRuntimeText(progress.runtime);
  final runtime = _notEmpty(progress.runtime);
  final genre = _notEmpty(progress.genre);
  final rating = _notEmpty(progress.rating);

  if (progress.contentType == ContentType.episode) {
    final series = progress.seriesId == null
        ? null
        : enricher.series(progress.seriesId!);
    final backdrop =
        _notEmpty(progress.backdropUrl) ?? _notEmpty(series?.backdropUrl);
    final season = progress.seasonNumber;
    final episode = progress.episodeNumber;
    final numbering = season != null && episode != null
        ? l.epgSeasonEpisode(season, episode)
        : season != null
        ? l.epgSeasonNumber(season)
        : null;
    final secondary = [?numbering, ?_notEmpty(progress.episodeTitle)].join(
      ' - ',
    );
    return HomeSpotlight(
      key: target.key,
      title:
          _notEmpty(progress.seriesName) ??
          series?.name ??
          _notEmpty(progress.title) ??
          '',
      clearLogoUrl: _notEmpty(series?.clearLogoUrl),
      backdropUrl: backdrop,
      toneUrl: backdrop ?? _notEmpty(progress.thumbnailUrl) ?? series?.coverUrl,
      badge: progress.upNext ? l.homeUpNext : null,
      secondaryTitle: secondary.isEmpty ? null : secondary,
      chips: [
        ?series?.year,
        ?_notEmpty(series?.contentRating),
        ?genre,
        ?runtime,
        if (rating != null) '★ $rating',
      ],
      progress: fraction,
      progressLabel: timeLeft,
      plot: _notEmpty(progress.plot) ?? _notEmpty(series?.plot),
      playLength: playLength,
    );
  }

  final info = enricher.vodInfo(progress.streamId);
  final backdrop =
      _notEmpty(progress.backdropUrl) ?? _notEmpty(info?.backdropUrl);
  final infoRating = info?.rating;
  return HomeSpotlight(
    key: target.key,
    title: _notEmpty(progress.title) ?? _notEmpty(info?.name) ?? '',
    clearLogoUrl: _notEmpty(info?.clearLogoUrl),
    backdropUrl: backdrop,
    toneUrl:
        backdrop ??
        _notEmpty(progress.thumbnailUrl) ??
        _notEmpty(info?.coverUrl),
    chips: [
      ?(_notEmpty(info?.year) ?? _notEmpty(progress.year)),
      ?_notEmpty(info?.contentRating),
      ?(genre ?? _notEmpty(info?.genre)),
      ?(runtime ?? _notEmpty(info?.duration)),
      if (rating != null)
        '★ $rating'
      else if (infoRating != null && infoRating > 0)
        _ratingLabel(infoRating),
    ],
    progress: fraction,
    progressLabel: timeLeft,
    plot: _notEmpty(progress.plot) ?? _notEmpty(info?.plot),
    playLength: playLength ?? parseRuntimeText(info?.duration),
  );
}

String? _episodeLabel(AppLocalizations l, EpgProgram program) {
  final season = program.season;
  final episode = program.episode;
  if (season != null && episode != null) {
    return l.epgSeasonEpisode(season, episode);
  }
  if (episode != null) return l.epgEpisodeNumber(episode);
  if (season != null) return l.epgSeasonNumber(season);
  return null;
}

String? _timeLeft(AppLocalizations l, Progress progress) {
  final duration = progress.durationSeconds;
  if (duration == null || duration <= 0) return null;
  final remainingSeconds = (duration - progress.positionSeconds).clamp(
    0,
    duration,
  );
  final totalMinutes = (remainingSeconds / 60).ceil().clamp(1, duration);
  if (totalMinutes < 60) return l.vodTimeLeftMinutes(totalMinutes);
  return l.vodTimeLeftHoursMinutes(totalMinutes ~/ 60, totalMinutes % 60);
}
