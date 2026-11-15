import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:m3u_tv/features/carplay/car_catalog.dart';
import 'package:m3u_tv/features/carplay/carplay_audio_player.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';

/// Plays [channel] from a CarPlay list; [context] is the list it was picked
/// from, for next/previous channel.
typedef CarPlayChannelHandler =
    void Function(Channel channel, ChannelContext context);

/// The app's CarPlay screens (iPhone): Favorites and Live TV tabs over the
/// live catalog.
///
/// Runs outside the widget tree, started from `main()`: the car can open the
/// app with no phone window, and then no widget is ever built (Flutter only
/// builds for a view). For the same reason it boots the app state itself.
///
/// A channel picked in the car plays in the phone's full-screen player while
/// the phone's window is up (the app in the background included), and in an
/// audio-only player otherwise, which hands over to the full-screen player
/// once the phone's screen opens.
///
/// The root template is set once; afterwards each tab's list is updated in
/// place, so a refresh never throws the driver out of the category they're
/// browsing.
class CarPlayController {
  CarPlayController(this._appState, {CarPlayAudioPlayer? audioPlayer})
    : _catalog = CarCatalog(_appState) {
    _audioPlayer = audioPlayer ?? CarPlayAudioPlayer.forApp(_catalog);
  }

  /// The running controller (iPhone only), set by `main()`.
  static CarPlayController? instance;

  final AppStateController _appState;
  final FlutterCarplay _carplay = FlutterCarplay();

  final CarCatalog _catalog;
  late final CarPlayAudioPlayer _audioPlayer;

  static const _scenesChannel = MethodChannel('m3u_tv/app_scenes');

  CarPlayChannelHandler? _onPlayChannel;

  /// Set by the phone's shell while it's up: plays a channel picked in the
  /// car. Null with no phone window.
  CarPlayChannelHandler? get onPlayChannel => _onPlayChannel;

  /// Setting it while the audio-only player is going (the phone's screen
  /// has just opened) moves that channel to the full-screen player.
  set onPlayChannel(CarPlayChannelHandler? handler) {
    _onPlayChannel = handler;
    if (handler != null) unawaited(_handOverToPhone(handler));
  }

  static const _favoritesTemplateId = 'carplay-favorites';
  static const _liveTemplateId = 'carplay-live';

  // CarPlay lists are short by design; some cars cap them lower still (the
  // template reports its own limit).
  static const _fallbackMaxItems = 100;
  static const _refreshDelay = Duration(seconds: 1);

