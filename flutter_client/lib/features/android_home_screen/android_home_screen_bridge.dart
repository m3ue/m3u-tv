import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/features/carplay/car_catalog.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';

/// What a home screen card asked the app to open.
sealed class HomeScreenLaunch {
  const HomeScreenLaunch();
}

/// An "On Now" card: play the channel live.
class HomeScreenChannelLaunch extends HomeScreenLaunch {
  const HomeScreenChannelLaunch(this.channel, this.context);

  final Channel channel;

  /// The favorites, for next/previous channel.
  final ChannelContext context;
}

/// A Watch Next card: resume it, as its Continue Watching card does.
class HomeScreenProgressLaunch extends HomeScreenLaunch {
  const HomeScreenProgressLaunch(this.progress);

  final Progress progress;
}

/// Fills the Android TV home screen rows (`HomeScreenRows.kt`): Watch Next
/// from Continue Watching and Up Next, and the "On Now" channel from the
/// favorite live channels and what's airing on each.
///
/// The launcher shows only what was last written, so the rows are written
/// again when leaving the app, when Continue Watching changes while in it,
/// and from `HomeScreenRefreshWorker.kt` while the app is closed. That one
/// starts the app with no activity (as Android Auto does), so this runs
/// outside the widget tree and the worker asks for the rows ([collect]).
class AndroidHomeScreenBridge {
  AndroidHomeScreenBridge(
    this._catalog, {
    MethodChannel? channel,
    Future<bool>? supported,
    this._publishDelay = const Duration(seconds: 3),
    this._refreshWait = const Duration(seconds: 20),
    this._guideWait = const Duration(seconds: 8),
  }) : _channel = channel ?? const MethodChannel(channelName),
       _supportedOverride = supported;

  static const channelName = 'm3u_tv/home_screen';

  /// The running bridge (Android TV only), set by `main()`.
  static AndroidHomeScreenBridge? instance;

  /// Android asks apps to keep Watch Next short.
  static const maxWatchNext = 10;
  static const maxOnNow = 20;

  static const _guidePoll = Duration(milliseconds: 250);

  final CarCatalog _catalog;
  final MethodChannel _channel;
  final Future<bool>? _supportedOverride;
  final Duration _publishDelay;
  final Duration _refreshWait;
  final Duration _guideWait;

  late final Future<bool> _supported =
      _supportedOverride ?? resolveNativeTelevisionHint();
  AppLifecycleListener? _lifecycle;
  Timer? _publishDebounce;
  List<Progress>? _publishedProgress;
  bool _wasConfigured = false;
  void Function(HomeScreenLaunch launch)? _onLaunch;

  /// Set by the shell while it's up: opens what a card asked for. A card
  /// the app was started from is handed over as soon as this is set.
  set onLaunch(void Function(HomeScreenLaunch launch)? handler) {
    _onLaunch = handler;
    if (handler != null) unawaited(_takeLaunch());
  }

  void Function(HomeScreenLaunch launch)? get onLaunch => _onLaunch;

