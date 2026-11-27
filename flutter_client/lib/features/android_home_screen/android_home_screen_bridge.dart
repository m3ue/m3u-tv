import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/features/carplay/car_catalog.dart';
import 'package:m3u_tv/features/sports/sports_fixture_actions.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';
import 'package:m3u_tv/shared/channel_context.dart';
import 'package:m3u_tv/shared/channel_sort.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';

/// What a home screen card asked the app to open.
sealed class HomeScreenLaunch {
  const HomeScreenLaunch();
}

/// An "On Now" card: play the channel live.
class HomeScreenChannelLaunch extends HomeScreenLaunch {
  const HomeScreenChannelLaunch(this.channel, this.context);

  final Channel channel;

  /// The Live TV lineup, for next/previous channel.
  final ChannelContext context;
}

/// A Watch Next card: resume it, as its Continue Watching card does.
class HomeScreenProgressLaunch extends HomeScreenLaunch {
  const HomeScreenProgressLaunch(this.progress);

  final Progress progress;
}

/// Fills the Android TV home screen rows (`HomeScreenRows.kt`) with what the
/// app's own Home shows: Watch Next from Continue Watching and Up Next, the
/// "On Now" channel from the Live TV lineup (in its sort) and what's airing
/// on each channel, and the Sports channel from today's games.
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
  static const maxSports = 20;
  static const _sportsCacheAge = Duration(minutes: 5);

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
  ({DateTime at, List<(SportsFixture, Channel)> fixtures})? _sportsCache;

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
        if (!_catalog.appState.isConfigured) {
          debugPrint('[HomeScreen] Background refresh: not signed in');
          return null;
        }
        final payload = await collect(fresh: true);
        debugPrint('[HomeScreen] Background refresh: ${_describe(payload)}');
        return payload;
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
      final payload = await collect(fresh: false);
      debugPrint('[HomeScreen] Publishing ${_describe(payload)}');
      await _channel.invokeMethod<void>('publish', payload);
    } on Object catch (error) {
      debugPrint('[HomeScreen] Publish failed: $error');
    }
  }

  static String _describe(Map<String, Object?> payload) => [
    '${(payload['watchNext']! as List).length} Watch Next',
    for (final channel in payload['channels']! as List<Map<String, Object?>>)
      '${(channel['items']! as List).length} ${channel['id']}',
  ].join(', ');

  /// The rows, as `HomeScreenRows.kt` writes them. [fresh] (the background
  /// refresh) re-reads Continue Watching and today's games from the server
  /// and waits a little for the channels' guide first.
  @visibleForTesting
  Future<Map<String, Object?>> collect({required bool fresh}) async {
    final appState = _catalog.appState;
    final settings = appState.viewSettingsService;
    final watchNextEnabled = await settings.androidHomeWatchNext();
    final onNowEnabled = await settings.androidHomeOnNow();
    final sportsEnabled = await settings.androidHomeSports();
    final configured = appState.isConfigured;
    final l10n = _catalog.l10n;
    // The widget localizations load these, and a background start builds no
    // widgets.
    await initializeDateFormatting(l10n.localeName);
    final time = DateFormat.jm(l10n.localeName);
    final now = clock.now();
    int? refreshAt;
    void refreshBy(DateTime? at) {
      final ms = at?.millisecondsSinceEpoch;
      if (ms == null || ms <= now.millisecondsSinceEpoch) return;
      if (refreshAt == null || ms < refreshAt!) refreshAt = ms;
    }

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
    if (configured && onNowEnabled) {
      final (:channels, context: _) = await _liveLineup();
      if (fresh) await _awaitGuide(channels);
      onNow = [for (final channel in channels) _onNowItem(channel, time)];
      for (final channel in channels) {
        refreshBy(appState.epgService.lookupForChannel(channel)?.current.end);
      }
    }

    var sports = const <Map<String, Object?>>[];
    if (configured && sportsEnabled) {
      final fixtures = await _sportsFixtures(fresh: fresh);
      sports = [
        for (final (fixture, channel) in fixtures)
          _sportsItem(fixture, channel, time),
      ];
      for (final (fixture, _) in fixtures) {
        if (fixture.state == SportsFixtureState.scheduled) {
          refreshBy(fixture.start);
        }
      }
    }

    return {
      'watchNextEnabled': watchNextEnabled,
      'watchNext': watchNext,
      'channels': [
        {
          'id': 'on_now',
          'title': l10n.homeScreenOnNowChannel,
          'enabled': onNowEnabled,
          'items': onNow,
        },
        {
          'id': 'sports',
          'title': l10n.navSports,
          'enabled': sportsEnabled,
          'items': sports,
        },
      ],
      'refreshAtMs': ?refreshAt,
    };
  }

  /// What the app's Home Live TV row would list: the lineup in the Live TV
  /// screen's sort, favorites leading only when it leads with them, and the
  /// context next/previous channel moves through.
  Future<({List<Channel> channels, ChannelContext context})>
  _liveLineup() async {
    final appState = _catalog.appState;
    final settings = appState.viewSettingsService;
    // Fills the cache the synchronous order below reads; a background start
    // can get here before main() has.
    await Future.wait<Object?>([
      settings.rememberMediaSort(),
      settings.liveTvSortOption(),
      settings.liveTvFavoritesFirst(),
    ]);
    final order = settings.liveTvBrowseOrder;
    final query = LiveChannelQuery(
      sort: catalogSortForChannels(order.sort),
      favoritesFirst: order.favoritesFirst
          ? await appState.favoritesService.all()
          : const <int>{},
    );
    final repository = appState.catalogRepository;
    final channels = await query.page(repository, 0, maxOnNow);
    return (
      channels: channels,
      context: CatalogChannelContext(
        repository: repository,
        query: query,
        length: await query.count(repository),
      ),
    );
  }

  /// Asks the server for the channels' guide and waits, a while at most,
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
      'live': true,
      'artworkUrl': ?(programme?.backdropUrl ?? programme?.iconUrl),
      'cardLogos': [?channel.logoUrl],
      'logoUrl': ?channel.logoUrl,
      'startMs': ?programme?.start.millisecondsSinceEpoch,
      'endMs': ?programme?.end.millisecondsSinceEpoch,
      'launch': {'kind': 'live', 'channelId': channel.id},
    };
  }

  /// What the app's Home Sports row would list, each with the channel a
  /// card plays. Kept a few minutes in front: leaving the app shouldn't ask
  /// the server every time.
  Future<List<(SportsFixture, Channel)>> _sportsFixtures({
    required bool fresh,
  }) async {
    final cached = _sportsCache;
    if (!fresh &&
        cached != null &&
        clock.now().difference(cached.at) < _sportsCacheAge) {
      return cached.fixtures;
    }
    final appState = _catalog.appState;
    try {
      if (fresh) {
        await appState.ensureServerHandshake().timeout(
          _refreshWait,
          onTimeout: () => false,
        );
      }
      final capability = appState.sportsCapability;
      if (capability == null) return const [];
      final settings = appState.sportsSettings;
      await settings.ensureLoaded();
      final leagues = settings.enabledLeagues(capability.leagues);
      if (leagues.isEmpty) return const [];
      final (:from, :to) = homeSportsWindow(clock.now());
      final service = SportsService(appState.xtreamService);
      final fixtures = await service.fixtures(
        capability: capability,
        leagues: leagues,
        from: from,
        to: to,
      );
      final watchable = fixtures.where(isSportsFixtureWatchable).toList();
      if (watchable.isEmpty) return const [];
      final matches = await loadSportsChannelMatches(
        service: service,
        repository: appState.catalogRepository,
        capability: capability,
        leagues: leagues,
        from: from,
        to: to,
      );
      final shown = [
        for (final fixture in rankHomeSportsFixtures(
          watchable,
          matches,
          settings.followedTeamKeys,
        ).take(maxSports))
          (fixture, matches[fixture.key]!.first.channel),
      ];
      _sportsCache = (at: clock.now(), fixtures: shown);
      return shown;
    } on Object catch (error) {
      debugPrint('[HomeScreen] Sports games failed: $error');
      return cached?.fixtures ?? const [];
    }
  }

  Map<String, Object?> _sportsItem(
    SportsFixture fixture,
    Channel channel,
    DateFormat time,
  ) {
    final sides = fixture.displayOrder;
    final isLive = fixture.state == SportsFixtureState.live;
    final title =
        fixture.name ??
        (sides.isEmpty
            ? fixture.league.abbreviation
            : sides.map((side) => side.team.shortName).join(' - '));
    final scores = [for (final side in sides) side.score];
    final description = [
      fixture.league.abbreviation,
      if (isLive && scores.every((score) => score != null)) scores.join(' - '),
      if (isLive)
        fixture.statusDetail
      else
        time.format(fixture.start.toLocal()),
      channel.name,
    ].join(' · ');
    final logos = [for (final side in sides) ?side.team.logoUrl];
    return {
      'key': 'sports:${fixture.key}',
      'title': title,
      'description': description,
      'live': isLive,
      'cardLogos': logos.isNotEmpty ? logos : [?fixture.leagueLogoUrl],
      'logoUrl': ?channel.logoUrl,
      'startMs': fixture.start.millisecondsSinceEpoch,
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
        final (channels: _, :context) = await _liveLineup();
        return HomeScreenChannelLaunch(channel, context);
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
