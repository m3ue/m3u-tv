import 'dart:ui';

import 'package:m3u_tv/features/player/player_source_settings.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/editor_stream_session_gateway.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';

/// What the car screens (CarPlay, Android Auto) list and play, shared so
/// both match the phone: the same favorites, categories and stream request.
class CarCatalog {
  CarCatalog(this.appState);

  final AppStateController appState;

  /// Favorite live channels by name, at most [max].
  Future<List<Channel>> favoriteChannels(int max) async {
    if (!appState.isConfigured) return const [];
    final ids = await appState.favoritesService.all();
    if (ids.isEmpty) return const [];
    final channels = await appState.catalogRepository.activeItemsByIds<Channel>(
      kind: kCatalogKindLive,
      ids: ids,
    );
    final sorted = [...channels]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted.take(max).toList(growable: false);
  }

  List<Category> liveCategories(int max) =>
      appState.liveCategories.take(max).toList(growable: false);

  /// A category's first [max] channels, and the context next/previous
  /// channel moves through (the whole category).
  Future<({List<Channel> channels, ChannelContext context})> categoryChannels(
    String categoryId,
    int max,
  ) async {
    final repository = appState.catalogRepository;
    final query = LiveChannelQuery(categoryId: categoryId);
    final channels = await query.page(repository, 0, max);
    final context = CatalogChannelContext(
      repository: repository,
      query: query,
      length: await query.count(repository),
    );
    return (channels: channels, context: context);
  }

  Future<Channel?> channelById(int id) async {
    final channels = await appState.catalogRepository.activeItemsByIds<Channel>(
      kind: kCatalogKindLive,
      ids: {id},
    );
    return channels.firstOrNull;
  }

  /// Every live channel, for a context too small to skip through.
  ChannelContext allChannels() =>
      CatalogChannelContext(repository: appState.catalogRepository, length: 0);

  /// The title airing now on [channel].
  String? currentProgramme(Channel channel) =>
      appState.epgService.lookupForChannel(channel)?.current.title;

  /// The stream request the full-screen player makes for [channel]: proxy
  /// playback and the playback settings applied.
  PlaybackSource sourceFor(Channel channel) {
    final args = PlayerArgs.liveChannel(channel);
    return applyPlayerSourceSettings(
      args
          .copyWith(
            streamUrl: appState.applyProxyPlayback(
              args.streamUrl,
              type: 'live',
            ),
          )
          .toPlaybackSource(),
      appState.viewSettingsService,
    );
  }

  PlaybackStreamSessionGateway streamSessions() => EditorStreamSessionGateway(
    serverBase: () => appState.xtreamService.credentials?.server,
    stopPlayerStream: appState.stopPlayerStream,
  );

  /// The app's language, or English when the app has none of the system's.
  AppLocalizations get l10n {
    final languageCode =
        (appState.locale ?? PlatformDispatcher.instance.locale).languageCode;
    final supported = AppLocalizations.supportedLocales.any(
      (locale) => locale.languageCode == languageCode,
    );
    return lookupAppLocalizations(Locale(supported ? languageCode : 'en'));
  }
}
