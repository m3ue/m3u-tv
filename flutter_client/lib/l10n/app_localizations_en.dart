// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navLiveTv => 'Live TV';

  @override
  String get navVod => 'Movies';

  @override
  String get navSeries => 'Series';

  @override
  String get navDvr => 'DVR';

  @override
  String get navRequests => 'Requests';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navSettings => 'Settings';

  @override
  String get navMore => 'More';

  @override
  String get appBackToExit => 'Press back again to exit';

  @override
  String appRecordingScheduled(String title) {
    return 'Recording scheduled: $title';
  }

  @override
  String appRecordingFailed(String error) {
    return 'Could not schedule recording: $error';
  }

  @override
  String get appNotConfigured => 'Please connect to your service in Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get unknown => 'Unknown';

  @override
  String get admin => 'Admin';

  @override
  String get liveTvSearchHint => 'Search live TV...';

  @override
  String get liveTvNoChannels => 'No channels available';

  @override
  String get liveTvAllChannels => 'All Channels';

  @override
  String get liveTvFavorites => '★ Favorites';

  @override
  String get liveTvNoProgram => 'No program info';

  @override
  String get liveTvNext => 'NEXT';

  @override
  String get liveTvRecord => 'Record';

  @override
  String get liveTvRecording => 'Recording';

  @override
  String get liveTvFavorite => 'Favorite';

  @override
  String get liveTvRemoveFavorite => 'Remove favorite';

  @override
  String get playerGoBack => 'Go back';

  @override
  String get playerResumeWatching => 'Resume Watching';

  @override
  String get playerContinue => 'Continue';

  @override
  String playerFromTime(String time) {
    return 'From $time';
  }

  @override
  String get playerStartFromBeginning => 'Start from Beginning';

  @override
  String get playerResume => 'Resume';

  @override
  String get searchHint => 'Search live TV, movies, and series...';

  @override
  String get searchSectionLiveTv => 'Live TV';

  @override
  String get searchSectionMovies => 'Movies';

  @override
  String get searchSectionSeries => 'Series';

  @override
  String get vodSearchHint => 'Search movies...';

  @override
  String get seriesSearchHint => 'Search series...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsIntegrations => 'Integrations';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System language';

  @override
  String get settingsLangEnglish => 'English';

  @override
  String get settingsLangGerman => 'German';

  @override
  String get settingsLangSpanish => 'Spanish';

  @override
  String get settingsLangFrench => 'French';

  @override
  String get settingsLangChinese => 'Chinese (Simplified)';

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsStatusConnected => 'Connected';

  @override
  String get settingsStatusUnavailable => 'Unavailable';

  @override
  String get settingsStatusLabel => 'Status';

  @override
  String get settingsSourceLabel => 'Source';

  @override
  String get settingsServerTimezone => 'Server Timezone';

  @override
  String get settingsLastError => 'Last error';

  @override
  String get settingsRetryConnection => 'Retry connection';

  @override
  String get settingsEditServer => 'Edit server settings';

  @override
  String get settingsActiveViewer => 'Active Viewer';

  @override
  String get settingsClearCacheTitle => 'Clear Cache & Refresh?';

  @override
  String get settingsClearCacheBody =>
      'All cached content will be cleared and reloaded from your source.';

  @override
  String get settingsClearCacheConfirm => 'Clear & Refresh';

  @override
  String get settingsCacheCleared =>
      'Cache cleared — content is refreshing in the background.';

  @override
  String get settingsContentCache => 'Content Cache';

  @override
  String get settingsCacheSubtitle =>
      'Cached content loads instantly. Data refreshes automatically in the background.';

  @override
  String get settingsEpgRefreshInterval => 'EPG refresh interval';

  @override
  String settingsEpgDurationMinutes(int count) {
    return '$count min';
  }

  @override
  String get settingsEpgDurationHour => '1 hour';

  @override
  String settingsEpgDurationHours(int count) {
    return '$count hours';
  }

  @override
  String get settingsManageViewers => 'Manage Viewers';

  @override
  String get settingsAddViewer => 'Add New Viewer';

  @override
  String get settingsSwitchViewer => 'Switch Viewer';

  @override
  String get settingsViewerNameLabel => 'Viewer name';

  @override
  String get settingsCreate => 'Create';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsProxyPlayback => 'Proxy Playback';

  @override
  String get settingsProxyPlaybackSubtitle =>
      'Stream through the m3u-editor proxy with an optional transcoding profile for this device.';

  @override
  String get settingsProxyUse => 'Use proxy';

  @override
  String get settingsProxyForced =>
      'The proxy is enabled at the playlist level and cannot be turned off.';

  @override
  String get settingsProxyLiveProfile => 'Live transcoding profile';

  @override
  String get settingsProxyVodProfile => 'VOD & Series transcoding profile';

  @override
  String get settingsProxyProfileDefault => 'Default';

  @override
  String get settingsProxyProfileDirect => 'Direct (no transcoding)';

  @override
  String get settingsProxyNoProfiles =>
      'No transcoding profiles available — streams use the direct proxy.';

  @override
  String get settingsDisconnectTitle => 'Disconnect?';

  @override
  String get settingsDisconnectBody =>
      'You will be signed out and will need to re-enter your credentials to reconnect.';

  @override
  String get settingsDisconnectConfirm => 'Disconnect';

  @override
  String get homeContinueWatching => 'Continue Watching';

  @override
  String get homeNoContinueWatching => 'No Continue Watching available';

  @override
  String get homeNoLiveTv => 'No Live TV available';

  @override
  String get homeFavoriteChannels => 'Favorite Channels';

  @override
  String get homeNoFavoriteChannels => 'No favorite channels available';

  @override
  String get homeNoMovies => 'No Movies available';

  @override
  String get homeLiveChannel => 'Live channel';

  @override
  String get homeMovie => 'Movie';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsTabNotifications => 'Notifications';

  @override
  String get notificationsTabChannelSettings => 'Channel Settings';

  @override
  String get notificationsMarkAllRead => 'Mark all read';

  @override
  String get notificationsEmpty => 'No notifications yet';

  @override
  String get notificationsEmptyFiltered =>
      'No notifications for your subscribed channels';

  @override
  String get notificationsChannelSubscriptions => 'Channel subscriptions';

  @override
  String get notificationsChannelSubtitle =>
      'Select which channels you want to receive. Leave all unselected to receive everything.';

  @override
  String get notificationsAllChannels => 'All channels';

  @override
  String get notificationsNoChannels =>
      'No channels seen yet — they appear here as notifications arrive.';

  @override
  String get notificationsJustNow => 'just now';

  @override
  String notificationsMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String notificationsHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String notificationsDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String notificationsReceivedAt(String time) {
    return 'Received $time';
  }

  @override
  String notificationsReadAt(String time) {
    return 'Read $time';
  }

  @override
  String get homeNoSeries => 'No Series available';

  @override
  String homeSeason(int number) {
    return 'Season $number';
  }

  @override
  String get traktWatchHistory => 'Watch History';

  @override
  String get traktWatchHistorySubtitle =>
      'Sync your watch history with Trakt to track progress across apps and services.';

  @override
  String get traktNotConfigured =>
      'Trakt client credentials are not configured.';

  @override
  String get traktNotConfiguredHint =>
      'Register an app at trakt.tv/oauth/applications and set the client ID and secret via --dart-define at build time.';

  @override
  String get traktConnectPrompt =>
      'Connect your Trakt account to automatically track what you watch.';

  @override
  String get traktConnectButton => 'Connect with Trakt';

  @override
  String get traktScanQr => 'Scan to open on your phone';

  @override
  String get traktOpenBrowser => 'Open in browser';

  @override
  String get traktPendingGoTo => 'On your phone or computer, go to:';

  @override
  String get traktPendingEnterCode => 'Then enter this code:';

  @override
  String get traktPendingWaiting => 'Waiting for authorization…';

  @override
  String get traktConnected => 'Connected to Trakt';

  @override
  String get traktDisconnectButton => 'Disconnect Trakt';

  @override
  String get vodAllMovies => 'All Movies';

  @override
  String get seriesAllSeries => 'All Series';

  @override
  String homeConnectedSource(String label) {
    return 'Connected source: $label';
  }

  @override
  String get searchTypeToSearch => 'Type to search';

  @override
  String get vodPlayMovie => 'Play movie';

  @override
  String get vodContinueMovie => 'Continue movie';

  @override
  String get navAioStreams => 'AIOStreams';

  @override
  String get aiostreamsGetStreams => 'Get Streams';

  @override
  String get aiostreamsLoadingStreams => 'Loading streams…';

  @override
  String get aiostreamsNoStreams => 'No streams found';

  @override
  String get aiostreamsSelectStream => 'Select a stream';

  @override
  String get aiostreamsLoadMore => 'Load more';

  @override
  String get aiostreamsSearchHint => 'Search movies & series…';

  @override
  String get aiostrreamsCatalogEmpty => 'Nothing here yet';

  @override
  String get aiostreamsToggleFavorite => 'Favorite';

  @override
  String get aiostreamsMyFavorites => 'My Favorites';

  @override
  String get aiostreamsContinueWatching => 'Continue Watching';

  @override
  String get aiostreamsSearch => 'Search AIOStreams';

  @override
  String get aiostreamsSearchResults => 'Search Results';

  @override
  String get aiostreamsNoResults => 'No results found';

  @override
  String get aiostreamsSearchAll => 'All';

  @override
  String get requestsTabSearch => 'Search';

  @override
  String get requestsTabMyRequests => 'My Requests';

  @override
  String get requestsSearchHint => 'Search movies & shows…';

  @override
  String get requestsNoResults => 'No results found';

  @override
  String get requestsAlreadyAvailable => 'Already available';

  @override
  String get requestsAlreadyRequested => 'Already requested';

  @override
  String requestsSubmitted(String title) {
    return '\"$title\" was requested';
  }

  @override
  String requestsSubmittedPendingApproval(String title) {
    return '\"$title\" was sent for approval';
  }

  @override
  String requestsSubmitFailed(String title, String error) {
    return 'Could not request \"$title\": $error';
  }

  @override
  String get requestsMyRequestsEmpty => 'You haven\'t requested anything yet';

  @override
  String get requestsDismiss => 'Dismiss';

  @override
  String requestsDismissFailed(String error) {
    return 'Could not dismiss request: $error';
  }

  @override
  String get requestsStatusPendingApproval => 'Pending Approval';

  @override
  String get requestsStatusApproved => 'Approved';

  @override
  String get requestsStatusRejected => 'Rejected';

  @override
  String get requestsStatusCompleted => 'Completed';

  @override
  String get requestsStatusUnknown => 'Unknown';
}
