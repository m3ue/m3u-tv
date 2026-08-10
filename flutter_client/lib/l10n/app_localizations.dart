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

  /// No description provided for @notificationsDesktopOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get notificationsDesktopOpen;

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

  /// No description provided for @liveTvRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get liveTvRecording;

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

  /// No description provided for @catchupBadgeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Catchup available'**
  String get catchupBadgeAvailable;

  /// No description provided for @catchupBadgeAvailableDays.
  ///
  /// In en, this message translates to:
  /// **'Catchup available: {days}d'**
  String catchupBadgeAvailableDays(int days);

  /// No description provided for @catchupProgramReplayable.
  ///
  /// In en, this message translates to:
  /// **'Catchup replay available'**
  String get catchupProgramReplayable;

  /// No description provided for @epgPreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get epgPreviousDay;

  /// No description provided for @epgNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get epgNow;

  /// No description provided for @epgNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get epgNextDay;

  /// No description provided for @epgChannels.
  ///
  /// In en, this message translates to:
  /// **'CHANNELS'**
  String get epgChannels;

  /// No description provided for @epgNoData.
  ///
  /// In en, this message translates to:
  /// **'No EPG data'**
  String get epgNoData;

  /// No description provided for @epgProgramScheduledToRecord.
  ///
  /// In en, this message translates to:
  /// **'Scheduled to record'**
  String get epgProgramScheduledToRecord;

  /// No description provided for @epgProgramCurrentlyRecording.
  ///
  /// In en, this message translates to:
  /// **'Currently recording'**
  String get epgProgramCurrentlyRecording;

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

  /// No description provided for @playerSkipPreviousTooltip.
  ///
  /// In en, this message translates to:
  /// **'Previous channel'**
  String get playerSkipPreviousTooltip;

  /// No description provided for @playerSkipNextTooltip.
  ///
  /// In en, this message translates to:
  /// **'Next channel'**
  String get playerSkipNextTooltip;

  /// No description provided for @playerNowPlayingMovie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get playerNowPlayingMovie;

  /// No description provided for @playerNowPlayingSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get playerNowPlayingSeries;

  /// No description provided for @playerNowPlayingSeasonEpisode.
  ///
  /// In en, this message translates to:
  /// **'S{season} · E{episode}'**
  String playerNowPlayingSeasonEpisode(int season, int episode);

  /// No description provided for @playerCommercialSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped commercial'**
  String get playerCommercialSkipped;

  /// No description provided for @playerSkipCommercial.
  ///
  /// In en, this message translates to:
  /// **'Skip commercial'**
  String get playerSkipCommercial;

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

  /// No description provided for @settingsDvr.
  ///
  /// In en, this message translates to:
  /// **'DVR'**
  String get settingsDvr;

  /// No description provided for @settingsDvrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Settings for recorded content playback.'**
  String get settingsDvrSubtitle;

  /// No description provided for @settingsComskip.
  ///
  /// In en, this message translates to:
  /// **'Commercial Skipping'**
  String get settingsComskip;

  /// No description provided for @settingsComskipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Controls how the player reacts to commercial breaks detected in DVR recordings.'**
  String get settingsComskipSubtitle;

  /// No description provided for @settingsComskipAutoSkip.
  ///
  /// In en, this message translates to:
  /// **'Auto-skip commercials'**
  String get settingsComskipAutoSkip;

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

  /// No description provided for @settingsApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsApp;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsAppVersion;

  /// No description provided for @settingsAppUpdateStatus.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get settingsAppUpdateStatus;

  /// No description provided for @settingsAppVersionChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get settingsAppVersionChecking;

  /// No description provided for @settingsAppUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsAppUpToDate;

  /// No description provided for @settingsAppUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {version}'**
  String settingsAppUpdateAvailable(String version);

  /// No description provided for @settingsAppViewRelease.
  ///
  /// In en, this message translates to:
  /// **'View release'**
  String get settingsAppViewRelease;

  /// No description provided for @settingsAppScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan to open on your phone'**
  String get settingsAppScanQr;

  /// No description provided for @settingsFillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get settingsFillAllFields;

  /// No description provided for @settingsConnectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Connection Settings'**
  String get settingsConnectionSettings;

  /// No description provided for @settingsConnectionSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your Xtream codes details'**
  String get settingsConnectionSettingsSubtitle;

  /// No description provided for @settingsConnectionSettingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Use the playlist Xtream connection details from m3u-editor, not your m3u-editor web login. You need the server URL, Xtream username and Xtream password.'**
  String get settingsConnectionSettingsHelp;

  /// No description provided for @settingsServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get settingsServerUrl;

  /// No description provided for @settingsUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get settingsUsername;

  /// No description provided for @settingsPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsPassword;

  /// No description provided for @settingsConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get settingsConnect;

  /// No description provided for @settingsPairWithCode.
  ///
  /// In en, this message translates to:
  /// **'Pair with code'**
  String get settingsPairWithCode;

  /// No description provided for @settingsTabPair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get settingsTabPair;

  /// No description provided for @settingsTabSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get settingsTabSignIn;

  /// No description provided for @settingsPairTabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your server address, then pair this TV using a code.'**
  String get settingsPairTabSubtitle;

  /// No description provided for @pairingEnterServerFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter your server URL first'**
  String get pairingEnterServerFirst;

  /// No description provided for @pairingErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed or the code expired. Please try again.'**
  String get pairingErrorGeneric;

  /// No description provided for @pairingScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan to open the pairing page on your phone'**
  String get pairingScanQr;

  /// No description provided for @pairingOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get pairingOpenBrowser;

  /// No description provided for @pairingPendingGoTo.
  ///
  /// In en, this message translates to:
  /// **'On your phone or computer, go to:'**
  String get pairingPendingGoTo;

  /// No description provided for @pairingPendingEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Then enter this code:'**
  String get pairingPendingEnterCode;

  /// No description provided for @pairingPendingWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval…'**
  String get pairingPendingWaiting;

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

  /// No description provided for @requestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requestsTitle;

  /// No description provided for @requestsTabSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get requestsTabSearch;

  /// No description provided for @requestsTabMyRequests.
  ///
  /// In en, this message translates to:
  /// **'My Requests'**
  String get requestsTabMyRequests;

  /// No description provided for @requestsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search movies & shows…'**
  String get requestsSearchHint;

  /// No description provided for @requestsNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get requestsNoResults;

  /// No description provided for @requestsAlreadyAvailable.
  ///
  /// In en, this message translates to:
  /// **'Already available'**
  String get requestsAlreadyAvailable;

  /// No description provided for @requestsAlreadyRequested.
  ///
  /// In en, this message translates to:
  /// **'Already requested'**
  String get requestsAlreadyRequested;

  /// No description provided for @requestsRequestButton.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get requestsRequestButton;

  /// No description provided for @requestsSeasonsHeading.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get requestsSeasonsHeading;

  /// No description provided for @requestsSeasonSpecials.
  ///
  /// In en, this message translates to:
  /// **'Specials'**
  String get requestsSeasonSpecials;

  /// No description provided for @requestsSelectAllSeasons.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get requestsSelectAllSeasons;

  /// No description provided for @requestsClearSeasons.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get requestsClearSeasons;

  /// No description provided for @requestsSubmitted.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" was requested'**
  String requestsSubmitted(String title);

  /// No description provided for @requestsSubmittedPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" was sent for approval'**
  String requestsSubmittedPendingApproval(String title);

  /// No description provided for @requestsSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not request \"{title}\": {error}'**
  String requestsSubmitFailed(String title, String error);

  /// No description provided for @requestsMyRequestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t requested anything yet'**
  String get requestsMyRequestsEmpty;

  /// No description provided for @requestsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get requestsDismiss;

  /// No description provided for @requestsDismissFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss request: {error}'**
  String requestsDismissFailed(String error);

  /// No description provided for @requestsStatusPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending Approval'**
  String get requestsStatusPendingApproval;

  /// No description provided for @requestsStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get requestsStatusApproved;

  /// No description provided for @requestsStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get requestsStatusRejected;

  /// No description provided for @requestsStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get requestsStatusCompleted;

  /// No description provided for @requestsStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get requestsStatusUnknown;

  /// No description provided for @dvrRecordingsTitle.
  ///
  /// In en, this message translates to:
  /// **'DVR Recordings'**
  String get dvrRecordingsTitle;

  /// No description provided for @dvrRecordingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Completed recordings and currently recording programmes'**
  String get dvrRecordingsSubtitle;

  /// No description provided for @dvrNoRecordings.
  ///
  /// In en, this message translates to:
  /// **'No DVR recordings available'**
  String get dvrNoRecordings;

  /// No description provided for @dvrNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Please connect to your service in Settings'**
  String get dvrNotConfigured;

  /// No description provided for @dvrCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dvrCancel;

  /// No description provided for @dvrDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dvrDelete;

  /// No description provided for @dvrStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop recording — {title}'**
  String dvrStopTitle(String title);

  /// No description provided for @dvrStopMessage.
  ///
  /// In en, this message translates to:
  /// **'Keep it in your recordings list, or delete it now?'**
  String get dvrStopMessage;

  /// No description provided for @dvrStopKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep recording'**
  String get dvrStopKeep;

  /// No description provided for @dvrStopDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get dvrStopDelete;

  /// No description provided for @dvrStopBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get dvrStopBack;

  /// No description provided for @dvrCancelSuccess.
  ///
  /// In en, this message translates to:
  /// **'Recording cancelled'**
  String get dvrCancelSuccess;

  /// No description provided for @dvrCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not cancel recording'**
  String get dvrCancelFailed;

  /// No description provided for @dvrDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete recording?'**
  String get dvrDeleteTitle;

  /// No description provided for @dvrDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This recording will be deleted permanently.'**
  String get dvrDeleteMessage;

  /// No description provided for @dvrDeleteDismiss.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get dvrDeleteDismiss;

  /// No description provided for @dvrDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete recording'**
  String get dvrDeleteConfirm;

  /// No description provided for @dvrDeleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Recording deleted'**
  String get dvrDeleteSuccess;

  /// No description provided for @dvrDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete recording'**
  String get dvrDeleteFailed;

  /// No description provided for @liveTvStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop Recording'**
  String get liveTvStopRecording;

  /// No description provided for @playerRecordNowTooltip.
  ///
  /// In en, this message translates to:
  /// **'Record current program'**
  String get playerRecordNowTooltip;

  /// No description provided for @playerStopRecordingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get playerStopRecordingTooltip;

  /// No description provided for @dvrMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get dvrMoreActions;

  /// No description provided for @dvrPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get dvrPlay;

  /// No description provided for @dvrSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get dvrSelect;

  /// No description provided for @dvrStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get dvrStop;

  /// No description provided for @dvrStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get dvrStatusRecording;

  /// No description provided for @dvrStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get dvrStatusScheduled;

  /// No description provided for @dvrStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get dvrStatusFailed;

  /// No description provided for @dvrExitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get dvrExitSelection;

  /// No description provided for @dvrSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items selected} one{1 item selected} other{{count} items selected}}'**
  String dvrSelectedCount(int count);

  /// No description provided for @dvrStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'DVR Storage'**
  String get dvrStorageTitle;

  /// No description provided for @dvrStorageUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get dvrStorageUnlimited;

  /// No description provided for @dvrStorageUsedUnlimited.
  ///
  /// In en, this message translates to:
  /// **'{used} used'**
  String dvrStorageUsedUnlimited(String used);

  /// No description provided for @dvrStorageUsedWithQuota.
  ///
  /// In en, this message translates to:
  /// **'{used} of {quota} used'**
  String dvrStorageUsedWithQuota(String used, String quota);

  /// No description provided for @dvrStorageRecordingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} recordings'**
  String dvrStorageRecordingCount(int count);

  /// No description provided for @dvrSeriesChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get dvrSeriesChannel;

  /// No description provided for @dvrSeriesStartEarly.
  ///
  /// In en, this message translates to:
  /// **'Start early'**
  String get dvrSeriesStartEarly;

  /// No description provided for @dvrSeriesUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get dvrSeriesUseDefault;

  /// No description provided for @dvrEpisodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 episode} other{{count} episodes}}'**
  String dvrEpisodeCount(int count);

  /// No description provided for @dvrDeleteSeriesRule.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get dvrDeleteSeriesRule;

  /// No description provided for @dvrEditSeriesRule.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get dvrEditSeriesRule;

  /// No description provided for @dvrUpdateSeriesRuleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update series rule'**
  String get dvrUpdateSeriesRuleFailed;

  /// No description provided for @dvrSeriesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dvrSeriesSave;

  /// No description provided for @dvrSeriesSecondsSuffix.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get dvrSeriesSecondsSuffix;

  /// No description provided for @dvrSeriesMode.
  ///
  /// In en, this message translates to:
  /// **'Series mode'**
  String get dvrSeriesMode;

  /// No description provided for @dvrUpdateSeriesRuleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Series rule updated'**
  String get dvrUpdateSeriesRuleSuccess;

  /// No description provided for @dvrSeriesModeAll.
  ///
  /// In en, this message translates to:
  /// **'All episodes'**
  String get dvrSeriesModeAll;

  /// No description provided for @dvrSeriesMatchModeStartsWith.
  ///
  /// In en, this message translates to:
  /// **'Starts with'**
  String get dvrSeriesMatchModeStartsWith;

  /// No description provided for @dvrDeleteSeriesRuleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this series rule?'**
  String get dvrDeleteSeriesRuleConfirm;

  /// No description provided for @dvrSeriesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dvrSeriesCancel;

  /// No description provided for @dvrDeleteSeriesRuleSuccess.
  ///
  /// In en, this message translates to:
  /// **'Series rule deleted'**
  String get dvrDeleteSeriesRuleSuccess;

  /// No description provided for @dvrSeriesRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Series Rules'**
  String get dvrSeriesRulesTitle;

  /// No description provided for @dvrSeriesMatchModeContains.
  ///
  /// In en, this message translates to:
  /// **'Contains'**
  String get dvrSeriesMatchModeContains;

  /// No description provided for @dvrSeriesMatchModeExact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get dvrSeriesMatchModeExact;

  /// No description provided for @dvrSeriesModeUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get dvrSeriesModeUseDefault;

  /// No description provided for @dvrSeriesModeNewFlag.
  ///
  /// In en, this message translates to:
  /// **'New only'**
  String get dvrSeriesModeNewFlag;

  /// No description provided for @dvrDeleteSeriesRuleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete series rule'**
  String get dvrDeleteSeriesRuleFailed;

  /// No description provided for @dvrSeriesKeepLast.
  ///
  /// In en, this message translates to:
  /// **'Keep last'**
  String get dvrSeriesKeepLast;

  /// No description provided for @dvrSeriesModeUniqueSe.
  ///
  /// In en, this message translates to:
  /// **'Unique S-E'**
  String get dvrSeriesModeUniqueSe;

  /// No description provided for @dvrSeriesAnyChannel.
  ///
  /// In en, this message translates to:
  /// **'Any channel'**
  String get dvrSeriesAnyChannel;

  /// No description provided for @dvrSeriesMatchMode.
  ///
  /// In en, this message translates to:
  /// **'Match mode'**
  String get dvrSeriesMatchMode;

  /// No description provided for @dvrSeriesEndLate.
  ///
  /// In en, this message translates to:
  /// **'End late'**
  String get dvrSeriesEndLate;

  /// No description provided for @dvrSeriesOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get dvrSeriesOptions;

  /// No description provided for @dvrSeriesOptionsFor.
  ///
  /// In en, this message translates to:
  /// **'Options: {title}'**
  String dvrSeriesOptionsFor(String title);

  /// No description provided for @dvrSeriesAllEpisodesWarning.
  ///
  /// In en, this message translates to:
  /// **'Recording all episodes on any channel may create duplicates — use New only or Unique S-E to deduplicate.'**
  String get dvrSeriesAllEpisodesWarning;

  /// No description provided for @dvrSeriesRulesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No series rules'**
  String get dvrSeriesRulesEmpty;

  /// No description provided for @dvrSeriesPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get dvrSeriesPriority;

  /// No description provided for @epgRecordSeries.
  ///
  /// In en, this message translates to:
  /// **'Record Series'**
  String get epgRecordSeries;

  /// No description provided for @epgRecordSeriesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Series recording set for {title}'**
  String epgRecordSeriesSuccess(String title);

  /// No description provided for @epgRecordSeriesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not set series recording'**
  String get epgRecordSeriesFailed;

  /// No description provided for @epgRecordSeriesDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Series recording already set'**
  String get epgRecordSeriesDuplicate;

  /// No description provided for @navShows.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get navShows;

  /// No description provided for @showAiringNext.
  ///
  /// In en, this message translates to:
  /// **'Next airing'**
  String get showAiringNext;

  /// No description provided for @showAiringNone.
  ///
  /// In en, this message translates to:
  /// **'No upcoming episodes in EPG'**
  String get showAiringNone;

  /// No description provided for @showChannelCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 channel} other{{count} channels}}'**
  String showChannelCount(int count);

  /// No description provided for @showDeleteRule.
  ///
  /// In en, this message translates to:
  /// **'Delete series rule'**
  String get showDeleteRule;

  /// No description provided for @showDeleteRuleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the series rule for {title}? Future episodes will not be recorded. Recordings already made will not be deleted.'**
  String showDeleteRuleConfirm(String title);

  /// No description provided for @showSeriesRuleActive.
  ///
  /// In en, this message translates to:
  /// **'Series rule active'**
  String get showSeriesRuleActive;

  /// No description provided for @showDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get showDetailTitle;

  /// No description provided for @showEpisodesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 episode} other{{count} episodes}}'**
  String showEpisodesCount(int count);

  /// No description provided for @showRecordSeries.
  ///
  /// In en, this message translates to:
  /// **'Record Series'**
  String get showRecordSeries;

  /// No description provided for @showRecordSeriesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Record every episode of {title} on {channel}?'**
  String showRecordSeriesConfirm(String title, String channel);

  /// No description provided for @showRecordSeriesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not set series recording for {title}'**
  String showRecordSeriesFailed(String title);

  /// No description provided for @showRecordSeriesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Series recording set for {title}'**
  String showRecordSeriesSuccess(String title);

  /// No description provided for @showRecordSeriesDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Series recording already set for {title}'**
  String showRecordSeriesDuplicate(String title);

  /// No description provided for @showsError.
  ///
  /// In en, this message translates to:
  /// **'Could not search shows'**
  String get showsError;

  /// No description provided for @showsNoResults.
  ///
  /// In en, this message translates to:
  /// **'No shows match your search'**
  String get showsNoResults;

  /// No description provided for @showsSearchError.
  ///
  /// In en, this message translates to:
  /// **'Search failed'**
  String get showsSearchError;

  /// No description provided for @showsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search shows by title'**
  String get showsSearchHint;

  /// No description provided for @showsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get showsTitle;

  /// No description provided for @showNotFound.
  ///
  /// In en, this message translates to:
  /// **'Show \"{title}\" not found'**
  String showNotFound(String title);

  /// No description provided for @settingsView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get settingsView;

  /// No description provided for @settingsLiveTvLayout.
  ///
  /// In en, this message translates to:
  /// **'Live TV layout'**
  String get settingsLiveTvLayout;

  /// No description provided for @settingsLiveTvLayoutList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get settingsLiveTvLayoutList;

  /// No description provided for @settingsLiveTvLayoutGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get settingsLiveTvLayoutGrid;

  /// No description provided for @settingsLiveTvLayoutTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get settingsLiveTvLayoutTimeline;

  /// No description provided for @settingsEpgStartView.
  ///
  /// In en, this message translates to:
  /// **'EPG starts at'**
  String get settingsEpgStartView;

  /// No description provided for @settingsEpgStartViewCurrentTime.
  ///
  /// In en, this message translates to:
  /// **'Current time'**
  String get settingsEpgStartViewCurrentTime;

  /// No description provided for @settingsEpgStartViewPrimeTime.
  ///
  /// In en, this message translates to:
  /// **'Prime time'**
  String get settingsEpgStartViewPrimeTime;
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
