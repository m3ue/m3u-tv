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
  String get appRecordingScheduling => 'Aufnahme wird geplant…';

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
  String get mediaCategorySortButton => 'Sortieren';

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
  String get epgToday => 'Heute';

  @override
  String get epgTomorrow => 'Morgen';

  @override
  String get epgYesterday => 'Gestern';

  @override
  String get epgLiveBadge => 'LIVE';

  @override
  String get epgReplayBadge => 'NACHSEHEN';

  @override
  String get epgBadgeNew => 'NEU';

  @override
  String get epgBadgePremiere => 'PREMIERE';

  @override
  String get epgBadgeRepeat => 'WIEDERHOLUNG';

  @override
  String epgSeasonEpisode(int season, int episode) {
    return 'S$season F$episode';
  }

  @override
  String epgSeasonNumber(int season) {
    return 'Staffel $season';
  }

  @override
  String epgEpisodeNumber(int episode) {
    return 'Folge $episode';
  }

  @override
  String epgDurationMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String epgDurationHours(int hours) {
    return '$hours Std.';
  }

  @override
  String epgDurationHoursMinutes(int hours, int minutes) {
    return '$hours Std. $minutes Min.';
  }

  @override
  String epgTimeLeft(String duration) {
    return 'Noch $duration';
  }

  @override
  String epgStartsIn(String duration) {
    return 'Beginnt in $duration';
  }

  @override
  String get epgEnded => 'Beendet';

  @override
  String get epgWatchLive => 'Live ansehen';

  @override
  String get epgPreview => 'Vorschau';

  @override
  String get epgWatchReplay => 'Nachsehen';

  @override
  String get epgMoreOptions => 'Weitere Optionen';

  @override
  String get epgKeyOk => 'OK';

  @override
  String get epgKeyHoldOk => 'OK halten';

  @override
  String get epgSweepLoadingTitle => 'Programmführer wird geladen';

  @override
  String epgSweepLoadingBody(int loaded, int total) {
    return '$loaded von $total Sendern';
  }

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
  String get playerPlay => 'Abspielen';

  @override
  String get playerResume => 'Fortsetzen';

  @override
  String get playerClearProgress => 'Fortschritt löschen';

  @override
  String get playerProgressCleared => 'Fortschritt gelöscht';

  @override
  String get playerSkipPreviousTooltip => 'Vorheriger Sender';

  @override
  String get playerSkipNextTooltip => 'Nächster Sender';

  @override
  String get playerEpisodesTooltip => 'Episoden';

  @override
  String get playerEpisodePickerTitle => 'Episoden';

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
  String playerEndsAt(String time) {
    return 'Endet um $time';
  }

  @override
  String get playerUpNextPlay => 'Nächste Folge';

  @override
  String get playerUpNextDismiss => 'Schließen';

  @override
  String get playerLiveStreamEnded => 'Übertragung beendet';

  @override
  String get playerReturningToMenu => 'Rückkehr zum Menü…';

  @override
  String get playerLoadingStream => 'Stream wird geladen…';

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
  String get settingsGeneralSubtitle => 'Sprache, Verbindung und Konto';

  @override
  String get settingsIntegrations => 'Integrationen';

  @override
  String get settingsIntegrationsSubtitle => 'SIMKL, TheIntroDB und mehr';

  @override
  String get settingsAppearance => 'Erscheinungsbild';

  @override
  String get settingsAppearanceSubtitle => 'Layout, EPG und Anzeige';

  @override
  String get settingsPlayback => 'Wiedergabe';

  @override
  String get settingsPlaybackSubtitle => 'Player, Proxy und DVR';

  @override
  String get settingsReleaseNotesSubtitle => 'Neuigkeiten in dieser Version';

  @override
  String get settingsSectionLanguageRegion => 'Sprache & Region';

  @override
  String get settingsSectionLayout => 'Layout';

  @override
  String get settingsSectionDisplay => 'Anzeige';

  @override
  String get settingsSectionFilters => 'Filter';

  @override
  String get settingsSectionStreaming => 'Streaming';

  @override
  String get settingsSectionLiveTv => 'Live-TV';

  @override
  String get settingsSectionServices => 'Dienste';

  @override
  String get settingsIntroDb => 'TheIntroDB';

  @override
  String get settingsIntroDbSubtitle =>
      'Zeigt Intro überspringen und Abspann überspringen anhand von Community-Zeitstempeln';

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
  String get settingsClearCacheConfirm => 'Löschen und aktualisieren';

  @override
  String get settingsCacheCleared =>
      'Cache geleert. Inhalte werden im Hintergrund aktualisiert.';

  @override
  String get settingsClearCacheEpgHint =>
      'Der aktuelle Programmführer bleibt beim Neuladen sichtbar';

  @override
  String get settingsClearCacheImagesHint =>
      'Poster und Logos werden beim Durchsuchen neu geladen';

  @override
  String get settingsEpgCacheCleared =>
      'Programmdaten werden im Hintergrund aktualisiert.';

  @override
  String get settingsImageCacheCleared => 'Bild-Cache geleert.';

  @override
  String get settingsCacheSubtitle =>
      'Gecachte Inhalte laden sofort. Daten werden automatisch im Hintergrund aktualisiert.';

  @override
  String get settingsStorage => 'Speicher';

  @override
  String get settingsStorageSubtitle =>
      'Gespeicherte Playlists, Programmführer und Bilder';

  @override
  String get settingsStorageTotal => 'Gesamt';

  @override
  String get settingsStorageGuide => 'Programmführer';

  @override
  String get settingsStorageArtwork => 'Bilder';

  @override
  String get settingsStorageCalculating => 'Wird berechnet...';

  @override
  String get settingsStorageUnavailable => 'Nicht verfügbar';

  @override
  String settingsStorageItems(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String get settingsStorageNotStored => 'Nicht auf diesem Gerät gespeichert';

  @override
  String get settingsStorageKeepPlaylists =>
      'Auf diesem Gerät behaltene Playlists';

  @override
  String settingsStorageKeepPlaylistsValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Die $count zuletzt genutzten',
      one: 'Nur die aktive Playlist',
    );
    return '$_temp0';
  }

  @override
  String get settingsStorageClearPlaylistTitle =>
      'Gespeicherte Inhalte löschen?';

  @override
  String settingsStorageClearPlaylistBody(String name) {
    return 'Kanäle, Filme, Serien und Programmführer von $name werden von diesem Gerät entfernt. Sie werden beim nächsten Wechsel zu dieser Playlist neu geladen.';
  }

  @override
  String settingsStorageClearActiveBody(String name) {
    return 'Kanäle, Filme und Serien von $name werden entfernt und jetzt neu geladen.';
  }

  @override
  String get settingsStorageClear => 'Löschen';

  @override
  String get settingsStorageCleared => 'Gespeicherte Inhalte gelöscht.';

  @override
  String get settingsStorageGuideData => 'Programmdaten';

  @override
  String settingsStorageProgrammes(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Sendungen',
      one: '1 Sendung',
    );
    return '$_temp0';
  }

  @override
  String get settingsStorageClearGuideTitle => 'Programmdaten aktualisieren?';

  @override
  String get settingsStorageArtworkCache => 'Bilder-Cache';

  @override
  String get settingsStorageClearArtworkTitle => 'Bilder löschen?';

  @override
  String get settingsStorageClearAll => 'Alles löschen';

  @override
  String get settingsStorageClearAllBody =>
      'Die gespeicherten Inhalte der anderen Playlists und alle Bilder werden entfernt. Kanäle, Filme, Serien und Programmführer der aktiven Playlist werden jetzt neu geladen.';

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
  String get settingsPlaylists => 'Playlists';

  @override
  String get settingsPlaylistActive => 'Aktive Playlist';

  @override
  String get settingsAddPlaylist => 'Playlist hinzufügen';

  @override
  String get settingsSwitchPlaylist => 'Zu dieser Playlist wechseln';

  @override
  String get settingsRenamePlaylist => 'Playlist umbenennen';

  @override
  String get settingsRemovePlaylist => 'Playlist entfernen';

  @override
  String get settingsRemovePlaylistTitle => 'Playlist entfernen?';

  @override
  String settingsRemovePlaylistBody(String name) {
    return '$name wird von diesem Gerät entfernt. Du kannst sie jederzeit wieder hinzufügen.';
  }

  @override
  String get settingsDisconnectBodyOtherPlaylists =>
      'Du wirst von dieser Playlist abgemeldet und sie wird von diesem Gerät entfernt. Deine anderen gespeicherten Playlists bleiben zum erneuten Verbinden verfügbar.';

  @override
  String get settingsPlaylistNameLabel => 'Name';

  @override
  String get settingsSave => 'Speichern';

  @override
  String settingsSwitchPlaylistFailed(String error) {
    return 'Playlist konnte nicht gewechselt werden: $error';
  }

  @override
  String get settingsTabSaved => 'Gespeichert';

  @override
  String get settingsSavedPlaylistsTitle => 'Gespeicherte Playlists';

  @override
  String get settingsSavedPlaylistsSubtitle =>
      'Verbinde dich wieder mit einer auf diesem Gerät gespeicherten Playlist oder füge über Koppeln oder Anmelden eine neue hinzu.';

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
  String get settingsAppUpdateNoticeTitle => 'App-Update verfügbar';

  @override
  String settingsAppUpdateNoticeBody(String version) {
    return 'Version $version kann installiert werden.';
  }

  @override
  String get settingsAppViewRelease => 'Release ansehen';

  @override
  String get settingsAppScanQr => 'Scannen, um auf deinem Handy zu öffnen';

  @override
  String get settingsReleaseNotesTab => 'Neuigkeiten';

  @override
  String get settingsReleaseNotesLoading => 'Versionshinweise werden geladen…';

  @override
  String get settingsReleaseNotesError =>
      'Versionshinweise konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get settingsReleaseNotesRetry => 'Erneut versuchen';

  @override
  String get settingsReleaseNotesCurrentBadge => 'Aktuell';

  @override
  String get settingsReleaseNotesNewBadge => 'Neu';

  @override
  String settingsReleaseNotesYouAreOn(String version) {
    return 'Du nutzt $version';
  }

  @override
  String settingsReleaseNotesNewerCount(int count) {
    return '$count neuere';
  }

  @override
  String get settingsReleaseNotesUpToDate => 'Du nutzt die neueste Version';

  @override
  String get settingsReleaseNotesViewOnGithub => 'Alle auf GitHub ansehen';

  @override
  String get settingsReleaseNotesNoneForVersion =>
      'Keine Hinweise für diese Version.';

  @override
  String get settingsReleaseNotesSelectVersion => 'Version auswählen';

  @override
  String settingsReleaseNotesFeatureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Funktionen',
      one: '1 Funktion',
    );
    return '$_temp0';
  }

  @override
  String settingsReleaseNotesFixCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fehlerbehebungen',
      one: '1 Fehlerbehebung',
    );
    return '$_temp0';
  }

  @override
  String get settingsReleaseNotesOlder => 'Ältere Version';

  @override
  String get settingsReleaseNotesNewer => 'Neuere Version';

  @override
  String get settingsReleaseNotesHintVersions => 'Version wechseln';

  @override
  String get settingsReleaseNotesHintScroll => 'Scrollen';

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
  String get settingsServerUrlLocked => 'Verwendet den Server dieser App';

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
  String get pairingCopyCode => 'Code kopieren';

  @override
  String get pairingCodeCopied => 'Kopiert';

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
  String get homeViewAll => 'Alle anzeigen';

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
  String get continueWatchingItemUnavailable =>
      'Dieser Titel ist nicht mehr verfügbar';

  @override
  String get homeNoLiveTv => 'Kein Live-TV verfügbar';

  @override
  String get homeFavoriteChannels => 'Lieblingssender';

  @override
  String get homeNoFavoriteChannels => 'Keine Lieblingssender verfügbar';

  @override
  String get homeNoMovies => 'Keine Filme verfügbar';

  @override
  String get homeMovie => 'Film';

  @override
  String get homeBrowseLiveTv => 'Alle Sender durchsuchen';

  @override
  String get homeBrowseSports =>
      'Alle Spiele deiner Ligen, mit Live-Ergebnissen';

  @override
  String homeSportsStartsAt(String time) {
    return 'Beginnt um $time';
  }

  @override
  String homeSportsOnChannels(String channels) {
    return 'Auf $channels';
  }

  @override
  String get homeBrowseMovies => 'Alle Filme durchsuchen';

  @override
  String get homeBrowseSeries => 'Alle Serien durchsuchen';

  @override
  String get homeNothingToShow => 'Noch nichts anzuzeigen';

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
  String get homeDvrRecordings => 'DVR-Aufnahmen';

  @override
  String get homeDvrRecordingsBrowse =>
      'Abgeschlossene und laufende Aufnahmen durchsuchen';

  @override
  String homeSeason(int number) {
    return 'Staffel $number';
  }

  @override
  String get seriesSeasons => 'Staffeln';

  @override
  String get seriesCast => 'Besetzung';

  @override
  String get relatedTitle => 'Ähnliche Titel';

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
  String traktConnectedAs(String account) {
    return 'Mit Trakt verbunden als $account';
  }

  @override
  String get traktDisconnectButton => 'Trakt trennen';

  @override
  String get traktName => 'Trakt';

  @override
  String get simklName => 'Simkl';

  @override
  String serverWatchHistoryActive(String service) {
    return 'M3U Editor sendet den Wiedergabefortschritt dieses Logins an $service.';
  }

  @override
  String serverWatchHistoryActiveAs(String service, String account) {
    return 'M3U Editor sendet den Wiedergabefortschritt dieses Logins als $account an $service.';
  }

  @override
  String serverWatchHistoryOverrideHint(String service) {
    return 'Verbinde dich hier, um auf diesem Gerät stattdessen dein eigenes $service-Konto zu verwenden.';
  }

  @override
  String get serverWatchHistoryOverridden =>
      'Dieses Gerät sendet seine Wiedergabe stattdessen an das hier verbundene Konto. Trenne die Verbindung, um stattdessen das Serverkonto zu verwenden.';

  @override
  String get simklConnectPrompt =>
      'Verbinde deinen Simkl-Account, um automatisch zu verfolgen, was du schaust.';

  @override
  String get simklConnectButton => 'Mit Simkl verbinden';

  @override
  String get simklConnected => 'Mit Simkl verbunden';

  @override
  String simklConnectedAs(String account) {
    return 'Mit Simkl verbunden als $account';
  }

  @override
  String get simklDisconnectButton => 'Simkl trennen';

  @override
  String get simklNotConfigured => 'Simkl-Client-ID ist nicht konfiguriert.';

  @override
  String get simklNotConfiguredHint =>
      'Registriere eine App auf simkl.com/settings/developer und setze die Client-ID über --dart-define=SIMKL_CLIENT_ID.';

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
  String get vodCast => 'Besetzung';

  @override
  String get vodDirector => 'Regie';

  @override
  String get castShowAll => 'Alle Darsteller anzeigen';

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
  String get dvrRecordingsTitle => 'Aufnahmen';

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
  String get playerEnterFullscreen => 'Vollbild';

  @override
  String get playerExitFullscreen => 'Vollbild beenden';

  @override
  String get playerSeekUnavailableTranscoding =>
      'Spulen ist während der Transkodierung nicht verfügbar';

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
  String get dvrSeriesRulesTitle => 'Regeln';

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
  String get settingsEpgPreviewPlayback => 'Vorschau-Wiedergabe im Guide';

  @override
  String get settingsEpgPreviewPlaybackOff => 'Aus';

  @override
  String get settingsEpgPreviewPlaybackPauseToPlay =>
      'Nach kurzem Verweilen abspielen';

  @override
  String get settingsEpgPreviewPlaybackClickToPreview =>
      'Mit OK Vorschau starten';

  @override
  String get settingsEpgPreviewDelay => 'Vorschau-Verzögerung';

  @override
  String settingsEpgPreviewDelaySeconds(int count) {
    return '$count Sekunden';
  }

  @override
  String get settingsFilterPersistence => 'Filterpersistenz';

  @override
  String get settingsFilterPersistenceRemember => 'Merken';

  @override
  String get settingsFilterPersistenceReset => 'Bei jedem Start zurücksetzen';

  @override
  String get vodSortDialogTitle => 'Filme sortieren nach';

  @override
  String get seriesSortDialogTitle => 'Serien sortieren nach';

  @override
  String get mediaSortDefault => 'Standard';

  @override
  String get mediaSortRating => 'Bewertung';

  @override
  String get mediaSortReleaseDateNewest => 'Neueste zuerst';

  @override
  String get mediaSortReleaseDateOldest => 'Älteste zuerst';

  @override
  String get mediaSortTitleAsc => 'Titel (A-Z)';

  @override
  String get mediaSortTitleDesc => 'Titel (Z-A)';

  @override
  String get mediaSortFavoritesFirst => 'Favoriten zuerst';

  @override
  String get liveTvSortDialogTitle => 'Sender sortieren nach';

  @override
  String get channelSortPlaylistOrder => 'Playlist-Reihenfolge';

  @override
  String get channelSortChannelNumber => 'Kanalnummer';

  @override
  String get channelSortAlphabeticalAsc => 'Alphabetisch (A-Z)';

  @override
  String get channelSortAlphabeticalDesc => 'Alphabetisch (Z-A)';

  @override
  String get settingsDefaultStartPage => 'Standardstartseite';

  @override
  String get settingsHomeScreenStyle => 'Startbildschirm';

  @override
  String get settingsHomeScreenStyleSimplified => 'Vereinfacht';

  @override
  String get settingsHomeScreenStyleRich => 'Spotlight';

  @override
  String get settingsSectionPlayer => 'Player';

  @override
  String get settingsVodPlayer => 'Player für Filme und Serien';

  @override
  String get settingsVodPlayerExoPlayerFirst => 'Zuerst ExoPlayer versuchen';

  @override
  String get settingsVodPlayerMpv => 'mpv verwenden';

  @override
  String get settingsHdrMode => 'HDR-Modus';

  @override
  String get settingsHdrModeHint =>
      'HDR-Videos dürfen das Display in den HDR-Modus schalten. Nur Windows und Linux.';

  @override
  String get settingsMatchRefreshRate => 'Bildwiederholrate anpassen';

  @override
  String get settingsMatchRefreshRateHint =>
      'Schaltet das Display beim Start der Wiedergabe auf die Bildrate des Videos. Der Bildschirm kann dabei kurz flackern oder schwarz werden.';

  @override
  String get settingsDeinterlace => 'Video deinterlacen';

  @override
  String get settingsDeinterlaceHint =>
      'Glättet die Kammlinien bei Interlaced-Sendern (z. B. 1080i und 576i). Benötigt mehr CPU-Leistung.';

  @override
  String get settingsPrebufferLive => 'Live-Streams vor der Wiedergabe puffern';

  @override
  String get settingsPrebufferLiveHint =>
      'Wartet einige Sekunden Video ab, bevor ein Sender losläuft, damit ungleichmäßig ankommende Streams nicht ständig zum Puffern anhalten. Senderwechsel dauern dadurch einige Sekunden länger.';

  @override
  String get settingsNavigationSound => 'Navigationston';

  @override
  String get settingsNavigationSoundHint =>
      'Beim Bewegen des Fokus mit Fernbedienung oder Tastatur einen Klickton abspielen.';

  @override
  String get settingsToggleOn => 'Ein';

  @override
  String get settingsToggleOff => 'Aus';

  @override
  String get settingsOptimizeFor => 'Optimierung';

  @override
  String get settingsOptimizeForQuality => 'Qualität';

  @override
  String get settingsOptimizeForQualityHint =>
      'Schärfere Bilder, höherer Speicherverbrauch.';

  @override
  String get settingsOptimizeForSpeed => 'Geschwindigkeit';

  @override
  String get settingsOptimizeForSpeedHint =>
      'Schnelleres Laden, niedrigere Bildqualität.';

  @override
  String get settingsFontSize => 'Anzeigegröße';

  @override
  String get settingsFontSizeVerySmall => 'Sehr klein';

  @override
  String get settingsFontSizeSmall => 'Klein';

  @override
  String get settingsFontSizeNormal => 'Normal';

  @override
  String get settingsFontSizeLarge => 'Groß';

  @override
  String get settingsFontSizeVeryLarge => 'Sehr groß';

  @override
  String get personDetailsFilmography => 'Filmografie';

  @override
  String get personDetailsBioUnavailable => 'Keine Biografie verfügbar.';

  @override
  String get personDetailsEmpty => 'Keine Filmografie verfügbar.';

  @override
  String get personDetailsError =>
      'Die Filmografie konnte nicht geladen werden.';

  @override
  String get personDetailsFilterInLibrary => 'In der Bibliothek';

  @override
  String get personDetailsNoLibraryMatches =>
      'Nichts aus der Filmografie dieses Schauspielers ist in deiner Bibliothek.';

  @override
  String get settingsLogsDiagnostics => 'Protokolle & Diagnose';

  @override
  String get settingsLogsDiagnosticsSubtitle =>
      'Gerätedetails und Protokolle dieser Sitzung zur Fehlersuche';

  @override
  String get settingsPlaybackDiagnostics => 'Wiedergabediagnose anzeigen';

  @override
  String get settingsPlaybackDiagnosticsHint =>
      'Zeigt in den Player-Steuerelementen den aktiven Player und den Grund für einen Wechsel an, zur Fehlersuche.';

  @override
  String get diagnosticsUpload => 'Auf den Server hochladen';

  @override
  String get diagnosticsRefresh => 'Aktualisieren';

  @override
  String get diagnosticsClear => 'Protokolle löschen';

  @override
  String get diagnosticsUploading => 'Protokolle werden hochgeladen...';

  @override
  String diagnosticsUploaded(int id) {
    return 'Protokolle hochgeladen (#$id). Ein Admin kann sie in m3u-editor unter Geräte > Registrierte Geräte ansehen.';
  }

  @override
  String diagnosticsUploadFailed(String error) {
    return 'Protokolle konnten nicht hochgeladen werden: $error';
  }

  @override
  String get diagnosticsNotConnected =>
      'Verbinde dich mit einem Server, um Protokolle hochzuladen.';

  @override
  String get diagnosticsDeviceHeading => 'Gerät';

  @override
  String diagnosticsLogsHeading(int count) {
    return 'Protokolle ($count)';
  }

  @override
  String get diagnosticsNoLogs =>
      'In dieser Sitzung wurde noch nichts protokolliert.';

  @override
  String get trailerButton => 'Trailer';

  @override
  String trailerSeasonButton(int season) {
    return 'Trailer Staffel $season';
  }

  @override
  String get trailerWatch => 'Trailer ansehen';

  @override
  String get mediaSortRecentlyAdded => 'Kürzlich hinzugefügt';

  @override
  String get mediaSortRecentlyUpdated => 'Kürzlich aktualisiert';

  @override
  String get playerTrackAudio => 'Audio';

  @override
  String get playerTrackSubtitles => 'Untertitel';

  @override
  String get playerTrackAudioTitle => 'Tonspur';

  @override
  String get playerTrackSubtitleTitle => 'Untertitelspur';

  @override
  String get playerTrackAudioDisabled => 'Deaktivieren';

  @override
  String get playerTrackSubtitlesOff => 'Aus';

  @override
  String get playerOnlineSubtitlesSearch => 'Online suchen';

  @override
  String get playerOnlineSubtitlesTitle => 'Online-Untertitel';

  @override
  String get playerOnlineSubtitlesSearching => 'Untertitel werden gesucht…';

  @override
  String get playerOnlineSubtitlesLoading => 'Untertitel wird geladen…';

  @override
  String get playerOnlineSubtitlesEmpty =>
      'Für diesen Titel wurden keine Untertitel gefunden.';

  @override
  String get playerOnlineSubtitlesFailed =>
      'Untertitel konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get playerOnlineSubtitlesRetry => 'Erneut versuchen';

  @override
  String get playerOnlineSubtitlesAllLanguages => 'Alle Sprachen';

  @override
  String get settingsOnlineSubtitles => 'Online-Untertitel';

  @override
  String get settingsOnlineSubtitlesSubtitle =>
      'Finde Untertitel für Filme und Episoden über das Untertitelmenü des Players.';

  @override
  String get settingsOnlineSubtitlesAddress => 'Untertitelquelle';

  @override
  String get settingsOnlineSubtitlesAddressHint =>
      'Adresse des Stremio-Untertitel-Add-ons';

  @override
  String get settingsOnlineSubtitlesAddressInvalid =>
      'Gib eine gültige http- oder https-Adresse ein.';

  @override
  String get settingsOnlineSubtitlesUseDefault => 'Standard verwenden';

  @override
  String get playerHdrOn => 'HDR an';

  @override
  String get playerHdrOff => 'HDR aus';

  @override
  String get playerStartOver => 'Von vorne';

  @override
  String get playerDiagBackend => 'Backend';

  @override
  String get playerDiagFallback => 'Fallback';

  @override
  String get playerDiagCodec => 'Codec';

  @override
  String get playerDiagTranscode => 'Transkodierung';

  @override
  String get playerDiagCleanup => 'Bereinigung';

  @override
  String get metaWriter => 'Drehbuch';

  @override
  String get mediaClearSearch => 'Suche löschen';

  @override
  String seriesEpisodesLoadFailed(String error) {
    return 'Episoden konnten nicht geladen werden: $error';
  }

  @override
  String get seriesNoEpisodes => 'Keine Episoden verfügbar';

  @override
  String get settingsConnecting => 'Verbinde...';

  @override
  String get favoritesNoChannels => 'Keine Lieblingssender';

  @override
  String get favoritesNoMovies => 'Keine Lieblingsfilme';

  @override
  String get favoritesNoSeries => 'Keine Lieblingsserien';

  @override
  String get seriesLoadFailed => 'Serien konnten nicht geladen werden';

  @override
  String get vodLoadFailed => 'Filme konnten nicht geladen werden';

  @override
  String get vodNoSynopsis => 'Keine Inhaltsangabe verfügbar.';

  @override
  String get settingsConnectionFailed =>
      'Verbindung fehlgeschlagen. Bitte überprüfe deine Zugangsdaten.';

  @override
  String get settingsConnectingSubtitle =>
      'Bitte warte, während wir eine Verbindung zu deinem Dienst herstellen';

  @override
  String get settingsCreateViewerFailed =>
      'Zuschauer konnte nicht erstellt werden. Bitte versuche es erneut.';

  @override
  String get searchNoResults => 'Keine Ergebnisse gefunden';

  @override
  String get playerLoadTimedOut =>
      'Zeitüberschreitung beim Laden des Streams. Der Server ist möglicherweise nicht erreichbar oder die Stream-URL ist ungültig.';

  @override
  String get playerErrorTitle => 'Wiedergabefehler';

  @override
  String get navSports => 'Sport';

  @override
  String get sportsScopeAll => 'Alle Ligen';

  @override
  String get sportsScopeMyTeams => 'Meine Teams';

  @override
  String get sportsSearchHint => 'Teams suchen';

  @override
  String get sportsLeaguesButton => 'Ligen';

  @override
  String get sportsLeaguesTitle => 'Ligen anzeigen';

  @override
  String sportsLeaguesShownCount(int shown, int total) {
    return '$shown von $total angezeigt';
  }

  @override
  String get sportsDone => 'Fertig';

  @override
  String get sportsLiveNow => 'Jetzt live';

  @override
  String get sportsLiveBadge => 'LIVE';

  @override
  String get sportsFinal => 'Ende';

  @override
  String get sportsPostponed => 'Verschoben';

  @override
  String get sportsNoGames => 'Keine Spiele an diesem Tag';

  @override
  String get sportsNoLeagues =>
      'Keine Ligen ausgewählt. Wähle welche unter Ligen.';

  @override
  String get sportsMyTeamsEmpty =>
      'Du folgst noch keinen Teams. Wähle sie unter Teams aus oder halte ein Spiel gedrückt.';

  @override
  String get sportsMyTeamsNoGames => 'Keines deiner Teams spielt an diesem Tag';

  @override
  String sportsChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sender',
      one: '1 Sender',
    );
    return '$_temp0';
  }

  @override
  String get sportsNoChannel => 'Kein Sender';

  @override
  String get sportsEventChannel => 'Event-Sender';

  @override
  String get sportsWatch => 'Ansehen';

  @override
  String get sportsViewDetails => 'Spieldetails';

  @override
  String get sportsDetailsTitle => 'Spiel';

  @override
  String get sportsFollow => 'Folgen';

  @override
  String get sportsFollowing => 'Folge ich';

  @override
  String get sportsDetailsOnYourChannels => 'Auf deinen Kanälen';

  @override
  String get sportsDetailsLoadFailed =>
      'Spieldetails konnten nicht geladen werden. Neuer Versuch in Kürze.';

  @override
  String get sportsDetailsUnavailable =>
      'Für dieses Spiel sind noch keine weiteren Details verfügbar.';

  @override
  String get sportsDetailsLineScore => 'Punkte pro Abschnitt';

  @override
  String get sportsDetailsTotalShort => 'G';

  @override
  String get sportsDetailsEvents => 'Wichtige Momente';

  @override
  String get sportsDetailsStats => 'Teamstatistiken';

  @override
  String get sportsDetailsSeasonStats => 'Saisonstatistiken';

  @override
  String get sportsDetailsLeaders => 'Beste Spieler';

  @override
  String get sportsDetailsSeasonLeaders => 'Beste der Saison';

  @override
  String get sportsDetailsInfo => 'Spielinfos';

  @override
  String get sportsDetailsStart => 'Beginn';

  @override
  String get sportsDetailsVenue => 'Spielort';

  @override
  String get sportsDetailsAttendance => 'Zuschauer';

  @override
  String get sportsDetailsOfficials => 'Schiedsrichter';

  @override
  String get sportsDetailsSeries => 'Serie';

  @override
  String get sportsDetailsBroadcast => 'Übertragung';

  @override
  String sportsFollowTeam(String team) {
    return '$team folgen';
  }

  @override
  String sportsUnfollowTeam(String team) {
    return '$team nicht mehr folgen';
  }

  @override
  String sportsFollowingTeam(String team) {
    return 'Du folgst $team';
  }

  @override
  String sportsUnfollowedTeam(String team) {
    return 'Du folgst $team nicht mehr';
  }

  @override
  String sportsAddedToMultiview(String channel) {
    return '$channel zu Multiview hinzugefügt';
  }

  @override
  String sportsFixtureAt(String away, String home) {
    return '$away bei $home';
  }

  @override
  String sportsFixtureVs(String home, String away) {
    return '$home gegen $away';
  }

  @override
  String get sportsUnavailable =>
      'Sport ist auf diesem Server nicht aktiviert. Ein Admin kann es in M3U Editor unter Einstellungen > Integrationen > Sport aktivieren.';

  @override
  String get sportsLoadFailed =>
      'Spiele konnten nicht geladen werden. Neuer Versuch in Kürze.';

  @override
  String get sportsTeamsButton => 'Teams';

  @override
  String get sportsTeamsTitle => 'Wähle deine Teams';

  @override
  String get sportsTeamsLoadFailed =>
      'Teams konnten nicht geladen werden. Wähle die Liga erneut, um es noch einmal zu versuchen.';

  @override
  String get sportsNoTeams => 'Keine Teams gefunden';

  @override
  String get homeAioStreamsBrowse => 'Deine AIOStreams-Kataloge durchsuchen';

  @override
  String get homeRequestsBrowse => 'Filme und Serien suchen und anfragen';

  @override
  String get settingsNavLayout => 'Navigation & Startseite';

  @override
  String get settingsNavLayoutSubtitle =>
      'Bereiche in der Navigation und auf der Startseite anordnen oder ausblenden';

  @override
  String get settingsNavLayoutHintRemote =>
      'Drücke OK auf einer Zeile, um sie aufzunehmen, verschiebe sie mit Hoch und Runter und drücke zum Ablegen erneut OK. Zurück bricht ab.';

  @override
  String get settingsNavLayoutHintTouch =>
      'Ziehe eine Zeile am Griff, um sie zu verschieben.';

  @override
  String get settingsNavLayoutPinned =>
      'Startseite und Suche bleiben oben, Mitteilungen und Einstellungen bleiben unten, und Weiterschauen bleibt auf der Startseite an erster Stelle.';

  @override
  String get settingsNavLayoutColumnNav => 'Nav';

  @override
  String get settingsNavLayoutReset => 'Auf Standard zurücksetzen';

  @override
  String get settingsNavLayoutResetMessage =>
      'Dadurch werden die ursprüngliche Reihenfolge und Sichtbarkeit dieser Bereiche wiederhergestellt.';

  @override
  String get settingsNavLayoutResetConfirm => 'Zurücksetzen';

  @override
  String get dvrStatusProcessing => 'Wird verarbeitet';

  @override
  String get dvrStatusCompleted => 'Abgeschlossen';

  @override
  String get dvrStatusCancelled => 'Abgebrochen';

  @override
  String get dvrFilterAll => 'Alle';

  @override
  String dvrFilterWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get dvrFilterEmpty => 'Keine Aufnahmen für diesen Filter';

  @override
  String dvrSortButton(String option) {
    return 'Sortieren: $option';
  }

  @override
  String get dvrSortDialogTitle => 'Aufnahmen sortieren';

  @override
  String get dvrSortNewest => 'Neueste zuerst';

  @override
  String get dvrSortOldest => 'Älteste zuerst';

  @override
  String get dvrSortTitle => 'Titel (A-Z)';

  @override
  String get dvrLoadError =>
      'Deine Aufnahmen konnten nicht geladen werden. Der Server hat einen Fehler gemeldet.';

  @override
  String get dvrLoadOffline =>
      'Dein Server ist nicht erreichbar. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get dvrLoadPartial =>
      'Einige ältere Aufnahmen konnten nicht geladen werden.';

  @override
  String get dvrLoadRefreshFailed =>
      'Deine Aufnahmen konnten nicht aktualisiert werden. Angezeigt wird die zuletzt geladene Liste.';

  @override
  String get dvrRetry => 'Erneut versuchen';

  @override
  String get requestsProviderHeading => 'Anfragen bei';

  @override
  String get playerAudioSync => 'Audio-Synchronisierung';

  @override
  String get playerSubtitleSync => 'Untertitel-Synchronisierung';

  @override
  String playerSyncRow(String label, String value) {
    return '$label: $value';
  }

  @override
  String playerSyncMilliseconds(String value) {
    return '$value ms';
  }

  @override
  String playerSyncSeconds(String value) {
    return '$value s';
  }

  @override
  String get playerSyncReset => 'Zurücksetzen';

  @override
  String get playerSyncDone => 'Fertig';

  @override
  String get playerAudioSyncHint =>
      'Plus verzögert den Ton, Minus spielt ihn früher ab. Wird für diesen Sender oder Titel gespeichert.';

  @override
  String get playerSubtitleSyncHint =>
      'Plus verzögert die Untertitel, Minus zeigt sie früher an. Wird für diesen Sender oder Titel gespeichert.';
}
