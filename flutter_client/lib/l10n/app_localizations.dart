import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('zh'),
  ];

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navLiveTv.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get navLiveTv;

  /// No description provided for @navVod.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get navVod;

  /// No description provided for @navSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get navSeries;

  /// No description provided for @navDvr.
  ///
  /// In en, this message translates to:
  /// **'DVR'**
  String get navDvr;

  /// No description provided for @navRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get navRequests;

  /// No description provided for @navNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get navNotifications;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @appBackToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get appBackToExit;

  /// No description provided for @appRecordingScheduled.
  ///
  /// In en, this message translates to:
  /// **'Recording scheduled: {title}'**
  String appRecordingScheduled(String title);

  /// No description provided for @appRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not schedule recording: {error}'**
  String appRecordingFailed(String error);

  /// No description provided for @appNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Please connect to your service in Settings'**
  String get appNotConfigured;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @liveTvSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search live TV...'**
  String get liveTvSearchHint;

  /// No description provided for @liveTvNoChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels available'**
  String get liveTvNoChannels;

  /// No description provided for @liveTvAllChannels.
  ///
  /// In en, this message translates to:
  /// **'All Channels'**
  String get liveTvAllChannels;

  /// No description provided for @liveTvFavorites.
  ///
  /// In en, this message translates to:
  /// **'★ Favorites'**
  String get liveTvFavorites;

  /// No description provided for @liveTvNoProgram.
  ///
  /// In en, this message translates to:
  /// **'No program info'**
  String get liveTvNoProgram;

  /// No description provided for @liveTvNext.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get liveTvNext;

  /// No description provided for @liveTvRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get liveTvRecord;

  /// No description provided for @liveTvFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get liveTvFavorite;

  /// No description provided for @liveTvRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove favorite'**
  String get liveTvRemoveFavorite;

  /// No description provided for @playerGoBack.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get playerGoBack;

  /// No description provided for @playerResumeWatching.
  ///
  /// In en, this message translates to:
  /// **'Resume Watching'**
  String get playerResumeWatching;

  /// No description provided for @playerContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get playerContinue;

  /// No description provided for @playerFromTime.
  ///
  /// In en, this message translates to:
  /// **'From {time}'**
  String playerFromTime(String time);

  /// No description provided for @playerStartFromBeginning.
  ///
  /// In en, this message translates to:
  /// **'Start from Beginning'**
  String get playerStartFromBeginning;

  /// No description provided for @playerResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get playerResume;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search live TV, movies, and series...'**
  String get searchHint;

  /// No description provided for @searchSectionLiveTv.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get searchSectionLiveTv;

  /// No description provided for @searchSectionMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get searchSectionMovies;

  /// No description provided for @searchSectionSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get searchSectionSeries;

  /// No description provided for @vodSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search movies...'**
  String get vodSearchHint;

  /// No description provided for @seriesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search series...'**
  String get seriesSearchHint;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get settingsIntegrations;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLangEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLangEnglish;

  /// No description provided for @settingsLangGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get settingsLangGerman;

  /// No description provided for @settingsLangSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsLangSpanish;

  /// No description provided for @settingsLangFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get settingsLangFrench;

  /// No description provided for @settingsLangChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get settingsLangChinese;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// No description provided for @settingsStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get settingsStatusConnected;

  /// No description provided for @settingsStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsStatusUnavailable;

  /// No description provided for @settingsStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get settingsStatusLabel;

  /// No description provided for @settingsSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get settingsSourceLabel;

  /// No description provided for @settingsServerTimezone.
  ///
  /// In en, this message translates to:
  /// **'Server Timezone'**
  String get settingsServerTimezone;

  /// No description provided for @settingsLastError.
  ///
  /// In en, this message translates to:
  /// **'Last error'**
  String get settingsLastError;

  /// No description provided for @settingsRetryConnection.
  ///
  /// In en, this message translates to:
  /// **'Retry connection'**
  String get settingsRetryConnection;

  /// No description provided for @settingsEditServer.
  ///
  /// In en, this message translates to:
  /// **'Edit server settings'**
  String get settingsEditServer;

  /// No description provided for @settingsActiveViewer.
  ///
  /// In en, this message translates to:
  /// **'Active Viewer'**
  String get settingsActiveViewer;

  /// No description provided for @settingsClearCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache & Refresh?'**
  String get settingsClearCacheTitle;

  /// No description provided for @settingsClearCacheBody.
  ///
  /// In en, this message translates to:
  /// **'All cached content will be cleared and reloaded from your source.'**
  String get settingsClearCacheBody;

  /// No description provided for @settingsClearCacheConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear & Refresh'**
  String get settingsClearCacheConfirm;

  /// No description provided for @settingsCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared — content is refreshing in the background.'**
  String get settingsCacheCleared;

  /// No description provided for @settingsContentCache.
  ///
  /// In en, this message translates to:
  /// **'Content Cache'**
  String get settingsContentCache;

  /// No description provided for @settingsCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cached content loads instantly. Data refreshes automatically in the background.'**
  String get settingsCacheSubtitle;

  /// No description provided for @settingsEpgRefreshInterval.
  ///
  /// In en, this message translates to:
  /// **'EPG refresh interval'**
  String get settingsEpgRefreshInterval;

  /// No description provided for @settingsEpgDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String settingsEpgDurationMinutes(int count);

  /// No description provided for @settingsEpgDurationHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get settingsEpgDurationHour;

  /// No description provided for @settingsEpgDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{count} hours'**
  String settingsEpgDurationHours(int count);

  /// No description provided for @settingsManageViewers.
  ///
  /// In en, this message translates to:
  /// **'Manage Viewers'**
  String get settingsManageViewers;

  /// No description provided for @settingsAddViewer.
  ///
  /// In en, this message translates to:
  /// **'Add New Viewer'**
  String get settingsAddViewer;

  /// No description provided for @settingsSwitchViewer.
  ///
  /// In en, this message translates to:
  /// **'Switch Viewer'**
  String get settingsSwitchViewer;

  /// No description provided for @settingsViewerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Viewer name'**
  String get settingsViewerNameLabel;

  /// No description provided for @settingsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get settingsCreate;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsProxyPlayback.
  ///
  /// In en, this message translates to:
  /// **'Proxy Playback'**
  String get settingsProxyPlayback;

  /// No description provided for @settingsProxyPlaybackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stream through the m3u-editor proxy with an optional transcoding profile for this device.'**
  String get settingsProxyPlaybackSubtitle;

  /// No description provided for @settingsProxyUse.
  ///
  /// In en, this message translates to:
  /// **'Use proxy'**
  String get settingsProxyUse;

  /// No description provided for @settingsProxyForced.
  ///
  /// In en, this message translates to:
  /// **'The proxy is enabled at the playlist level and cannot be turned off.'**
  String get settingsProxyForced;

  /// No description provided for @settingsProxyLiveProfile.
  ///
  /// In en, this message translates to:
  /// **'Live transcoding profile'**
  String get settingsProxyLiveProfile;

  /// No description provided for @settingsProxyVodProfile.
  ///
  /// In en, this message translates to:
  /// **'VOD & Series transcoding profile'**
  String get settingsProxyVodProfile;

  /// No description provided for @settingsProxyProfileDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settingsProxyProfileDefault;

  /// No description provided for @settingsProxyProfileDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct (no transcoding)'**
  String get settingsProxyProfileDirect;

  /// No description provided for @settingsProxyNoProfiles.
  ///
  /// In en, this message translates to:
  /// **'No transcoding profiles available — streams use the direct proxy.'**
  String get settingsProxyNoProfiles;

  /// No description provided for @settingsDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect?'**
  String get settingsDisconnectTitle;

  /// No description provided for @settingsDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'You will be signed out and will need to re-enter your credentials to reconnect.'**
  String get settingsDisconnectBody;

  /// No description provided for @settingsDisconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get settingsDisconnectConfirm;

  /// No description provided for @homeContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get homeContinueWatching;

  /// No description provided for @homeNoContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'No Continue Watching available'**
  String get homeNoContinueWatching;

  /// No description provided for @homeNoLiveTv.
  ///
  /// In en, this message translates to:
  /// **'No Live TV available'**
  String get homeNoLiveTv;

  /// No description provided for @homeFavoriteChannels.
  ///
  /// In en, this message translates to:
  /// **'Favorite Channels'**
  String get homeFavoriteChannels;

  /// No description provided for @homeNoFavoriteChannels.
  ///
  /// In en, this message translates to:
  /// **'No favorite channels available'**
  String get homeNoFavoriteChannels;

  /// No description provided for @homeNoMovies.
  ///
  /// In en, this message translates to:
  /// **'No Movies available'**
  String get homeNoMovies;

  /// No description provided for @homeLiveChannel.
  ///
  /// In en, this message translates to:
  /// **'Live channel'**
  String get homeLiveChannel;

  /// No description provided for @homeMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get homeMovie;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsTabNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTabNotifications;

  /// No description provided for @notificationsTabChannelSettings.
  ///
  /// In en, this message translates to:
  /// **'Channel Settings'**
  String get notificationsTabChannelSettings;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationsEmpty;

  /// No description provided for @notificationsEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'No notifications for your subscribed channels'**
  String get notificationsEmptyFiltered;

  /// No description provided for @notificationsChannelSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Channel subscriptions'**
  String get notificationsChannelSubscriptions;

  /// No description provided for @notificationsChannelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select which channels you want to receive. Leave all unselected to receive everything.'**
  String get notificationsChannelSubtitle;

  /// No description provided for @notificationsAllChannels.
  ///
  /// In en, this message translates to:
  /// **'All channels'**
  String get notificationsAllChannels;

  /// No description provided for @notificationsNoChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels seen yet — they appear here as notifications arrive.'**
  String get notificationsNoChannels;

  /// No description provided for @notificationsJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get notificationsJustNow;

  /// No description provided for @notificationsMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String notificationsMinutesAgo(int count);

  /// No description provided for @notificationsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String notificationsHoursAgo(int count);

  /// No description provided for @notificationsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String notificationsDaysAgo(int count);

  /// No description provided for @notificationsReceivedAt.
  ///
  /// In en, this message translates to:
  /// **'Received {time}'**
  String notificationsReceivedAt(String time);

  /// No description provided for @notificationsReadAt.
  ///
  /// In en, this message translates to:
  /// **'Read {time}'**
  String notificationsReadAt(String time);

  /// No description provided for @homeNoSeries.
  ///
  /// In en, this message translates to:
  /// **'No Series available'**
  String get homeNoSeries;

  /// No description provided for @homeSeason.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String homeSeason(int number);

  /// No description provided for @traktWatchHistory.
  ///
  /// In en, this message translates to:
  /// **'Watch History'**
  String get traktWatchHistory;

  /// No description provided for @traktWatchHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync your watch history with Trakt to track progress across apps and services.'**
  String get traktWatchHistorySubtitle;

  /// No description provided for @traktNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Trakt client credentials are not configured.'**
  String get traktNotConfigured;

  /// No description provided for @traktNotConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'Register an app at trakt.tv/oauth/applications and set the client ID and secret via --dart-define at build time.'**
  String get traktNotConfiguredHint;

  /// No description provided for @traktConnectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect your Trakt account to automatically track what you watch.'**
  String get traktConnectPrompt;

  /// No description provided for @traktConnectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect with Trakt'**
  String get traktConnectButton;

  /// No description provided for @traktScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan to open on your phone'**
  String get traktScanQr;

  /// No description provided for @traktOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get traktOpenBrowser;

  /// No description provided for @traktPendingGoTo.
  ///
  /// In en, this message translates to:
  /// **'On your phone or computer, go to:'**
  String get traktPendingGoTo;

  /// No description provided for @traktPendingEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Then enter this code:'**
  String get traktPendingEnterCode;

  /// No description provided for @traktPendingWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for authorization…'**
  String get traktPendingWaiting;

  /// No description provided for @traktConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to Trakt'**
  String get traktConnected;

  /// No description provided for @traktDisconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Trakt'**
  String get traktDisconnectButton;

  /// No description provided for @vodAllMovies.
  ///
  /// In en, this message translates to:
  /// **'All Movies'**
  String get vodAllMovies;

  /// No description provided for @seriesAllSeries.
  ///
  /// In en, this message translates to:
  /// **'All Series'**
  String get seriesAllSeries;

  /// No description provided for @homeConnectedSource.
  ///
  /// In en, this message translates to:
  /// **'Connected source: {label}'**
  String homeConnectedSource(String label);

  /// No description provided for @searchTypeToSearch.
  ///
  /// In en, this message translates to:
  /// **'Type to search'**
  String get searchTypeToSearch;

  /// No description provided for @vodPlayMovie.
  ///
  /// In en, this message translates to:
  /// **'Play movie'**
  String get vodPlayMovie;

  /// No description provided for @vodContinueMovie.
  ///
  /// In en, this message translates to:
  /// **'Continue movie'**
  String get vodContinueMovie;

  /// No description provided for @navAioStreams.
  ///
  /// In en, this message translates to:
  /// **'AIOStreams'**
  String get navAioStreams;

  /// No description provided for @aiostreamsGetStreams.
  ///
  /// In en, this message translates to:
  /// **'Get Streams'**
  String get aiostreamsGetStreams;

  /// No description provided for @aiostreamsLoadingStreams.
  ///
  /// In en, this message translates to:
  /// **'Loading streams…'**
  String get aiostreamsLoadingStreams;

  /// No description provided for @aiostreamsNoStreams.
  ///
  /// In en, this message translates to:
  /// **'No streams found'**
  String get aiostreamsNoStreams;

  /// No description provided for @aiostreamsSelectStream.
  ///
  /// In en, this message translates to:
  /// **'Select a stream'**
  String get aiostreamsSelectStream;

  /// No description provided for @aiostreamsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get aiostreamsLoadMore;

  /// No description provided for @aiostreamsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search movies & series…'**
  String get aiostreamsSearchHint;

  /// No description provided for @aiostrreamsCatalogEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get aiostrreamsCatalogEmpty;

  /// No description provided for @aiostreamsToggleFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get aiostreamsToggleFavorite;

  /// No description provided for @aiostreamsMyFavorites.
  ///
  /// In en, this message translates to:
  /// **'My Favorites'**
  String get aiostreamsMyFavorites;

  /// No description provided for @aiostreamsContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get aiostreamsContinueWatching;

  /// No description provided for @aiostreamsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search AIOStreams'**
  String get aiostreamsSearch;

  /// No description provided for @aiostreamsSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Search Results'**
  String get aiostreamsSearchResults;

  /// No description provided for @aiostreamsNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get aiostreamsNoResults;

  /// No description provided for @aiostreamsSearchAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get aiostreamsSearchAll;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