  void start() {
    _channel.setMethodCallHandler(handle);
    _catalog.appState
      ..addListener(_onAppStateChanged)
      ..viewSettingsService.addListener(_schedulePublish);
    // Leaving the app is when the launcher comes back into view.
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(publish()));
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _catalog.appState.removeListener(_onAppStateChanged);
    _catalog.appState.viewSettingsService.removeListener(_schedulePublish);
    _lifecycle?.dispose();
    _publishDebounce?.cancel();
  }

  @visibleForTesting
  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'collect':
        await _catalog.appState.ensureBooted();
        // Signed out, or nothing to show yet: leave the rows as they are.
        if (!_catalog.appState.isConfigured) return null;
        return collect(fresh: true);
      case 'launch':
        await _takeLaunch();
        return null;
    }
    throw MissingPluginException(call.method);
  }

  void _onAppStateChanged() {
    final appState = _catalog.appState;
    if (appState.isBootstrapping) return;
    final configured = appState.isConfigured;
    final signedOut = _wasConfigured && !configured;
    _wasConfigured = configured;
    if (signedOut ||
        (configured && !identical(appState.progressList, _publishedProgress))) {
      _schedulePublish();
    }
  }

  void _schedulePublish() {
    // Only while the app is in front: a background start has the worker
    // writing the rows itself.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _publishDebounce?.cancel();
    _publishDebounce = Timer(_publishDelay, () => unawaited(publish()));
  }

  /// Writes the rows from what the app holds now.
  @visibleForTesting
  Future<void> publish() async {
    _publishDebounce?.cancel();
    if (!await _supported) return;
    final appState = _catalog.appState;
    if (appState.isBootstrapping) return;
    _publishedProgress = appState.progressList;
    try {
      await _channel.invokeMethod<void>(
        'publish',
        await collect(fresh: false),
      );
    } on Object catch (error) {
      debugPrint('[HomeScreen] Publish failed: $error');
    }
  }

  /// The rows, as `HomeScreenRows.kt` writes them. [fresh] (the background
  /// refresh) re-reads Continue Watching from the server and waits a little
  /// for the favorites' guide first.
  @visibleForTesting
  Future<Map<String, Object?>> collect({required bool fresh}) async {
    final appState = _catalog.appState;
    final settings = appState.viewSettingsService;
    final watchNextEnabled = await settings.androidHomeWatchNext();
    final onNowEnabled = await settings.androidHomeOnNow();
    final configured = appState.isConfigured;

    var watchNext = const <Map<String, Object?>>[];
    if (configured && watchNextEnabled) {
      if (fresh) {
        await appState.refreshRecentlyWatched().timeout(
          _refreshWait,
          onTimeout: () {},
        );
      }
      watchNext = await _watchNextItems(appState.progressList);
    }

    var onNow = const <Map<String, Object?>>[];
    int? refreshAt;
    if (configured && onNowEnabled) {
      final favorites = await _catalog.favoriteChannels(maxOnNow);
      if (fresh) await _awaitGuide(favorites);
      final localeName = _catalog.l10n.localeName;
      // The widget localizations load these, and a background start builds
      // no widgets.
      await initializeDateFormatting(localeName);
      final time = DateFormat.jm(localeName);
      onNow = [
        for (final channel in favorites) _onNowItem(channel, time),
      ];
      final now = clock.now();
      for (final item in onNow) {
        final end = item['endMs'] as int?;
        if (end == null || end <= now.millisecondsSinceEpoch) continue;
        if (refreshAt == null || end < refreshAt) refreshAt = end;
      }
    }

    return {
      'watchNextEnabled': watchNextEnabled,
      'watchNext': watchNext,
      'onNowEnabled': onNowEnabled,
      'onNowTitle': _catalog.l10n.homeScreenOnNowChannel,
      'onNow': onNow,
      'refreshAtMs': ?refreshAt,
    };
  }

  /// Asks the server for the favorites' guide and waits, a while at most,
  /// until each has a programme airing.
  Future<void> _awaitGuide(List<Channel> channels) async {
    if (channels.isEmpty) return;
    final epg = _catalog.appState.epgService;
    _catalog.appState.ensureEpgForChannels(channels);
    final deadline = clock.now().add(_guideWait);
    while (channels.any((c) => epg.lookupForChannel(c) == null) &&
        clock.now().isBefore(deadline)) {
      await Future<void>.delayed(_guidePoll);
    }
  }

  Map<String, Object?> _onNowItem(Channel channel, DateFormat time) {
    final current = _catalog.appState.epgService.lookupForChannel(channel);
    final programme = current?.current;
    final l10n = _catalog.l10n;
    String? description;
    if (programme != null) {
      description = l10n.homeScreenOnNowDescription(
        channel.name,
        time.format(programme.start.toLocal()),
        time.format(programme.end.toLocal()),
      );
    }
    return {
      'key': 'live:${channel.id}',
      'title': programme?.title ?? channel.name,
      'description': ?description,
      'artworkUrl': ?(programme?.backdropUrl ?? programme?.iconUrl),
      'logoUrl': ?channel.logoUrl,
      'startMs': ?programme?.start.millisecondsSinceEpoch,
      'endMs': ?programme?.end.millisecondsSinceEpoch,
      'launch': {'kind': 'live', 'channelId': channel.id},
    };
  }

  Future<List<Map<String, Object?>>> _watchNextItems(
    List<Progress> progressList,
  ) async {
    final eligible = progressList
        .where((p) => isContinueWatchingEligible(p) && p.aioItemId == null)
        .take(maxWatchNext)
        .toList(growable: false);
    if (eligible.isEmpty) return const [];
    final repository = _catalog.appState.catalogRepository;
    final vodIds = {
      for (final p in eligible)
        if (p.contentType == ContentType.vod) p.streamId,
    };
    final seriesIds = {
      for (final p in eligible)
        if (p.contentType == ContentType.episode && p.seriesId != null)
          p.seriesId!,
    };
    final vodById = {
      if (vodIds.isNotEmpty)
        for (final item in await repository.activeItemsByIds<VodItem>(
          kind: kCatalogKindVod,
          ids: vodIds,
        ))
          item.id: item,
    };
    final seriesById = {
      if (seriesIds.isNotEmpty)
        for (final series in await repository.activeItemsByIds<Series>(
          kind: kCatalogKindSeries,
          ids: seriesIds,
        ))
          series.id: series,
    };
    return [
      for (final p in eligible)
        ?_watchNextItem(p, vodById[p.streamId], seriesById[p.seriesId]),
    ];
  }

  Map<String, Object?>? _watchNextItem(
    Progress progress,
    VodItem? vod,
    Series? series,
  ) {
    final duration = progress.durationSeconds;
    final hasPosition = !progress.upNext && progress.positionSeconds > 0;
    final launch = <String, Object?>{
      'kind': 'progress',
      'contentType': progress.contentType.name,
      'streamId': progress.streamId,
      'positionSeconds': progress.positionSeconds,
      'upNext': progress.upNext ? 1 : 0,
      'seriesId': ?progress.seriesId,
      'seasonNumber': ?progress.seasonNumber,
      'episodeNumber': ?progress.episodeNumber,
    };
    final common = <String, Object?>{
      'contentType': progress.contentType.name,
      'upNext': progress.upNext,
      // What makes a removed card come back: watching more of it.
      'engagement': progress.upNext ? 'next' : '${progress.positionSeconds}',
      if (hasPosition) 'positionMs': progress.positionSeconds * 1000,
      if (hasPosition && duration != null && duration > 0)
        'durationMs': duration * 1000,
      'description': ?progress.plot,
      'launch': launch,
    };
    if (progress.contentType == ContentType.vod) {
      final title = progress.title ?? vod?.name;
      if (title == null) return null;
      return {
        'key': 'vod:${progress.streamId}',
        'title': title,
        'imageUrl':
            ?(progress.backdropUrl ?? progress.thumbnailUrl ?? vod?.logoUrl),
        ...common,
      };
    }
    if (progress.contentType == ContentType.episode) {
      final title = progress.seriesName ?? series?.name ?? progress.title;
      if (title == null || progress.seriesId == null) return null;
      return {
        'key': 'episode:${progress.streamId}',
        'title': title,
        'episodeTitle': ?progress.episodeTitle,
        'seasonNumber': ?progress.seasonNumber,
        'episodeNumber': ?progress.episodeNumber,
        'imageUrl':
            ?(progress.thumbnailUrl ??
            progress.backdropUrl ??
            series?.backdropUrl ??
            series?.coverUrl),
        ...common,
      };
    }
    return null;
  }

  Future<void> _takeLaunch() async {
    if (_onLaunch == null) return;
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('takeLaunch');
    } on Object catch (error) {
      debugPrint('[HomeScreen] Launch lookup failed: $error');
      return;
    }
    if (raw == null) return;
    await _catalog.appState.ensureBooted();
    final launch = await resolveLaunch(raw);
    if (launch != null) _onLaunch?.call(launch);
  }

  /// What a card's launch extras ([raw]) point at, or null when it's gone.
  @visibleForTesting
  Future<HomeScreenLaunch?> resolveLaunch(Map<Object?, Object?> raw) async {
    int? number(String key) => (raw[key] as num?)?.toInt();
    switch (raw['kind']) {
      case 'live':
        final channelId = number('channelId');
        if (channelId == null) return null;
        final channel = await _catalog.channelById(channelId);
        if (channel == null) return null;
        final favorites = await _catalog.favoriteChannels(maxOnNow);
        return HomeScreenChannelLaunch(channel, ListChannelContext(favorites));
      case 'progress':
        final streamId = number('streamId');
        final contentType = ContentType.values.asNameMap()[raw['contentType']];
        if (streamId == null || contentType == null) return null;
        final appState = _catalog.appState;
        final known = appState.progressList
            .where(
              (p) => p.contentType == contentType && p.streamId == streamId,
            )
            .firstOrNull;
        return HomeScreenProgressLaunch(
          known ??
              Progress(
                viewerId: appState.activeViewer?.ulid ?? '',
                contentType: contentType,
                streamId: streamId,
                positionSeconds: number('positionSeconds') ?? 0,
                seriesId: number('seriesId'),
                seasonNumber: number('seasonNumber'),
                episodeNumber: number('episodeNumber'),
                upNext: number('upNext') == 1,
              ),
        );
    }
    return null;
  }
}
