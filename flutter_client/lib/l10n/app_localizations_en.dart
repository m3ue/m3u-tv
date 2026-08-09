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
  String get notificationsDesktopOpen => 'Open';

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
  String get catchupBadgeAvailable => 'Catchup available';

  @override
  String catchupBadgeAvailableDays(int days) {
    return 'Catchup available: ${days}d';
  }

  @override
  String get catchupProgramReplayable => 'Catchup replay available';

  @override
  String get epgPreviousDay => 'Previous day';

  @override
  String get epgNow => 'Now';

  @override
  String get epgNextDay => 'Next day';

  @override
  String get epgChannels => 'CHANNELS';

  @override
  String get epgNoData => 'No EPG data';

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
  String get playerSkipPreviousTooltip => 'Previous channel';

  @override
  String get playerSkipNextTooltip => 'Next channel';

  @override
  String get playerNowPlayingMovie => 'Movie';

  @override
  String get playerNowPlayingSeries => 'Series';

  @override
  String playerNowPlayingSeasonEpisode(int season, int episode) {
    return 'S$season · E$episode';
  }

  @override
  String get playerCommercialSkipped => 'Skipped commercial';

  @override
  String get playerSkipCommercial => 'Skip commercial';

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
  String get settingsDvr => 'DVR';

  @override
  String get settingsDvrSubtitle => 'Settings for recorded content playback.';

  @override
  String get settingsComskip => 'Commercial Skipping';

  @override
  String get settingsComskipSubtitle =>
      'Controls how the player reacts to commercial breaks detected in DVR recordings.';

  @override
  String get settingsComskipAutoSkip => 'Auto-skip commercials';

  @override
  String get settingsDisconnectTitle => 'Disconnect?';

  @override
  String get settingsDisconnectBody =>
      'You will be signed out and will need to re-enter your credentials to reconnect.';

  @override
  String get settingsDisconnectConfirm => 'Disconnect';

  @override
  String get settingsApp => 'App';

  @override
  String get settingsAppVersion => 'Version';

  @override
  String get settingsAppUpdateStatus => 'Update';

  @override
  String get settingsAppVersionChecking => 'Checking for updates…';

  @override
  String get settingsAppUpToDate => 'Up to date';

  @override
  String settingsAppUpdateAvailable(String version) {
    return 'Update available: $version';
  }

  @override
  String get settingsAppViewRelease => 'View release';

  @override
  String get settingsAppScanQr => 'Scan to open on your phone';

  @override
  String get settingsFillAllFields => 'Please fill in all fields';

  @override
  String get settingsConnectionSettings => 'Connection Settings';

  @override
  String get settingsConnectionSettingsSubtitle =>
      'Enter your Xtream codes details';

  @override
  String get settingsServerUrl => 'Server URL';

  @override
  String get settingsUsername => 'Username';

  @override
  String get settingsPassword => 'Password';

  @override
  String get settingsConnect => 'Connect';

  @override
  String get settingsPairWithCode => 'Pair with code';

  @override
  String get settingsTabPair => 'Pair';

  @override
  String get settingsTabSignIn => 'Sign In';

  @override
  String get settingsPairTabSubtitle =>
      'Enter your server address, then pair this TV using a code.';

  @override
  String get pairingEnterServerFirst => 'Enter your server URL first';

  @override
  String get pairingErrorGeneric =>
      'Pairing failed or the code expired. Please try again.';

  @override
  String get pairingScanQr => 'Scan to open the pairing page on your phone';

  @override
  String get pairingOpenBrowser => 'Open in browser';

  @override
  String get pairingPendingGoTo => 'On your phone or computer, go to:';

  @override
  String get pairingPendingEnterCode => 'Then enter this code:';

  @override
  String get pairingPendingWaiting => 'Waiting for approval…';

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
  String get requestsTitle => 'Requests';

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
  String get requestsRequestButton => 'Request';

  @override
  String get requestsSeasonsHeading => 'Seasons';

  @override
  String get requestsSeasonSpecials => 'Specials';

  @override
  String get requestsSelectAllSeasons => 'Select All';

  @override
  String get requestsClearSeasons => 'Clear';

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

  @override
  String get dvrRecordingsTitle => 'DVR Recordings';

  @override
  String get dvrRecordingsSubtitle =>
      'Completed recordings and currently recording programmes';

  @override
  String get dvrNoRecordings => 'No DVR recordings available';

  @override
  String get dvrNotConfigured => 'Please connect to your service in Settings';

  @override
  String get dvrCancel => 'Cancel';

  @override
  String get dvrDelete => 'Delete';

  @override
  String dvrStopTitle(String title) {
    return 'Stop recording — $title';
  }

  @override
  String get dvrStopMessage =>
      'Keep it in your recordings list, or delete it now?';

  @override
  String get dvrStopKeep => 'Keep recording';

  @override
  String get dvrStopDelete => 'Delete recording';

  @override
  String get dvrStopBack => 'Back';

  @override
  String get dvrCancelSuccess => 'Recording cancelled';

  @override
  String get dvrCancelFailed => 'Could not cancel recording';

  @override
  String get dvrDeleteTitle => 'Delete recording?';

  @override
  String get dvrDeleteMessage => 'This recording will be deleted permanently.';

  @override
  String get dvrDeleteDismiss => 'Keep';

  @override
  String get dvrDeleteConfirm => 'Delete recording';

  @override
  String get dvrDeleteSuccess => 'Recording deleted';

  @override
  String get dvrDeleteFailed => 'Could not delete recording';

  @override
  String get liveTvStopRecording => 'Stop Recording';

  @override
  String get playerRecordNowTooltip => 'Record current program';

  @override
  String get playerStopRecordingTooltip => 'Stop recording';

  @override
  String get dvrMoreActions => 'More actions';

  @override
  String get dvrPlay => 'Play';

  @override
  String get dvrSelect => 'Select';

  @override
  String get dvrStop => 'Stop';

  @override
  String get dvrStatusRecording => 'Recording';

  @override
  String get dvrStatusScheduled => 'Scheduled';

  @override
  String get dvrStatusFailed => 'Failed';

  @override
  String get dvrExitSelection => 'Exit selection';

  @override
  String dvrSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items selected',
      one: '1 item selected',
      zero: 'No items selected',
    );
    return '$_temp0';
  }

  @override
  String get dvrStorageTitle => 'DVR Storage';

  @override
  String get dvrStorageUnlimited => 'Unlimited';

  @override
  String dvrStorageUsedUnlimited(String used) {
    return '$used used';
  }

  @override
  String dvrStorageUsedWithQuota(String used, String quota) {
    return '$used of $quota used';
  }

  @override
  String dvrStorageRecordingCount(int count) {
    return '$count recordings';
  }

  @override
  String get dvrSeriesChannel => 'Channel';

  @override
  String get dvrSeriesStartEarly => 'Start early';

  @override
  String get dvrSeriesUseDefault => 'Use default';

  @override
  String dvrEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$_temp0';
  }

  @override
  String get dvrDeleteSeriesRule => 'Delete rule';

  @override
  String get dvrEditSeriesRule => 'Edit rule';

  @override
  String get dvrUpdateSeriesRuleFailed => 'Could not update series rule';

  @override
  String get dvrSeriesSave => 'Save';

  @override
  String get dvrSeriesSecondsSuffix => 'sec';

  @override
  String get dvrSeriesMode => 'Series mode';

  @override
  String get dvrUpdateSeriesRuleSuccess => 'Series rule updated';

  @override
  String get dvrSeriesModeAll => 'All episodes';

  @override
  String get dvrSeriesMatchModeStartsWith => 'Starts with';

  @override
  String get dvrDeleteSeriesRuleConfirm => 'Delete this series rule?';

  @override
  String get dvrSeriesCancel => 'Cancel';

  @override
  String get dvrDeleteSeriesRuleSuccess => 'Series rule deleted';

  @override
  String get dvrSeriesRulesTitle => 'Series Rules';

  @override
  String get dvrSeriesMatchModeContains => 'Contains';

  @override
  String get dvrSeriesMatchModeExact => 'Exact';

  @override
  String get dvrSeriesModeUseDefault => 'Use default';

  @override
  String get dvrSeriesModeNewFlag => 'New only';

  @override
  String get dvrDeleteSeriesRuleFailed => 'Could not delete series rule';

  @override
  String get dvrSeriesKeepLast => 'Keep last';

  @override
  String get dvrSeriesModeUniqueSe => 'Unique S-E';

  @override
  String get dvrSeriesAnyChannel => 'Any channel';

  @override
  String get dvrSeriesMatchMode => 'Match mode';

  @override
  String get dvrSeriesEndLate => 'End late';

  @override
  String get dvrSeriesOptions => 'Options';

  @override
  String dvrSeriesOptionsFor(String title) {
    return 'Options: $title';
  }

  @override
  String get dvrSeriesAllEpisodesWarning =>
      'Recording all episodes on any channel may create duplicates — use New only or Unique S-E to deduplicate.';

  @override
  String get dvrSeriesRulesEmpty => 'No series rules';

  @override
  String get dvrSeriesPriority => 'Priority';

  @override
  String get epgRecordSeries => 'Record Series';

  @override
  String epgRecordSeriesSuccess(String title) {
    return 'Series recording set for $title';
  }

  @override
  String get epgRecordSeriesFailed => 'Could not set series recording';

  @override
  String get epgRecordSeriesDuplicate => 'Series recording already set';

  @override
  String get navShows => 'Shows';

  @override
  String get showAiringNext => 'Next airing';

  @override
  String get showAiringNone => 'No upcoming episodes in EPG';

  @override
  String showChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '1 channel',
    );
    return '$_temp0';
  }

  @override
  String get showDeleteRule => 'Delete series rule';

  @override
  String showDeleteRuleConfirm(String title) {
    return 'Delete the series rule for $title? Future episodes will not be recorded. Recordings already made will not be deleted.';
  }

  @override
  String get showSeriesRuleActive => 'Series rule active';

  @override
  String get showDetailTitle => 'Show details';

  @override
  String showEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$_temp0';
  }

  @override
  String get showRecordSeries => 'Record Series';

  @override
  String showRecordSeriesConfirm(String title, String channel) {
    return 'Record every episode of $title on $channel?';
  }

  @override
  String showRecordSeriesFailed(String title) {
    return 'Could not set series recording for $title';
  }

  @override
  String showRecordSeriesSuccess(String title) {
    return 'Series recording set for $title';
  }

  @override
  String showRecordSeriesDuplicate(String title) {
    return 'Series recording already set for $title';
  }

  @override
  String get showsError => 'Could not search shows';

  @override
  String get showsNoResults => 'No shows match your search';

  @override
  String get showsSearchError => 'Search failed';

  @override
  String get showsSearchHint => 'Search shows by title';

  @override
  String get showsTitle => 'Shows';

  @override
  String showNotFound(String title) {
    return 'Show \"$title\" not found';
  }
}
