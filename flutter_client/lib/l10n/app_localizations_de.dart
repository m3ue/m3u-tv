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
  String get liveTvSearchHint => 'Live-TV durchsuchen …';

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
  String get liveTvFavorite => 'Favorit';

  @override
  String get liveTvRemoveFavorite => 'Aus Favoriten entfernen';

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
  String get searchHint => 'Live-TV, Filme und Serien durchsuchen …';

  @override
  String get searchSectionLiveTv => 'Live-TV';

  @override
  String get searchSectionMovies => 'Filme';

  @override
  String get searchSectionSeries => 'Serien';

  @override
  String get vodSearchHint => 'Filme durchsuchen …';

  @override
  String get seriesSearchHint => 'Serien durchsuchen …';

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
  String get settingsDisconnectTitle => 'Trennen?';

  @override
  String get settingsDisconnectBody =>
      'Du wirst abgemeldet und musst deine Anmeldedaten erneut eingeben, um dich wieder zu verbinden.';

  @override
  String get settingsDisconnectConfirm => 'Trennen';

  @override
  String get homeContinueWatching => 'Weiterschauen';

  @override
  String get homeNoContinueWatching => 'Nichts zum Weiterschauen';

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
}