  bool _started = false;
  bool _rootSet = false;
  int _maxItems = _fallbackMaxItems;
  Timer? _refreshTimer;
  String? _favoritesSignature;
  String? _liveSignature;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _appState.addListener(_scheduleRefresh);
    _appState.favoritesService.addListener(_scheduleRefresh);
    _maxItems = await _maximumItemCount();
    await _refresh();
    await _appState.ensureBooted();
    await _refresh();
  }

  void dispose() {
    unawaited(_audioPlayer.stop());
    _refreshTimer?.cancel();
    _appState.removeListener(_scheduleRefresh);
    _appState.favoritesService.removeListener(_scheduleRefresh);
  }

  Future<int> _maximumItemCount() async {
    try {
      return await CPListTemplate.getMaximumItemCount() ?? _fallbackMaxItems;
    } on Object {
      return _fallbackMaxItems;
    }
  }

  // App state notifies for far more than the catalog; the signatures below
  // keep that from re-sending unchanged lists to the car.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDelay, () => unawaited(_refresh()));
  }

  AppLocalizations get _l10n => _catalog.l10n;

  Future<void> _refresh() async {
    final l10n = _l10n;
    final favorites = await _catalog.favoriteChannels(_maxItems);
    final categories = _catalog.liveCategories(_maxItems);

    final favoritesSignature = favorites
        .map((channel) => '${channel.id}:${channel.name}')
        .join('|');
    final liveSignature = [
      _appState.isConfigured,
      for (final category in categories) '${category.id}:${category.name}',
    ].join('|');

    final favoritesSections = [
      CPListSection(
        items: [
          for (final channel in favorites)
            _channelItem(
              channel,
              ListChannelContext(favorites),
            ),
        ],
      ),
    ];
    final liveSections = [
      CPListSection(
        items: [
          for (final category in categories) _categoryItem(category, l10n),
        ],
      ),
    ];

    if (!_rootSet) {
      _rootSet = true;
      _favoritesSignature = favoritesSignature;
      _liveSignature = liveSignature;
      await FlutterCarplay.setRootTemplate(
        rootTemplate: CPTabBarTemplate(
          templates: [
            CPListTemplate(
              id: _favoritesTemplateId,
              title: l10n.carPlayFavorites,
              tabTitle: l10n.carPlayFavorites,
              systemIcon: 'star.fill',
              sections: favoritesSections,
              emptyViewTitleVariants: [l10n.carPlayNoFavorites],
              emptyViewSubtitleVariants: [
                if (_appState.isConfigured)
                  l10n.carPlayNoFavoritesHint
                else
                  l10n.carPlaySignInHint,
              ],
            ),
            CPListTemplate(
              id: _liveTemplateId,
              title: l10n.navLiveTv,
              tabTitle: l10n.navLiveTv,
              systemIcon: 'tv',
              sections: liveSections,
              emptyViewTitleVariants: [l10n.liveTvNoChannels],
              emptyViewSubtitleVariants: [
                if (!_appState.isConfigured) l10n.carPlaySignInHint,
              ],
            ),
          ],
        ),
        animated: false,
      );
      return;
    }

    if (favoritesSignature != _favoritesSignature) {
      _favoritesSignature = favoritesSignature;
      await _carplay.updateListTemplateSections(
        elementId: _favoritesTemplateId,
        sections: favoritesSections,
      );
    }
    if (liveSignature != _liveSignature) {
      _liveSignature = liveSignature;
      await _carplay.updateListTemplateSections(
        elementId: _liveTemplateId,
        sections: liveSections,
      );
    }
  }

  Future<void> _play(Channel channel, ChannelContext context) async {
    final handler = _onPlayChannel;
    if (handler != null && await _phoneWindowConnected()) {
      await _audioPlayer.stop();
      handler(channel, context);
    } else {
      await _audioPlayer.play(channel, context);
    }
  }

  Future<void> _handOverToPhone(CarPlayChannelHandler handler) async {
    final channel = _audioPlayer.channel;
    if (channel == null) return;
    final context = _audioPlayer.context;
    // One player at a time: the stream is let go of before the full-screen
    // player asks for it again.
    await _audioPlayer.stop();
    if (_onPlayChannel != handler) return;
    handler(channel, context);
  }

  Future<bool> _phoneWindowConnected() async {
    try {
      return await _scenesChannel.invokeMethod<bool>('phoneWindowConnected') ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  CPListItem _categoryItem(Category category, AppLocalizations l10n) {
    return CPListItem(
      text: category.name,
      accessoryType: CPListItemAccessoryType.disclosureIndicator,
      onPress: (complete, self) async {
        try {
          final (:channels, :context) = await _catalog.categoryChannels(
            category.id,
            _maxItems,
          );
          await FlutterCarplay.push(
            template: CPListTemplate(
              title: category.name,
              sections: [
                CPListSection(
                  items: [
                    for (final channel in channels)
                      _channelItem(channel, context),
                  ],
                ),
              ],
              emptyViewTitleVariants: [l10n.liveTvNoChannels],
            ),
          );
        } finally {
          complete();
        }
      },
    );
  }

  CPListItem _channelItem(Channel channel, ChannelContext context) {
    return CPListItem(
      text: channel.name,
      detailText: _catalog.currentProgramme(channel),
      image: channel.logoUrl,
      onPress: (complete, self) async {
        try {
          await _play(channel, context);
          await FlutterCarplay.showSharedNowPlaying();
        } finally {
          complete();
        }
      },
    );
  }
}
