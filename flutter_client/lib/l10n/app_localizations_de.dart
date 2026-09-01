// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get navHome => 'Startseite';

  @override
  String get navSearch => 'Suche';

  @override
  String get navLiveTv => 'Live-TV';

  @override
  String get navVod => 'Filme';

  @override
  String get navSeries => 'Serien';

  @override
  String get navDvr => 'DVR';

  @override
  String get navRequests => 'Anfragen';

  @override
  String get navNotifications => 'Mitteilungen';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navMore => 'Mehr';

  @override
  String get notificationsDesktopOpen => 'Öffnen';

  @override
  String get appBackToExit => 'Zum Beenden erneut Zurück drücken';

  @override
  String appRecordingScheduled(String title) {
    return 'Aufnahme geplant: $title';
  }

  @override
  String appRecordingFailed(String error) {
    return 'Aufnahme konnte nicht geplant werden: $error';
  }

  @override
  String get appNotConfigured =>
      'Bitte verbinde deinen Dienst in den Einstellungen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get disconnect => 'Trennen';

  @override
  String get unknown => 'Unbekannt';

  @override
  String get admin => 'Admin';

  @override
  String get mediaCategoryFilterButton => 'Filter';

  @override
  String get mediaCategoryFilterScreenTitle => 'Categories';

  @override
  String get liveTvViewModeList => 'List';

  @override
  String get liveTvViewModeGrid => 'Grid';

  @override
  String get liveTvViewModeEpg => 'EPG';

  @override
  String get liveTvSearchHint => 'Suchen …';

  @override
  String get liveTvUpcomingAirings => 'Demnächst';

  @override
  String get liveTvSearchFilterAll => 'Alle';

  @override
  String get liveTvShowResultsLoading => 'Sendungen werden gesucht …';

  @override
  String get liveTvOnNow => 'Jetzt live';

  @override
  String liveTvAiringUntil(String time) {
    return 'Bis $time';
  }

  @override
  String liveTvAiringTomorrow(String time) {
    return 'Morgen $time';
  }

  @override
  String liveTvMoreAirings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count weitere',
      one: '+1 weitere',
    );
    return '$_temp0';
  }

  @override
  String get liveTvNoChannels => 'Keine Sender verfügbar';

  @override
  String get liveTvAllChannels => 'Alle Sender';

  @override
  String get liveTvFavorites => '★ Favoriten';

  @override
  String get liveTvNoProgram => 'Keine Programminfo';

  @override
  String get liveTvNext => 'NÄCHSTES';

  @override
  String get liveTvRecord => 'Aufnehmen';

  @override
  String get liveTvRecording => 'Aufnahme läuft';

  @override
  String get liveTvFavorite => 'Favorit';

  @override
  String get liveTvRemoveFavorite => 'Aus Favoriten entfernen';

  @override
  String get liveTvCatchupShows => 'Catchup-Sendungen';

  @override
  String get catchupShowsEmpty => 'Keine Catchup-Sendungen verfügbar';

  @override
  String get catchupShowsLoading => 'Catchup-Sendungen werden geladen…';

  @override
  String get liveTvAddMultiview => 'Zu Multiview hinzufügen';

  @override
  String get liveTvRemoveMultiview => 'Aus Multiview entfernen';

  @override
  String get liveTvMultiviewFull => 'Multiview ist voll (max. 9 Streams)';

  @override
  String get multiviewTitle => 'Multiview';

  @override
  String get multiviewEmpty =>
      'Keine Streams - Kanal in Live TV lange drücken und „Zu Multiview hinzufügen“ wählen';

  @override
  String get multiviewMove => 'Verschieben';

  @override
  String get multiviewOpenFullscreen => 'Vollbild öffnen';

  @override
  String get multiviewMakeFeatured => 'Hervorheben';

  @override
  String get multiviewPictureInPicture => 'Bild-in-Bild';

  @override
  String get multiviewBackToGrid => 'Zurück zum Raster';

  @override
  String get multiviewRemove => 'Aus Multiview entfernen';

  @override
  String get multiviewRetry =>
      'Wiedergabe fehlgeschlagen - zum Wiederholen auswählen';

  @override
  String get multiviewManageTitle => 'Multiview verwalten';

  @override
  String get multiviewClearAll => 'Alle entfernen';

  @override
  String multiviewRemoveChannel(String channel) {
    return '$channel entfernen';
  }

  @override
  String get close => 'Schließen';

  @override
  String get catchupBadgeAvailable => 'Catchup verfügbar';

  @override
  String catchupBadgeAvailableDays(int days) {
    return 'Catchup verfügbar: $days Tage';
  }

  @override
  String get catchupProgramReplayable => 'Catchup-Wiedergabe verfügbar';

  @override
  String get epgPreviousDay => 'Vorheriger Tag';

  @override
  String get epgNow => 'Jetzt';

  @override
  String get epgNextDay => 'Nächster Tag';

  @override
  String get epgChannels => 'SENDER';

  @override
  String get epgNoData => 'Keine EPG-Daten';

  @override
  String get epgProgramScheduledToRecord => 'Aufnahme geplant';

  @override
  String get epgProgramCurrentlyRecording => 'Wird aufgenommen';

  @override
  String get playerGoBack => 'Zurück';

  @override
  String get playerResumeWatching => 'Weiterschauen';

  @override
  String get playerContinue => 'Fortsetzen';

  @override
  String playerFromTime(String time) {
    return 'Ab $time';
  }

  @override
  String get playerStartFromBeginning => 'Von vorne abspielen';

  @override
  String get playerResume => 'Fortsetzen';

  @override
  String get playerSkipPreviousTooltip => 'Vorheriger Sender';

  @override
  String get playerSkipNextTooltip => 'Nächster Sender';

  @override
  String get playerNowPlayingMovie => 'Film';

  @override
  String get playerNowPlayingSeries => 'Serie';

  @override
  String playerNowPlayingSeasonEpisode(int season, int episode) {
    return 'S$season · F$episode';
  }

  @override
  String get playerCommercialSkipped => 'Werbung übersprungen';

  @override
  String get playerSkipCommercial => 'Werbung überspringen';

  @override
  String get playerSkipCredits => 'Abspann überspringen';

  @override
  String get playerSkipIntro => 'Intro überspringen';

  @override
  String get playerUpNext => 'Als Nächstes';

  @override
  String get playerUpNextPlay => 'Nächste Folge';

  @override
  String get playerUpNextDismiss => 'Schließen';

  @override
  String get searchHint => 'Live-TV, Filme und Serien durchsuchen …';

  @override
  String get searchSectionLiveTv => 'Live-TV';

  @override
  String get searchSectionMovies => 'Filme';

  @override
  String get searchSectionSeries => 'Serien';

  @override
  String get vodSearchHint => 'Suchen …';

  @override
  String get seriesSearchHint => 'Suchen …';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsGeneral => 'Allgemein';

  @override
  String get settingsIntegrations => 'Integrationen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageSystem => 'Systemsprache';

  @override
  String get settingsLangEnglish => 'Englisch';

  @override
  String get settingsLangGerman => 'Deutsch';

  @override
  String get settingsLangSpanish => 'Spanisch';

  @override
  String get settingsLangFrench => 'Französisch';

  @override
  String get settingsLangChinese => 'Chinesisch (Vereinfacht)';

  @override
  String get settingsConnection => 'Verbindung';

  @override
  String get settingsStatusConnected => 'Verbunden';

  @override
  String get settingsStatusUnavailable => 'Nicht verfügbar';

  @override
  String get settingsStatusLabel => 'Status';

  @override
  String get settingsSourceLabel => 'Quelle';

  @override
  String get settingsServerTimezone => 'Server-Zeitzone';

  @override
  String get settingsLastError => 'Letzter Fehler';

  @override
  String get settingsRetryConnection => 'Verbindung wiederherstellen';

  @override
  String get settingsEditServer => 'Servereinstellungen bearbeiten';

  @override
  String get settingsActiveViewer => 'Aktiver Nutzer';

  @override
  String get settingsClearCacheTitle => 'Cache löschen und aktualisieren?';

  @override
  String get settingsClearCacheBody =>
      'Alle gecachten Inhalte werden gelöscht und von deiner Quelle neu geladen.';

  @override
  String get settingsClearCacheConfirm => 'Löschen und aktualisieren';

  @override
  String get settingsCacheCleared =>
      'Cache geleert – Inhalte werden im Hintergrund aktualisiert.';

  @override
  String get settingsContentCache => 'Inhaltscache';

  @override
  String get settingsCacheSubtitle =>
      'Gecachte Inhalte laden sofort. Daten werden automatisch im Hintergrund aktualisiert.';

  @override
  String get settingsEpgRefreshInterval => 'EPG-Aktualisierungsintervall';

  @override
  String settingsEpgDurationMinutes(int count) {
    return '$count Min';
  }

  @override
  String get settingsEpgDurationHour => '1 Stunde';

  @override
  String settingsEpgDurationHours(int count) {
    return '$count Stunden';
  }

  @override
  String get settingsManageViewers => 'Zuschauer verwalten';

  @override
  String get settingsAddViewer => 'Neuer Zuschauer';

  @override
  String get settingsSwitchViewer => 'Zuschauer wechseln';

  @override
  String get settingsViewerNameLabel => 'Name des Zuschauers';

  @override
  String get settingsCreate => 'Erstellen';

  @override
  String get settingsAccount => 'Konto';

  @override
  String get settingsProxyPlayback => 'Proxy-Wiedergabe';

  @override
  String get settingsProxyPlaybackSubtitle =>
      'Streams über den m3u-editor-Proxy mit optionalem Transkodierungsprofil für dieses Gerät.';

  @override
  String get settingsProxyUse => 'Proxy verwenden';

  @override
  String get settingsProxyForced =>
      'Der Proxy ist auf Playlist-Ebene aktiviert und kann nicht deaktiviert werden.';

  @override
  String get settingsProxyLiveProfile => 'Live-Transkodierungsprofil';

  @override
  String get settingsProxyVodProfile => 'VOD- & Serien-Transkodierungsprofil';

  @override
  String get settingsProxyProfileDefault => 'Standard';

  @override
  String get settingsProxyProfileDirect => 'Direkt (ohne Transkodierung)';

  @override
  String get settingsProxyNoProfiles =>
      'Keine Transkodierungsprofile verfügbar — Streams nutzen den direkten Proxy.';

  @override
  String get settingsDvr => 'DVR';

  @override
  String get settingsDvrSubtitle =>
      'Einstellungen für die Wiedergabe aufgenommener Inhalte.';

  @override
  String get settingsComskip => 'Werbeerkennung';

  @override
  String get settingsComskipSubtitle =>
      'Legt fest, wie der Player auf erkannte Werbeunterbrechungen in DVR-Aufnahmen reagiert.';

  @override
  String get settingsComskipAutoSkip => 'Werbung automatisch überspringen';

  @override
  String get settingsDisconnectTitle => 'Trennen?';

  @override
  String get settingsDisconnectBody =>
      'Du wirst abgemeldet und musst deine Anmeldedaten erneut eingeben, um dich wieder zu verbinden.';

  @override
  String get settingsDisconnectConfirm => 'Trennen';

  @override
  String get settingsApp => 'App';

  @override
  String get settingsAppVersion => 'Version';

  @override
  String get settingsAppUpdateStatus => 'Update';

  @override
  String get settingsAppVersionChecking => 'Suche nach Updates…';

  @override
  String get settingsAppUpToDate => 'Aktuell';

  @override
  String settingsAppUpdateAvailable(String version) {
    return 'Update verfügbar: $version';
  }

  @override
  String get settingsAppViewRelease => 'Release ansehen';

  @override
  String get settingsAppScanQr => 'Scannen, um auf deinem Handy zu öffnen';

  @override
  String get settingsFillAllFields => 'Bitte fülle alle Felder aus';

  @override
  String get settingsConnectionSettings => 'Verbindungseinstellungen';

  @override
  String get settingsConnectionSettingsSubtitle =>
      'Gib deine Xtream-Codes-Daten ein';

  @override
  String get settingsConnectionSettingsHelp =>
      'Verwende die Xtream-Verbindungsdaten der Playlist aus m3u-editor, nicht deinen m3u-editor-Web-Login. Du benoetigst die Server-URL, den Xtream-Benutzernamen und das Xtream-Passwort.';

  @override
  String get settingsServerUrl => 'Server-URL';

  @override
  String get settingsUsername => 'Benutzername';

  @override
  String get settingsPassword => 'Passwort';

  @override
  String get settingsConnect => 'Verbinden';

  @override
  String get settingsPairWithCode => 'Mit Code koppeln';

  @override
  String get settingsTabPair => 'Koppeln';

  @override
  String get settingsTabSignIn => 'Anmelden';

  @override
  String get settingsPairTabSubtitle =>
      'Gib deine Serveradresse ein und koppele diesen Fernseher dann mit einem Code.';

  @override
  String get pairingEnterServerFirst => 'Gib zuerst deine Server-URL ein';

  @override
  String get pairingErrorGeneric =>
      'Kopplung fehlgeschlagen oder der Code ist abgelaufen. Bitte versuche es erneut.';

  @override
  String get pairingScanQr =>
      'Scanne, um die Kopplungsseite auf deinem Handy zu öffnen';

  @override
  String get pairingOpenBrowser => 'Im Browser öffnen';

  @override
  String get pairingPendingGoTo => 'Gehe auf deinem Telefon oder Computer zu:';

  @override
  String get pairingPendingEnterCode => 'Kopplungscode:';

  @override
  String get pairingPendingWaiting => 'Warte auf Bestätigung…';

  @override
  String get homeContinueWatching => 'Weiterschauen';

  @override
  String get homeNoContinueWatching => 'Nichts zum Weiterschauen';

  @override
  String get homeContinueWatchingSeeAll => 'Alle anzeigen';

  @override
  String homeContinueWatchingMoreCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count weitere',
      one: '+1 weitere',
    );
    return '$_temp0';
  }

  @override
  String get homeUpNext => 'Als Nächstes';

  @override
  String get homeNoLiveTv => 'Kein Live-TV verfügbar';

  @override
  String get homeFavoriteChannels => 'Lieblingssender';

  @override
  String get homeNoFavoriteChannels => 'Keine Lieblingssender verfügbar';

  @override
  String get homeNoMovies => 'Keine Filme verfügbar';

  @override
  String get homeLiveChannel => 'Live-Sender';

  @override
  String get homeMovie => 'Film';

  @override
  String get notificationsTitle => 'Mitteilungen';

  @override
  String get notificationsTabNotifications => 'Mitteilungen';

  @override
  String get notificationsTabChannelSettings => 'Kanaleinstellungen';

  @override
  String get notificationsMarkAllRead => 'Alle als gelesen markieren';

  @override
  String get notificationsEmpty => 'Noch keine Benachrichtigungen';

  @override
  String get notificationsEmptyFiltered =>
      'Keine Benachrichtigungen für deine abonnierten Kanäle';

  @override
  String get notificationsChannelSubscriptions => 'Kanalabonnements';

  @override
  String get notificationsChannelSubtitle =>
      'Wähle aus, welche Kanäle du empfangen möchtest. Lasse alle deaktiviert, um alles zu empfangen.';

  @override
  String get notificationsAllChannels => 'Alle Kanäle';

  @override
  String get notificationsNoChannels =>
      'Noch keine Kanäle — sie erscheinen hier, wenn Benachrichtigungen eingehen.';

  @override
  String get notificationsJustNow => 'gerade eben';

  @override
  String notificationsMinutesAgo(int count) {
    return 'vor $count Min';
  }

  @override
  String notificationsHoursAgo(int count) {
    return 'vor $count Std';
  }

  @override
  String notificationsDaysAgo(int count) {
    return 'vor $count T';
  }

  @override
  String notificationsReceivedAt(String time) {
    return 'Empfangen $time';
  }

  @override
  String notificationsReadAt(String time) {
    return 'Gelesen $time';
  }

  @override
  String get homeNoSeries => 'Keine Serien verfügbar';

  @override
  String homeSeason(int number) {
    return 'Staffel $number';
  }

  @override
  String get seriesSeasons => 'Staffeln';

  @override
  String seriesEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Folgen',
      one: '1 Folge',
    );
    return '$_temp0';
  }

  @override
  String seriesPlayEpisode(int season, int episode) {
    return 'S${season}E$episode abspielen';
  }

  @override
  String seriesResumeEpisode(int season, int episode) {
    return 'S${season}E$episode fortsetzen';
  }

  @override
  String get seriesMarkWatched => 'Als gesehen markieren';

  @override
  String get seriesMarkUnwatched => 'Als ungesehen markieren';

  @override
  String get seriesMarkedWatched => 'Als gesehen markiert';

  @override
  String get seriesMarkedUnwatched => 'Als ungesehen markiert';

  @override
  String get seriesMarkSyncFailed =>
      'Gesehen-Status konnte nicht synchronisiert werden';

  @override
  String seriesMarkSeasonPrompt(int number) {
    return 'Den Gesehen-Status für jede Folge von Staffel $number aktualisieren?';
  }

  @override
  String get traktWatchHistory => 'Wiedergabeverlauf';

  @override
  String get traktWatchHistorySubtitle =>
      'Synchronisiere deinen Wiedergabeverlauf mit Trakt, um den Fortschritt über Apps und Dienste hinweg zu verfolgen.';

  @override
  String get traktNotConfigured =>
      'Trakt-Client-Anmeldedaten sind nicht konfiguriert.';

  @override
  String get traktNotConfiguredHint =>
      'Registriere eine App auf trakt.tv/oauth/applications und setze Client-ID und Secret via --dart-define zur Build-Zeit.';

  @override
  String get traktConnectPrompt =>
      'Verbinde deinen Trakt-Account, um automatisch zu verfolgen, was du schaust.';

  @override
  String get traktConnectButton => 'Mit Trakt verbinden';

  @override
  String get traktScanQr => 'Scannen, um auf deinem Handy zu öffnen';

  @override
  String get traktOpenBrowser => 'Im Browser öffnen';

  @override
  String get traktPendingGoTo => 'Gehe auf deinem Telefon oder Computer zu:';

  @override
  String get traktPendingEnterCode => 'Gib dann diesen Code ein:';

  @override
  String get traktPendingWaiting => 'Warte auf Autorisierung…';

  @override
  String get traktConnected => 'Mit Trakt verbunden';

  @override
  String get traktDisconnectButton => 'Trakt trennen';

  @override
  String get vodAllMovies => 'Alle Filme';

  @override
  String get seriesAllSeries => 'Alle Serien';

  @override
  String homeConnectedSource(String label) {
    return 'Verbundene Quelle: $label';
  }

  @override
  String get searchTypeToSearch => 'Zum Suchen tippen';

  @override
  String get vodPlayMovie => 'Film abspielen';

  @override
  String get vodContinueMovie => 'Film fortsetzen';

  @override
  String vodTimeLeftMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'noch $minutes Min.',
      one: 'noch 1 Min.',
    );
    return '$_temp0';
  }

  @override
  String vodTimeLeftHoursMinutes(int hours, int minutes) {
    return 'noch $hours Std. $minutes Min.';
  }

  @override
  String get navAioStreams => 'AIOStreams';

  @override
  String get aiostreamsGetStreams => 'Streams laden';

  @override
  String get aiostreamsLoadingStreams => 'Streams werden geladen…';

  @override
  String get aiostreamsNoStreams => 'Keine Streams gefunden';

  @override
  String get aiostreamsSelectStream => 'Stream auswählen';

  @override
  String get aiostreamsLoadMore => 'Mehr laden';

  @override
  String get aiostreamsSearchHint => 'Filme & Serien suchen…';

  @override
  String get aiostrreamsCatalogEmpty => 'Noch nichts vorhanden';

  @override
  String get aiostreamsToggleFavorite => 'Favorit';

  @override
  String get aiostreamsMyFavorites => 'Meine Favoriten';

  @override
  String get aiostreamsContinueWatching => 'Weiterschauen';

  @override
  String get aiostreamsSearch => 'AIOStreams durchsuchen';

  @override
  String get aiostreamsSearchResults => 'Suchergebnisse';

  @override
  String get aiostreamsNoResults => 'Keine Ergebnisse gefunden';

  @override
  String get aiostreamsSearchAll => 'Alle';

  @override
  String get requestsTitle => 'Anfragen';

  @override
  String get requestsTabSearch => 'Suche';

  @override
  String get requestsTabMyRequests => 'Meine Anfragen';

  @override
  String get requestsSearchHint => 'Suchen …';

  @override
  String get requestsNoResults => 'Keine Ergebnisse gefunden';

  @override
  String get requestsAlreadyAvailable => 'Bereits verfügbar';

  @override
  String get requestsAlreadyRequested => 'Bereits angefragt';

  @override
  String get requestsRequestButton => 'Anfragen';

  @override
  String get requestsSeasonsHeading => 'Staffeln';

  @override
  String get requestsSeasonSpecials => 'Specials';

  @override
  String get requestsSelectAllSeasons => 'Alle auswählen';

  @override
  String get requestsClearSeasons => 'Zurücksetzen';

  @override
  String requestsSubmitted(String title) {
    return '\"$title\" wurde angefragt';
  }

  @override
  String requestsSubmittedPendingApproval(String title) {
    return '\"$title\" wurde zur Genehmigung gesendet';
  }

  @override
  String requestsSubmitFailed(String title, String error) {
    return '\"$title\" konnte nicht angefragt werden: $error';
  }

  @override
  String get requestsMyRequestsEmpty => 'Du hast noch nichts angefragt';

  @override
  String get requestsDismiss => 'Verwerfen';

  @override
  String requestsDismissFailed(String error) {
    return 'Anfrage konnte nicht verworfen werden: $error';
  }

  @override
  String get requestsStatusPendingApproval => 'Ausstehende Genehmigung';

  @override
  String get requestsStatusApproved => 'Genehmigt';

  @override
  String get requestsStatusRejected => 'Abgelehnt';

  @override
  String get requestsStatusCompleted => 'Abgeschlossen';

  @override
  String get requestsStatusUnknown => 'Unbekannt';

  @override
  String get dvrRecordingsTitle => 'DVR-Aufnahmen';

  @override
  String get dvrRecordingsSubtitle => 'Abgeschlossene und laufende Aufnahmen';

  @override
  String get dvrNoRecordings => 'Keine DVR-Aufnahmen verfügbar';

  @override
  String get dvrNotConfigured =>
      'Bitte verbinde dich in den Einstellungen mit deinem Dienst';

  @override
  String get dvrCancel => 'Abbrechen';

  @override
  String get dvrDelete => 'Löschen';

  @override
  String dvrStopTitle(String title) {
    return 'Aufnahme stoppen — $title';
  }

  @override
  String get dvrStopMessage =>
      'In der Aufnahmeliste behalten oder jetzt löschen?';

  @override
  String get dvrStopKeep => 'Aufnahme behalten';

  @override
  String get dvrStopDelete => 'Aufnahme löschen';

  @override
  String get dvrStopBack => 'Zurück';

  @override
  String get dvrCancelSuccess => 'Aufnahme abgebrochen';

  @override
  String get dvrCancelFailed => 'Aufnahme konnte nicht abgebrochen werden';

  @override
  String get dvrDeleteTitle => 'Aufnahme löschen?';

  @override
  String get dvrDeleteMessage => 'Diese Aufnahme wird dauerhaft gelöscht.';

  @override
  String get dvrDeleteDismiss => 'Behalten';

  @override
  String get dvrDeleteConfirm => 'Aufnahme löschen';

  @override
  String get dvrDeleteSuccess => 'Aufnahme gelöscht';

  @override
  String get dvrDeleteFailed => 'Aufnahme konnte nicht gelöscht werden';

  @override
  String get liveTvStopRecording => 'Aufnahme stoppen';

  @override
  String get playerRecordNowTooltip => 'Aktuelle Sendung aufnehmen';

  @override
  String get playerStopRecordingTooltip => 'Aufnahme stoppen';

  @override
  String get dvrMoreActions => 'Weitere Aktionen';

  @override
  String get dvrPlay => 'Abspielen';

  @override
  String get dvrSelect => 'Auswählen';

  @override
  String get dvrStop => 'Stoppen';

  @override
  String get dvrStatusRecording => 'Aufnahme läuft';

  @override
  String get dvrStatusScheduled => 'Geplant';

  @override
  String get dvrStatusFailed => 'Fehlgeschlagen';

  @override
  String get dvrExitSelection => 'Auswahl beenden';

  @override
  String dvrSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente ausgewählt',
      one: '1 Element ausgewählt',
      zero: 'Keine Elemente ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get dvrStorageTitle => 'DVR-Speicher';

  @override
  String get dvrStorageUnlimited => 'Unbegrenzt';

  @override
  String dvrStorageUsedUnlimited(String used) {
    return '$used belegt';
  }

  @override
  String dvrStorageUsedWithQuota(String used, String quota) {
    return '$used von $quota belegt';
  }

  @override
  String dvrStorageRecordingCount(int count) {
    return '$count Aufnahmen';
  }

  @override
  String get dvrSeriesChannel => 'Sender';

  @override
  String get dvrSeriesStartEarly => 'Früh starten';

  @override
  String get dvrSeriesUseDefault => 'Standard';

  @override
  String dvrEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Folgen',
      one: '1 Folge',
    );
    return '$_temp0';
  }

  @override
  String get dvrDeleteSeriesRule => 'Regel löschen';

  @override
  String get dvrEditSeriesRule => 'Regel bearbeiten';

  @override
  String get dvrUpdateSeriesRuleFailed =>
      'Serien-Regel konnte nicht aktualisiert werden';

  @override
  String get dvrSeriesSave => 'Speichern';

  @override
  String get dvrSeriesSecondsSuffix => 'Sek';

  @override
  String get dvrSeriesMode => 'Serienmodus';

  @override
  String get dvrUpdateSeriesRuleSuccess => 'Serien-Regel aktualisiert';

  @override
  String get dvrSeriesModeAll => 'Alle Episoden';

  @override
  String get dvrSeriesMatchModeStartsWith => 'Beginnt mit';

  @override
  String get dvrDeleteSeriesRuleConfirm => 'Diese Serien-Regel löschen?';

  @override
  String get dvrSeriesCancel => 'Abbrechen';

  @override
  String get dvrDeleteSeriesRuleSuccess => 'Serien-Regel gelöscht';

  @override
  String get dvrSeriesRulesTitle => 'Serien-Regeln';

  @override
  String get dvrSeriesMatchModeContains => 'Enthält';

  @override
  String get dvrSeriesMatchModeExact => 'Genau';

  @override
  String get dvrSeriesModeUseDefault => 'Standard';

  @override
  String get dvrSeriesModeNewFlag => 'Nur Neue';

  @override
  String get dvrDeleteSeriesRuleFailed =>
      'Serien-Regel konnte nicht gelöscht werden';

  @override
  String get dvrSeriesKeepLast => 'Letzte behalten';

  @override
  String get dvrSeriesModeUniqueSe => 'Eindeutige S-E';

  @override
  String get dvrSeriesAnyChannel => 'Beliebiger Sender';

  @override
  String get dvrSeriesMatchMode => 'Übereinstimmungsmodus';

  @override
  String get dvrSeriesEndLate => 'Spät beenden';

  @override
  String get dvrSeriesOptions => 'Optionen';

  @override
  String dvrSeriesOptionsFor(String title) {
    return 'Optionen: $title';
  }

  @override
  String get dvrSeriesAllEpisodesWarning =>
      'Aufnahme aller Folgen auf jedem Sender kann Duplikate erzeugen — Nutze „Neue nur\" oder „Eindeutige S-E\" zum Deduplizieren.';

  @override
  String get dvrSeriesRulesEmpty => 'Keine Serien-Regeln';

  @override
  String get dvrSeriesPriority => 'Priorität';

  @override
  String get epgRecordSeries => 'Serie aufnehmen';

  @override
  String epgRecordSeriesSuccess(String title) {
    return 'Serienaufnahme für $title aktiviert';
  }

  @override
  String get epgRecordSeriesFailed =>
      'Serienaufnahme konnte nicht aktiviert werden';

  @override
  String get epgRecordSeriesDuplicate => 'Serienaufnahme bereits aktiv';

  @override
  String get navShows => 'Shows';

  @override
  String get showAiringNext => 'Nächste Ausstrahlung';

  @override
  String get showAiringNone => 'Keine kommenden Folgen im EPG';

  @override
  String showChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sender',
      one: '1 Sender',
    );
    return '$_temp0';
  }

  @override
  String get showDeleteRule => 'Serien-Regel löschen';

  @override
  String showDeleteRuleConfirm(String title) {
    return 'Serien-Regel für $title löschen? Zukünftige Folgen werden nicht aufgenommen. Bereits vorhandene Aufnahmen werden nicht gelöscht.';
  }

  @override
  String get showSeriesRuleActive => 'Serien-Regel aktiv';

  @override
  String get showScheduled => 'Geplant';

  @override
  String showBatchRecord(int count) {
    return 'Aufnehmen ($count)';
  }

  @override
  String showBatchScheduleSummary(int scheduled, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      scheduled,
      locale: localeName,
      other: '$scheduled Folgen aufgenommen',
      one: '1 Folge aufgenommen',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed fehlgeschlagen.',
      one: '1 fehlgeschlagen.',
      zero: 'Alle erfolgreich.',
    );
    return '$_temp0. $_temp1';
  }

  @override
  String showBatchScheduleFailures(String titles) {
    return 'Fehlgeschlagen: $titles';
  }

  @override
  String get showDetailTitle => 'Show-Details';

  @override
  String showEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Folgen',
      one: '1 Folge',
    );
    return '$_temp0';
  }

  @override
  String get showRecordSeries => 'Serie aufnehmen';

  @override
  String showRecordSeriesConfirm(String title, String channel) {
    return 'Jede Folge von $title auf $channel aufnehmen?';
  }

  @override
  String showRecordSeriesFailed(String title) {
    return 'Serienaufnahme für $title konnte nicht aktiviert werden';
  }

  @override
  String showRecordSeriesSuccess(String title) {
    return 'Serienaufnahme für $title aktiviert';
  }

  @override
  String showRecordSeriesDuplicate(String title) {
    return 'Serienaufnahme für $title bereits aktiv';
  }

  @override
  String get showsError => 'Shows konnten nicht durchsucht werden';

  @override
  String get showsNoResults => 'Keine Shows entsprechen deiner Suche';

  @override
  String get showsSearchError => 'Suche fehlgeschlagen';

  @override
  String get showsSearchHint => 'Shows nach Titel suchen';

  @override
  String get showsTitle => 'Shows';

  @override
  String showNotFound(String title) {
    return 'Show „$title\" nicht gefunden';
  }

  @override
  String get settingsView => 'Ansicht';

  @override
  String get settingsLiveTvLayout => 'Live-TV-Layout';

  @override
  String get settingsLiveTvLayoutList => 'Liste';

  @override
  String get settingsLiveTvLayoutGrid => 'Raster';

  @override
  String get settingsLiveTvLayoutTimeline => 'Zeitleiste';

  @override
  String get settingsLiveTvChannelColumn => 'Kanalspalte';

  @override
  String get settingsLiveTvChannelColumnLogoTitle => 'Logo + Titel';

  @override
  String get settingsLiveTvChannelColumnLogoOnly => 'Nur Logo';

  @override
  String get settingsLiveTvChannelColumnTitleOnly => 'Nur Titel';

  @override
  String get settingsEpgStartView => 'EPG startet um';

  @override
  String get settingsEpgStartViewCurrentTime => 'Aktuelle Uhrzeit';

  @override
  String get settingsEpgStartViewPrimeTime => 'Prime Time';

  @override
  String get settingsDefaultStartPage => 'Standardstartseite';

  @override
  String get settingsHdrMode => 'HDR-Modus';

  @override
  String get settingsHdrModeHint =>
      'HDR-Videos dürfen das Display in den HDR-Modus schalten. Nur Windows und Linux.';

  @override
  String get settingsMatchRefreshRate => 'Bildwiederholrate anpassen';

  @override
  String get settingsMatchRefreshRateHint =>
      'Schaltet den Monitor beim Start der Wiedergabe auf die Bildrate des Videos. Kann den Bildschirm kurz schwarz werden lassen. Nur Windows.';

  @override
  String get settingsToggleOn => 'Ein';

  @override
  String get settingsToggleOff => 'Aus';
}
