// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get navHome => 'Accueil';

  @override
  String get navSearch => 'Rechercher';

  @override
  String get navLiveTv => 'Télévision en direct';

  @override
  String get navVod => 'Films';

  @override
  String get navSeries => 'Série';

  @override
  String get navDvr => 'DVR';

  @override
  String get navRequests => 'Demandes';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get navMore => 'Plus';

  @override
  String get notificationsDesktopOpen => 'Ouvrir';

  @override
  String get appBackToExit => 'Appuyez à nouveau sur Retour pour quitter';

  @override
  String get appRecordingScheduling =>
      'Enregistrement en cours de programmation…';

  @override
  String appRecordingScheduled(String title) {
    return 'Enregistrement programmé : $title';
  }

  @override
  String appRecordingFailed(String error) {
    return 'Impossible de programmer l\'enregistrement : $error';
  }

  @override
  String get appNotConfigured => 'Connectez votre service dans les Paramètres';

  @override
  String get cancel => 'Annuler';

  @override
  String get disconnect => 'Déconnecter';

  @override
  String get unknown => 'Inconnu';

  @override
  String get admin => 'Administrateur';

  @override
  String get mediaCategoryFilterButton => 'Filter';

  @override
  String get mediaCategorySortButton => 'Trier';

  @override
  String get mediaCategoryFilterScreenTitle => 'Categories';

  @override
  String get liveTvViewModeList => 'List';

  @override
  String get liveTvViewModeGrid => 'Grid';

  @override
  String get liveTvViewModeEpg => 'EPG';

  @override
  String get liveTvSearchHint => 'Rechercher…';

  @override
  String get liveTvUpcomingAirings => 'Prochainement';

  @override
  String get liveTvSearchFilterAll => 'Tout';

  @override
  String get liveTvShowResultsLoading => 'Recherche d\'émissions…';

  @override
  String get liveTvOnNow => 'En direct';

  @override
  String liveTvAiringUntil(String time) {
    return 'Jusqu\'à $time';
  }

  @override
  String liveTvAiringTomorrow(String time) {
    return 'Demain $time';
  }

  @override
  String liveTvMoreAirings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count autres',
      one: '+1 autre',
    );
    return '$_temp0';
  }

  @override
  String get liveTvNoChannels => 'Aucune chaîne disponible';

  @override
  String get liveTvAllChannels => 'Toutes les chaînes';

  @override
  String get liveTvFavorites => '★ Favoris';

  @override
  String get liveTvNoProgram => 'Aucune info programme';

  @override
  String get liveTvNext => 'SUIVANT';

  @override
  String get liveTvRecord => 'Enregistrer';

  @override
  String get liveTvRecording => 'Enregistrement en cours';

  @override
  String get liveTvFavorite => 'Favori';

  @override
  String get liveTvRemoveFavorite => 'Retirer des favoris';

  @override
  String get liveTvCatchupShows => 'Programmes de rattrapage';

  @override
  String get catchupShowsEmpty => 'Aucun programme de rattrapage disponible';

  @override
  String get catchupShowsLoading => 'Chargement des programmes de rattrapage…';

  @override
  String get liveTvAddMultiview => 'Ajouter à Multivue';

  @override
  String get liveTvRemoveMultiview => 'Retirer de Multivue';

  @override
  String get liveTvMultiviewFull => 'Multivue est complet (9 flux max)';

  @override
  String get multiviewTitle => 'Multivue';

  @override
  String get multiviewEmpty =>
      'Aucun flux - appuyez longuement sur une chaîne dans Live TV et choisissez Ajouter à Multivue';

  @override
  String get multiviewMove => 'Déplacer';

  @override
  String get multiviewOpenFullscreen => 'Ouvrir en plein écran';

  @override
  String get multiviewMakeFeatured => 'Mettre en avant';

  @override
  String get multiviewPictureInPicture => 'Image dans l\'image';

  @override
  String get multiviewBackToGrid => 'Retour à la grille';

  @override
  String get multiviewRemove => 'Retirer de Multivue';

  @override
  String get multiviewRetry =>
      'Échec de la lecture - sélectionner pour réessayer';

  @override
  String get multiviewManageTitle => 'Gérer Multivue';

  @override
  String get multiviewClearAll => 'Tout retirer';

  @override
  String multiviewRemoveChannel(String channel) {
    return 'Retirer $channel';
  }

  @override
  String get close => 'Fermer';

  @override
  String get catchupBadgeAvailable => 'Catchup disponible';

  @override
  String catchupBadgeAvailableDays(int days) {
    return 'Catchup disponible : $days j';
  }

  @override
  String get catchupProgramReplayable => 'Rediffusion catchup disponible';

  @override
  String get epgPreviousDay => 'Jour précédent';

  @override
  String get epgNow => 'Maintenant';

  @override
  String get epgNextDay => 'Jour suivant';

  @override
  String get epgChannels => 'CHAÎNES';

  @override
  String get epgNoData => 'Aucune donnée EPG';

  @override
  String get epgProgramScheduledToRecord => 'Programmé pour enregistrement';

  @override
  String get epgProgramCurrentlyRecording => 'En cours d\'enregistrement';

  @override
  String get epgToday => 'Aujourd\'hui';

  @override
  String get epgTomorrow => 'Demain';

  @override
  String get epgYesterday => 'Hier';

  @override
  String get epgLiveBadge => 'EN DIRECT';

  @override
  String get epgReplayBadge => 'REVOIR';

  @override
  String get epgBadgeNew => 'NOUVEAU';

  @override
  String get epgBadgePremiere => 'PREMIÈRE';

  @override
  String get epgBadgeRepeat => 'REDIFFUSION';

  @override
  String epgSeasonEpisode(int season, int episode) {
    return 'S$season É$episode';
  }

  @override
  String epgSeasonNumber(int season) {
    return 'Saison $season';
  }

  @override
  String epgEpisodeNumber(int episode) {
    return 'Épisode $episode';
  }

  @override
  String epgDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String epgDurationHours(int hours) {
    return '$hours h';
  }

  @override
  String epgDurationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String epgTimeLeft(String duration) {
    return 'Encore $duration';
  }

  @override
  String epgStartsIn(String duration) {
    return 'Commence dans $duration';
  }

  @override
  String get epgEnded => 'Terminé';

  @override
  String get epgWatchLive => 'Regarder en direct';

  @override
  String get epgPreview => 'Aperçu';

  @override
  String get epgWatchReplay => 'Revoir';

  @override
  String get epgMoreOptions => 'Plus d\'options';

  @override
  String get epgKeyOk => 'OK';

  @override
  String get epgKeyHoldOk => 'Maintenir OK';

  @override
  String get epgSweepLoadingTitle => 'Chargement du guide des programmes';

  @override
  String epgSweepLoadingBody(int loaded, int total) {
    return '$loaded sur $total chaînes';
  }

  @override
  String get playerGoBack => 'Retour';

  @override
  String get playerResumeWatching => 'Reprendre la lecture';

  @override
  String get playerContinue => 'Continuer';

  @override
  String playerFromTime(String time) {
    return 'À partir de $time';
  }

  @override
  String get playerStartFromBeginning => 'Recommencer depuis le début';

  @override
  String get playerPlay => 'Lire';

  @override
  String get playerResume => 'Reprendre';

  @override
  String get playerClearProgress => 'Effacer la progression';

  @override
  String get playerProgressCleared => 'Progression effacée';

  @override
  String get playerSkipPreviousTooltip => 'Chaîne précédente';

  @override
  String get playerSkipNextTooltip => 'Chaîne suivante';

  @override
  String get playerEpisodesTooltip => 'Épisodes';

  @override
  String get playerEpisodePickerTitle => 'Épisodes';

  @override
  String get playerNowPlayingMovie => 'Film';

  @override
  String get playerNowPlayingSeries => 'Série';

  @override
  String playerNowPlayingSeasonEpisode(int season, int episode) {
    return 'S$season · É$episode';
  }

  @override
  String get playerCommercialSkipped => 'Publicité ignorée';

  @override
  String get playerSkipCommercial => 'Ignorer la publicité';

  @override
  String get playerSkipCredits => 'Ignorer le générique';

  @override
  String get playerSkipIntro => 'Ignorer l\'intro';

  @override
  String get playerUpNext => 'À suivre';

  @override
  String playerEndsAt(String time) {
    return 'Se termine à $time';
  }

  @override
  String get playerUpNextPlay => 'Lire la suite';

  @override
  String get playerUpNextDismiss => 'Ignorer';

  @override
  String get playerLiveStreamEnded => 'Diffusion terminée';

  @override
  String get playerReturningToMenu => 'Retour au menu…';

  @override
  String get playerLoadingStream => 'Chargement du flux…';

  @override
  String get searchHint => 'Rechercher Télévision en direct, films et séries…';

  @override
  String get searchSectionLiveTv => 'Télévision en direct';

  @override
  String get searchSectionMovies => 'Films';

  @override
  String get searchSectionSeries => 'Série';

  @override
  String get vodSearchHint => 'Rechercher…';

  @override
  String get seriesSearchHint => 'Rechercher…';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsGeneral => 'Général';

  @override
  String get settingsGeneralSubtitle => 'Langue, connexion et compte';

  @override
  String get settingsIntegrations => 'Intégrations';

  @override
  String get settingsIntegrationsSubtitle => 'SIMKL, TheIntroDB et plus';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsAppearanceSubtitle => 'Disposition, EPG et affichage';

  @override
  String get settingsPlayback => 'Lecture';

  @override
  String get settingsPlaybackSubtitle => 'Lecteur, proxy et DVR';

  @override
  String get settingsReleaseNotesSubtitle => 'Nouveautés de cette version';

  @override
  String get settingsSectionLanguageRegion => 'Langue et région';

  @override
  String get settingsSectionLayout => 'Disposition';

  @override
  String get settingsSectionDisplay => 'Affichage';

  @override
  String get settingsSectionFilters => 'Filtres';

  @override
  String get settingsSectionStreaming => 'Streaming';

  @override
  String get settingsSectionLiveTv => 'Télévision en direct';

  @override
  String get settingsSectionServices => 'Services';

  @override
  String get settingsIntroDb => 'TheIntroDB';

  @override
  String get settingsIntroDbSubtitle =>
      'Affiche Ignorer l\'intro et Ignorer le générique grâce aux horodatages de la communauté';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Langue du système';

  @override
  String get settingsLangEnglish => 'Anglais';

  @override
  String get settingsLangGerman => 'Allemand';

  @override
  String get settingsLangSpanish => 'Espagnol';

  @override
  String get settingsLangFrench => 'Français';

  @override
  String get settingsLangChinese => 'Chinois (Simplifié)';

  @override
  String get settingsConnection => 'Connexion';

  @override
  String get settingsStatusConnected => 'Connecté';

  @override
  String get settingsStatusUnavailable => 'Indisponible';

  @override
  String get settingsStatusLabel => 'Statut';

  @override
  String get settingsSourceLabel => 'Source';

  @override
  String get settingsServerTimezone => 'Fuseau horaire du serveur';

  @override
  String get settingsLastError => 'Dernière erreur';

  @override
  String get settingsRetryConnection => 'Réessayer la connexion';

  @override
  String get settingsEditServer => 'Modifier les paramètres du serveur';

  @override
  String get settingsActiveViewer => 'Utilisateur actif';

  @override
  String get settingsClearCacheConfirm => 'Vider et actualiser';

  @override
  String get settingsCacheCleared =>
      'Cache vidé. Le contenu est en cours d\'actualisation en arrière-plan.';

  @override
  String get settingsClearCacheEpgHint =>
      'Le guide actuel reste visible pendant le rechargement';

  @override
  String get settingsClearCacheImagesHint =>
      'Affiches et logos se rechargent pendant la navigation';

  @override
  String get settingsEpgCacheCleared =>
      'Le guide est en cours d\'actualisation en arrière-plan.';

  @override
  String get settingsImageCacheCleared => 'Cache des images vidé.';

  @override
  String get settingsCacheSubtitle =>
      'Le contenu en cache se charge instantanément. Les données se rafraîchissent automatiquement en arrière-plan.';

  @override
  String get settingsStorage => 'Stockage';

  @override
  String get settingsStorageSubtitle =>
      'Playlists enregistrées, guide et images';

  @override
  String get settingsStorageTotal => 'Total';

  @override
  String get settingsStorageGuide => 'Guide';

  @override
  String get settingsStorageArtwork => 'Images';

  @override
  String get settingsStorageCalculating => 'Calcul en cours...';

  @override
  String get settingsStorageUnavailable => 'Indisponible';

  @override
  String settingsStorageItems(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString éléments',
      one: '1 élément',
    );
    return '$_temp0';
  }

  @override
  String get settingsStorageNotStored => 'Pas enregistrée sur cet appareil';

  @override
  String get settingsStorageKeepPlaylists =>
      'Playlists conservées sur cet appareil';

  @override
  String settingsStorageKeepPlaylistsValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Les $count plus récentes',
      one: 'Seulement la playlist active',
    );
    return '$_temp0';
  }

  @override
  String get settingsStorageClearPlaylistTitle =>
      'Effacer le contenu enregistré ?';

  @override
  String settingsStorageClearPlaylistBody(String name) {
    return 'Les chaînes, films, séries et le guide de $name sont supprimés de cet appareil. Ils sont téléchargés de nouveau la prochaine fois que vous passez à cette playlist.';
  }

  @override
  String settingsStorageClearActiveBody(String name) {
    return 'Les chaînes, films et séries de $name sont supprimés puis téléchargés de nouveau maintenant.';
  }

  @override
  String get settingsStorageClear => 'Effacer';

  @override
  String get settingsStorageCleared => 'Contenu enregistré effacé.';

  @override
  String get settingsStorageGuideData => 'Données du guide';

  @override
  String settingsStorageProgrammes(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString programmes',
      one: '1 programme',
    );
    return '$_temp0';
  }

  @override
  String get settingsStorageClearGuideTitle =>
      'Actualiser les données du guide ?';

  @override
  String get settingsStorageArtworkCache => 'Cache des images';

  @override
  String get settingsStorageClearArtworkTitle => 'Effacer les images ?';

  @override
  String get settingsStorageClearAll => 'Tout effacer';

  @override
  String get settingsStorageClearAllBody =>
      'Le contenu enregistré des autres playlists et toutes les images sont supprimés. Les chaînes, films, séries et le guide de la playlist active sont téléchargés de nouveau maintenant.';

  @override
  String get settingsEpgRefreshInterval => 'Intervalle de rafraîchissement EPG';

  @override
  String settingsEpgDurationMinutes(int count) {
    return '$count min';
  }

  @override
  String get settingsEpgDurationHour => '1 heure';

  @override
  String settingsEpgDurationHours(int count) {
    return '$count heures';
  }

  @override
  String get settingsManageViewers => 'Gérer les utilisateurs';

  @override
  String get settingsAddViewer => 'Nouvel utilisateur';

  @override
  String get settingsSwitchViewer => 'Changer d\'utilisateur';

  @override
  String get settingsViewerNameLabel => 'Nom d\'utilisateur';

  @override
  String get settingsCreate => 'Créer';

  @override
  String get settingsAccount => 'Compte';

  @override
  String get settingsProxyPlayback => 'Lecture via proxy';

  @override
  String get settingsProxyPlaybackSubtitle =>
      'Diffusez via le proxy m3u-editor avec un profil de transcodage optionnel pour cet appareil.';

  @override
  String get settingsProxyUse => 'Utiliser le proxy';

  @override
  String get settingsProxyForced =>
      'Le proxy est activé au niveau de la playlist et ne peut pas être désactivé.';

  @override
  String get settingsProxyLiveProfile => 'Profil de transcodage en direct';

  @override
  String get settingsProxyVodProfile => 'Profil de transcodage VOD et séries';

  @override
  String get settingsProxyProfileDefault => 'Par défaut';

  @override
  String get settingsProxyProfileDirect => 'Direct (sans transcodage)';

  @override
  String get settingsProxyNoProfiles =>
      'Aucun profil de transcodage disponible — les flux utilisent le proxy direct.';

  @override
  String get settingsDvr => 'DVR';

  @override
  String get settingsDvrSubtitle =>
      'Paramètres de lecture du contenu enregistré.';

  @override
  String get settingsComskip => 'Suppression des publicités';

  @override
  String get settingsComskipSubtitle =>
      'Contrôle la réaction du lecteur aux coupures publicitaires détectées dans les enregistrements DVR.';

  @override
  String get settingsComskipAutoSkip =>
      'Ignorer automatiquement les publicités';

  @override
  String get settingsDisconnectTitle => 'Se déconnecter ?';

  @override
  String get settingsDisconnectBody =>
      'Vous serez déconnecté et devrez saisir à nouveau vos identifiants pour vous reconnecter.';

  @override
  String get settingsDisconnectConfirm => 'Déconnecter';

  @override
  String get settingsPlaylists => 'Playlists';

  @override
  String get settingsPlaylistActive => 'Playlist active';

  @override
  String get settingsAddPlaylist => 'Ajouter une playlist';

  @override
  String get settingsSwitchPlaylist => 'Passer à cette playlist';

  @override
  String get settingsRenamePlaylist => 'Renommer la playlist';

  @override
  String get settingsRemovePlaylist => 'Supprimer la playlist';

  @override
  String get settingsRemovePlaylistTitle => 'Supprimer la playlist ?';

  @override
  String settingsRemovePlaylistBody(String name) {
    return '$name sera supprimée de cet appareil. Vous pourrez l\'ajouter à nouveau à tout moment.';
  }

  @override
  String get settingsDisconnectBodyOtherPlaylists =>
      'Vous serez déconnecté de cette playlist et elle sera supprimée de cet appareil. Vos autres playlists enregistrées restent disponibles pour vous reconnecter.';

  @override
  String get settingsPlaylistNameLabel => 'Nom';

  @override
  String get settingsSave => 'Enregistrer';

  @override
  String settingsSwitchPlaylistFailed(String error) {
    return 'Impossible de changer de playlist : $error';
  }

  @override
  String get settingsTabSaved => 'Enregistrées';

  @override
  String get settingsSavedPlaylistsTitle => 'Playlists enregistrées';

  @override
  String get settingsSavedPlaylistsSubtitle =>
      'Reconnectez-vous à une playlist enregistrée sur cet appareil, ou ajoutez-en une nouvelle via Coupler ou Connexion.';

  @override
  String get settingsApp => 'Application';

  @override
  String get settingsAppVersion => 'Version';

  @override
  String get settingsAppUpdateStatus => 'Mise à jour';

  @override
  String get settingsAppVersionChecking => 'Recherche de mises à jour…';

  @override
  String get settingsAppUpToDate => 'À jour';

  @override
  String settingsAppUpdateAvailable(String version) {
    return 'Mise à jour disponible : $version';
  }

  @override
  String get settingsAppUpdateNoticeTitle => 'Mise à jour de l\'app disponible';

  @override
  String settingsAppUpdateNoticeBody(String version) {
    return 'La version $version est prête à être installée.';
  }

  @override
  String get settingsAppViewRelease => 'Voir la version';

  @override
  String get settingsAppScanQr => 'Scanner pour ouvrir sur votre téléphone';

  @override
  String get settingsReleaseNotesTab => 'Nouveautés';

  @override
  String get settingsReleaseNotesLoading => 'Chargement des notes de version…';

  @override
  String get settingsReleaseNotesError =>
      'Impossible de charger les notes de version. Vérifiez votre connexion et réessayez.';

  @override
  String get settingsReleaseNotesRetry => 'Réessayer';

  @override
  String get settingsReleaseNotesCurrentBadge => 'Actuelle';

  @override
  String get settingsReleaseNotesNewBadge => 'Nouvelle';

  @override
  String settingsReleaseNotesYouAreOn(String version) {
    return 'Vous utilisez la version $version';
  }

  @override
  String settingsReleaseNotesNewerCount(int count) {
    return '$count plus récentes';
  }

  @override
  String get settingsReleaseNotesUpToDate =>
      'Vous utilisez la dernière version';

  @override
  String get settingsReleaseNotesViewOnGithub => 'Tout voir sur GitHub';

  @override
  String get settingsReleaseNotesNoneForVersion =>
      'Aucune note pour cette version.';

  @override
  String get settingsReleaseNotesSelectVersion => 'Sélectionner une version';

  @override
  String settingsReleaseNotesFeatureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveautés',
      one: '1 nouveauté',
    );
    return '$_temp0';
  }

  @override
  String settingsReleaseNotesFixCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correctifs',
      one: '1 correctif',
    );
    return '$_temp0';
  }

  @override
  String get settingsReleaseNotesOlder => 'Version précédente';

  @override
  String get settingsReleaseNotesNewer => 'Version suivante';

  @override
  String get settingsReleaseNotesHintVersions => 'Changer de version';

  @override
  String get settingsReleaseNotesHintScroll => 'Faire défiler';

  @override
  String get settingsFillAllFields => 'Veuillez remplir tous les champs';

  @override
  String get settingsConnectionSettings => 'Paramètres de connexion';

  @override
  String get settingsConnectionSettingsSubtitle =>
      'Entrez vos identifiants Xtream Codes';

  @override
  String get settingsConnectionSettingsHelp =>
      'Utilisez les informations de connexion Xtream de la playlist m3u-editor, pas votre connexion web m3u-editor. Vous avez besoin de l\'URL du serveur, du nom d\'utilisateur Xtream et du mot de passe Xtream.';

  @override
  String get settingsServerUrl => 'URL du serveur';

  @override
  String get settingsServerUrlLocked =>
      'Utilise le serveur de cette application';

  @override
  String get settingsUsername => 'Nom d\'utilisateur';

  @override
  String get settingsPassword => 'Mot de passe';

  @override
  String get settingsConnect => 'Connecter';

  @override
  String get settingsPairWithCode => 'Coupler avec un code';

  @override
  String get settingsTabPair => 'Coupler';

  @override
  String get settingsTabSignIn => 'Connexion';

  @override
  String get settingsPairTabSubtitle =>
      'Saisissez l\'adresse de votre serveur, puis couplez ce téléviseur à l\'aide d\'un code.';

  @override
  String get pairingEnterServerFirst =>
      'Entrez d\'abord l\'URL de votre serveur';

  @override
  String get pairingErrorGeneric =>
      'Le couplage a échoué ou le code a expiré. Veuillez réessayer.';

  @override
  String get pairingScanQr =>
      'Scannez pour ouvrir la page de couplage sur votre téléphone';

  @override
  String get pairingCopyCode => 'Copier le code';

  @override
  String get pairingCodeCopied => 'Copié';

  @override
  String get pairingOpenBrowser => 'Ouvrir dans le navigateur';

  @override
  String get pairingPendingGoTo =>
      'Sur votre téléphone ou ordinateur, allez sur :';

  @override
  String get pairingPendingEnterCode => 'Code d\'appairage :';

  @override
  String get pairingPendingWaiting => 'En attente d\'approbation…';

  @override
  String get homeContinueWatching => 'Reprendre';

  @override
  String get homeNoContinueWatching => 'Rien à reprendre';

  @override
  String get homeViewAll => 'Tout afficher';

  @override
  String homeContinueWatchingMoreCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count autres',
      one: '+1 autre',
    );
    return '$_temp0';
  }

  @override
  String get homeUpNext => 'À suivre';

  @override
  String get continueWatchingItemUnavailable =>
      'Ce contenu n\'est plus disponible';

  @override
  String get homeNoLiveTv => 'Pas de Télévision en direct disponible';

  @override
  String get homeFavoriteChannels => 'Chaînes favorites';

  @override
  String get homeNoFavoriteChannels => 'Aucune chaîne favorite disponible';

  @override
  String get homeNoMovies => 'Pas de films disponibles';

  @override
  String get homeMovie => 'Film';

  @override
  String get homeBrowseLiveTv => 'Parcourir toutes les chaînes';

  @override
  String get homeBrowseSports =>
      'Tous les matchs de tes ligues, avec les scores en direct';

  @override
  String homeSportsStartsAt(String time) {
    return 'Commence à $time';
  }

  @override
  String homeSportsOnChannels(String channels) {
    return 'Sur $channels';
  }

  @override
  String get homeBrowseMovies => 'Parcourir tous les films';

  @override
  String get homeBrowseSeries => 'Parcourir toutes les séries';

  @override
  String get homeNothingToShow => 'Rien à afficher pour le moment';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsTabNotifications => 'Notifications';

  @override
  String get notificationsTabChannelSettings => 'Paramètres des chaînes';

  @override
  String get notificationsMarkAllRead => 'Tout marquer comme lu';

  @override
  String get notificationsEmpty => 'Aucune notification pour l\'instant';

  @override
  String get notificationsEmptyFiltered =>
      'Aucune notification pour vos chaînes abonnées';

  @override
  String get notificationsChannelSubscriptions => 'Abonnements aux chaînes';

  @override
  String get notificationsChannelSubtitle =>
      'Sélectionnez les chaînes que vous souhaitez recevoir. Laissez tout désélectionné pour tout recevoir.';

  @override
  String get notificationsAllChannels => 'Toutes les chaînes';

  @override
  String get notificationsNoChannels =>
      'Aucune chaîne pour l\'instant — elles apparaissent ici à l\'arrivée des notifications.';

  @override
  String get notificationsJustNow => 'à l\'instant';

  @override
  String notificationsMinutesAgo(int count) {
    return 'il y a ${count}m';
  }

  @override
  String notificationsHoursAgo(int count) {
    return 'il y a ${count}h';
  }

  @override
  String notificationsDaysAgo(int count) {
    return 'il y a ${count}j';
  }

  @override
  String notificationsReceivedAt(String time) {
    return 'Reçu $time';
  }

  @override
  String notificationsReadAt(String time) {
    return 'Lu $time';
  }

  @override
  String get homeNoSeries => 'Pas de séries disponibles';

  @override
  String get homeDvrRecordings => 'Enregistrements DVR';

  @override
  String get homeDvrRecordingsBrowse =>
      'Parcourir les enregistrements terminés et en cours';

  @override
  String homeSeason(int number) {
    return 'Saison $number';
  }

  @override
  String get seriesSeasons => 'Saisons';

  @override
  String get seriesCast => 'Casting';

  @override
  String get relatedTitle => 'Contenus similaires';

  @override
  String seriesEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count épisodes',
      one: '1 épisode',
    );
    return '$_temp0';
  }

  @override
  String seriesPlayEpisode(int season, int episode) {
    return 'Lire S${season}E$episode';
  }

  @override
  String seriesResumeEpisode(int season, int episode) {
    return 'Reprendre S${season}E$episode';
  }

  @override
  String get seriesMarkWatched => 'Marquer comme vu';

  @override
  String get seriesMarkUnwatched => 'Marquer comme non vu';

  @override
  String get seriesMarkedWatched => 'Marqué comme vu';

  @override
  String get seriesMarkedUnwatched => 'Marqué comme non vu';

  @override
  String get seriesMarkSyncFailed => 'Impossible de synchroniser le statut vu';

  @override
  String seriesMarkSeasonPrompt(int number) {
    return 'Mettre à jour le statut vu pour tous les épisodes de la saison $number ?';
  }

  @override
  String get traktWatchHistory => 'Historique de visionnage';

  @override
  String get traktWatchHistorySubtitle =>
      'Synchronisez votre historique de visionnage avec Trakt pour suivre votre progression sur toutes les applications et services.';

  @override
  String get traktNotConfigured =>
      'Les identifiants du client Trakt ne sont pas configurés.';

  @override
  String get traktNotConfiguredHint =>
      'Enregistrez une application sur trakt.tv/oauth/applications et définissez le client ID et le secret via --dart-define lors de la compilation.';

  @override
  String get traktConnectPrompt =>
      'Connectez votre compte Trakt pour suivre automatiquement ce que vous regardez.';

  @override
  String get traktConnectButton => 'Connecter avec Trakt';

  @override
  String get traktScanQr => 'Scanner pour ouvrir sur votre téléphone';

  @override
  String get traktOpenBrowser => 'Ouvrir dans le navigateur';

  @override
  String get traktPendingGoTo =>
      'Sur votre téléphone ou ordinateur, allez sur :';

  @override
  String get traktPendingEnterCode => 'Saisissez ensuite ce code :';

  @override
  String get traktPendingWaiting => 'En attente d\'autorisation…';

  @override
  String get traktConnected => 'Connecté à Trakt';

  @override
  String traktConnectedAs(String account) {
    return 'Connecté à Trakt en tant que $account';
  }

  @override
  String get traktDisconnectButton => 'Déconnecter Trakt';

  @override
  String get traktName => 'Trakt';

  @override
  String get simklName => 'Simkl';

  @override
  String serverWatchHistoryActive(String service) {
    return 'M3U Editor envoie la progression de lecture de cet identifiant à $service.';
  }

  @override
  String serverWatchHistoryActiveAs(String service, String account) {
    return 'M3U Editor envoie la progression de lecture de cet identifiant à $service en tant que $account.';
  }

  @override
  String serverWatchHistoryOverrideHint(String service) {
    return 'Connectez-vous ici pour utiliser votre propre compte $service sur cet appareil.';
  }

  @override
  String get serverWatchHistoryOverridden =>
      'Cet appareil envoie sa lecture au compte connecté ici. Déconnectez-le pour utiliser plutôt le compte du serveur.';

  @override
  String get simklConnectPrompt =>
      'Connectez votre compte Simkl pour suivre automatiquement ce que vous regardez.';

  @override
  String get simklConnectButton => 'Se connecter avec Simkl';

  @override
  String get simklConnected => 'Connecté à Simkl';

  @override
  String simklConnectedAs(String account) {
    return 'Connecté à Simkl en tant que $account';
  }

  @override
  String get simklDisconnectButton => 'Déconnecter Simkl';

  @override
  String get simklNotConfigured =>
      'L\'identifiant client Simkl n\'est pas configuré.';

  @override
  String get simklNotConfiguredHint =>
      'Enregistrez une application sur simkl.com/settings/developer et définissez l\'identifiant client avec --dart-define=SIMKL_CLIENT_ID.';

  @override
  String get mdblistName => 'MDBList';

  @override
  String get mdblistConnectPrompt =>
      'Connectez votre compte MDBList pour suivre automatiquement ce que vous regardez.';

  @override
  String get mdblistConnectButton => 'Se connecter avec MDBList';

  @override
  String get mdblistConnected => 'Connecté à MDBList';

  @override
  String mdblistConnectedAs(String account) {
    return 'Connecté à MDBList en tant que $account';
  }

  @override
  String get mdblistDisconnectButton => 'Déconnecter MDBList';

  @override
  String get mdblistNotConfigured =>
      'L\'identifiant client MDBList n\'est pas configuré.';

  @override
  String get mdblistNotConfiguredHint =>
      'Enregistrez une application sur mdblist.com/developer et définissez l\'identifiant client avec --dart-define=MDBLIST_CLIENT_ID.';

  @override
  String get vodAllMovies => 'Tous les films';

  @override
  String get seriesAllSeries => 'Toutes les séries';

  @override
  String homeConnectedSource(String label) {
    return 'Source connectée : $label';
  }

  @override
  String get searchTypeToSearch => 'Saisir pour rechercher';

  @override
  String get vodPlayMovie => 'Lire le film';

  @override
  String get vodContinueMovie => 'Continuer le film';

  @override
  String get vodCast => 'Casting';

  @override
  String get vodDirector => 'Réalisateur';

  @override
  String get castShowAll => 'Voir tout le casting';

  @override
  String vodTimeLeftMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Il reste $minutes min',
      one: 'Il reste 1 min',
    );
    return '$_temp0';
  }

  @override
  String vodTimeLeftHoursMinutes(int hours, int minutes) {
    return 'Il reste $hours h $minutes min';
  }

  @override
  String get navAioStreams => 'AIOStreams';

  @override
  String get aiostreamsGetStreams => 'Obtenir les sources';

  @override
  String get aiostreamsLoadingStreams => 'Chargement des sources…';

  @override
  String get aiostreamsNoStreams => 'Aucune source trouvée';

  @override
  String get aiostreamsSelectStream => 'Sélectionner une source';

  @override
  String get aiostreamsLoadMore => 'Charger plus';

  @override
  String get aiostreamsSearchHint => 'Rechercher films et séries…';

  @override
  String get aiostrreamsCatalogEmpty => 'Rien ici pour l\'instant';

  @override
  String get aiostreamsToggleFavorite => 'Favori';

  @override
  String get aiostreamsMyFavorites => 'Mes Favoris';

  @override
  String get aiostreamsContinueWatching => 'Continuer à regarder';

  @override
  String get aiostreamsSearch => 'Rechercher dans AIOStreams';

  @override
  String get aiostreamsSearchResults => 'Résultats de recherche';

  @override
  String get aiostreamsNoResults => 'Aucun résultat trouvé';

  @override
  String get aiostreamsSearchAll => 'Tout';

  @override
  String get requestsTitle => 'Demandes';

  @override
  String get requestsTabSearch => 'Recherche';

  @override
  String get requestsTabMyRequests => 'Mes Demandes';

  @override
  String get requestsSearchHint => 'Rechercher…';

  @override
  String get requestsNoResults => 'Aucun résultat trouvé';

  @override
  String get requestsAlreadyAvailable => 'Déjà disponible';

  @override
  String get requestsAlreadyRequested => 'Déjà demandé';

  @override
  String get requestsRequestButton => 'Demander';

  @override
  String get requestsSeasonsHeading => 'Saisons';

  @override
  String get requestsSeasonSpecials => 'Épisodes spéciaux';

  @override
  String get requestsSelectAllSeasons => 'Tout sélectionner';

  @override
  String get requestsClearSeasons => 'Effacer';

  @override
  String requestsSubmitted(String title) {
    return '« $title » a été demandé';
  }

  @override
  String requestsSubmittedPendingApproval(String title) {
    return '« $title » a été envoyé pour approbation';
  }

  @override
  String requestsSubmitFailed(String title, String error) {
    return 'Impossible de demander « $title » : $error';
  }

  @override
  String get requestsMyRequestsEmpty => 'Vous n\'avez encore rien demandé';

  @override
  String get requestsDismiss => 'Ignorer';

  @override
  String requestsDismissFailed(String error) {
    return 'Impossible d\'ignorer la demande : $error';
  }

  @override
  String get requestsStatusPendingApproval => 'En attente d\'approbation';

  @override
  String get requestsStatusApproved => 'Approuvé';

  @override
  String get requestsStatusRejected => 'Rejeté';

  @override
  String get requestsStatusCompleted => 'Terminé';

  @override
  String get requestsStatusUnknown => 'Inconnu';

  @override
  String get dvrRecordingsTitle => 'Enregistrements';

  @override
  String get dvrRecordingsSubtitle => 'Enregistrements terminés et en cours';

  @override
  String get dvrNoRecordings => 'Aucun enregistrement DVR disponible';

  @override
  String get dvrNotConfigured =>
      'Veuillez vous connecter à votre service dans les paramètres';

  @override
  String get dvrCancel => 'Annuler';

  @override
  String get dvrDelete => 'Supprimer';

  @override
  String dvrStopTitle(String title) {
    return 'Arrêter l\'enregistrement — $title';
  }

  @override
  String get dvrStopMessage =>
      'La conserver dans votre liste ou la supprimer maintenant ?';

  @override
  String get dvrStopKeep => 'Conserver l\'enregistrement';

  @override
  String get dvrStopDelete => 'Supprimer l\'enregistrement';

  @override
  String get dvrStopBack => 'Retour';

  @override
  String get dvrCancelSuccess => 'Enregistrement annulé';

  @override
  String get dvrCancelFailed => 'Impossible d\'annuler l\'enregistrement';

  @override
  String get dvrDeleteTitle => 'Supprimer l\'enregistrement ?';

  @override
  String get dvrDeleteMessage =>
      'Cet enregistrement sera supprimé définitivement.';

  @override
  String get dvrDeleteDismiss => 'Conserver';

  @override
  String get dvrDeleteConfirm => 'Supprimer l\'enregistrement';

  @override
  String get dvrDeleteSuccess => 'Enregistrement supprimé';

  @override
  String get dvrDeleteFailed => 'Impossible de supprimer l\'enregistrement';

  @override
  String get liveTvStopRecording => 'Arrêter l\'enregistrement';

  @override
  String get playerEnterFullscreen => 'Plein écran';

  @override
  String get playerExitFullscreen => 'Quitter le plein écran';

  @override
  String get playerSeekUnavailableTranscoding =>
      'La recherche n\'est pas disponible pendant le transcodage';

  @override
  String get playerRecordNowTooltip => 'Enregistrer le programme en cours';

  @override
  String get playerStopRecordingTooltip => 'Arrêter l\'enregistrement';

  @override
  String get dvrMoreActions => 'Plus d\'actions';

  @override
  String get dvrPlay => 'Lire';

  @override
  String get dvrSelect => 'Sélectionner';

  @override
  String get dvrStop => 'Arrêter';

  @override
  String get dvrStatusRecording => 'Enregistrement';

  @override
  String get dvrStatusScheduled => 'Planifiée';

  @override
  String get dvrStatusFailed => 'Échec';

  @override
  String get dvrExitSelection => 'Quitter la sélection';

  @override
  String dvrSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments sélectionnés',
      one: '1 élément sélectionné',
      zero: 'Aucun élément sélectionné',
    );
    return '$_temp0';
  }

  @override
  String get dvrStorageTitle => 'Stockage DVR';

  @override
  String get dvrStorageUnlimited => 'Illimité';

  @override
  String dvrStorageUsedUnlimited(String used) {
    return '$used utilisé';
  }

  @override
  String dvrStorageUsedWithQuota(String used, String quota) {
    return '$used sur $quota utilisé';
  }

  @override
  String dvrStorageRecordingCount(int count) {
    return '$count enregistrements';
  }

  @override
  String get dvrSeriesChannel => 'Chaîne';

  @override
  String get dvrSeriesStartEarly => 'Démarrer en avance';

  @override
  String get dvrSeriesUseDefault => 'Par défaut';

  @override
  String dvrEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count épisodes',
      one: '1 épisode',
    );
    return '$_temp0';
  }

  @override
  String get dvrDeleteSeriesRule => 'Supprimer la règle';

  @override
  String get dvrEditSeriesRule => 'Modifier la règle';

  @override
  String get dvrUpdateSeriesRuleFailed =>
      'Impossible de mettre à jour la règle de série';

  @override
  String get dvrSeriesSave => 'Enregistrer';

  @override
  String get dvrSeriesSecondsSuffix => 'sec';

  @override
  String get dvrSeriesMode => 'Mode série';

  @override
  String get dvrUpdateSeriesRuleSuccess => 'Règle de série mise à jour';

  @override
  String get dvrSeriesModeAll => 'Tous les épisodes';

  @override
  String get dvrSeriesMatchModeStartsWith => 'Commence par';

  @override
  String get dvrDeleteSeriesRuleConfirm => 'Supprimer cette règle de série ?';

  @override
  String get dvrSeriesCancel => 'Annuler';

  @override
  String get dvrDeleteSeriesRuleSuccess => 'Règle de série supprimée';

  @override
  String get dvrSeriesRulesTitle => 'Règles';

  @override
  String get dvrSeriesMatchModeContains => 'Contient';

  @override
  String get dvrSeriesMatchModeExact => 'Exact';

  @override
  String get dvrSeriesModeUseDefault => 'Par défaut';

  @override
  String get dvrSeriesModeNewFlag => 'Nouveaux uniquement';

  @override
  String get dvrDeleteSeriesRuleFailed =>
      'Impossible de supprimer la règle de série';

  @override
  String get dvrSeriesKeepLast => 'Garder dernière';

  @override
  String get dvrSeriesModeUniqueSe => 'S-E unique';

  @override
  String get dvrSeriesAnyChannel => 'N\'importe quelle chaîne';

  @override
  String get dvrSeriesMatchMode => 'Mode de correspondance';

  @override
  String get dvrSeriesEndLate => 'Fin tard';

  @override
  String get dvrSeriesOptions => 'Options';

  @override
  String dvrSeriesOptionsFor(String title) {
    return 'Options : $title';
  }

  @override
  String get dvrSeriesAllEpisodesWarning =>
      'Enregistrer tous les épisodes sur n\'importe quelle chaîne peut créer des doublons — utilisez Nouveaux uniquement ou S-E unique pour dédupliquer.';

  @override
  String get dvrSeriesRulesEmpty => 'Aucune règle de série';

  @override
  String get dvrSeriesPriority => 'Priorité';

  @override
  String get epgRecordSeries => 'Enregistrer la série';

  @override
  String epgRecordSeriesSuccess(String title) {
    return 'Enregistrement de série activé pour $title';
  }

  @override
  String get epgRecordSeriesFailed =>
      'Impossible d\'activer l\'enregistrement de la série';

  @override
  String get epgRecordSeriesDuplicate => 'Enregistrement de série déjà activé';

  @override
  String get navShows => 'Shows';

  @override
  String get showAiringNext => 'Prochaine diffusion';

  @override
  String get showAiringNone => 'Aucun épisode à venir dans l\'EPG';

  @override
  String showChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chaînes',
      one: '1 chaîne',
    );
    return '$_temp0';
  }

  @override
  String get showDeleteRule => 'Supprimer la règle de série';

  @override
  String showDeleteRuleConfirm(String title) {
    return 'Supprimer la règle de série pour $title ? Les futurs épisodes ne seront pas enregistrés. Les enregistrements déjà effectués ne seront pas supprimés.';
  }

  @override
  String get showSeriesRuleActive => 'Règle de série active';

  @override
  String get showScheduled => 'Programmé';

  @override
  String showBatchRecord(int count) {
    return 'Enregistrer ($count)';
  }

  @override
  String showBatchScheduleSummary(int scheduled, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      scheduled,
      locale: localeName,
      other: '$scheduled épisodes programmés',
      one: '1 épisode programmé',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '$failed échecs.',
      one: '1 échec.',
      zero: 'Tous réussis.',
    );
    return '$_temp0. $_temp1';
  }

  @override
  String showBatchScheduleFailures(String titles) {
    return 'Échecs : $titles';
  }

  @override
  String get showDetailTitle => 'Détails du show';

  @override
  String showEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count épisodes',
      one: '1 épisode',
    );
    return '$_temp0';
  }

  @override
  String get showRecordSeries => 'Enregistrer la série';

  @override
  String showRecordSeriesConfirm(String title, String channel) {
    return 'Enregistrer chaque épisode de $title sur $channel ?';
  }

  @override
  String showRecordSeriesFailed(String title) {
    return 'Impossible d\'activer l\'enregistrement de la série pour $title';
  }

  @override
  String showRecordSeriesSuccess(String title) {
    return 'Enregistrement de série activé pour $title';
  }

  @override
  String showRecordSeriesDuplicate(String title) {
    return 'Enregistrement de série déjà activé pour $title';
  }

  @override
  String get showsError => 'Impossible de rechercher des shows';

  @override
  String get showsNoResults => 'Aucun show ne correspond à votre recherche';

  @override
  String get showsSearchError => 'Échec de la recherche';

  @override
  String get showsSearchHint => 'Rechercher des shows par titre';

  @override
  String get showsTitle => 'Shows';

  @override
  String showNotFound(String title) {
    return 'Show « $title » introuvable';
  }

  @override
  String get settingsView => 'Affichage';

  @override
  String get settingsLiveTvLayout => 'Mise en page TV en direct';

  @override
  String get settingsLiveTvLayoutList => 'Liste';

  @override
  String get settingsLiveTvLayoutGrid => 'Grille';

  @override
  String get settingsLiveTvLayoutTimeline => 'Chronologie';

  @override
  String get settingsLiveTvChannelColumn => 'Colonne des chaînes';

  @override
  String get settingsLiveTvChannelColumnLogoTitle => 'Logo + Titre';

  @override
  String get settingsLiveTvChannelColumnLogoOnly => 'Logo uniquement';

  @override
  String get settingsLiveTvChannelColumnTitleOnly => 'Titre uniquement';

  @override
  String get settingsEpgStartView => 'Le guide démarre à';

  @override
  String get settingsEpgStartViewCurrentTime => 'Heure actuelle';

  @override
  String get settingsEpgStartViewPrimeTime => 'Prime time';

  @override
  String get settingsEpgPreviewPlayback => 'Lecture dans l\'aperçu du guide';

  @override
  String get settingsEpgPreviewPlaybackOff => 'Désactivée';

  @override
  String get settingsEpgPreviewPlaybackPauseToPlay => 'Lire après une pause';

  @override
  String get settingsEpgPreviewPlaybackClickToPreview =>
      'Appuyer sur OK pour prévisualiser';

  @override
  String get settingsEpgPreviewDelay => 'Délai de l\'aperçu';

  @override
  String settingsEpgPreviewDelaySeconds(int count) {
    return '$count secondes';
  }

  @override
  String get settingsFilterPersistence => 'Persistance du filtre';

  @override
  String get settingsFilterPersistenceRemember => 'Mémoriser';

  @override
  String get settingsFilterPersistenceReset => 'Réinitialiser à chaque fois';

  @override
  String get vodSortDialogTitle => 'Trier les films par';

  @override
  String get seriesSortDialogTitle => 'Trier les séries par';

  @override
  String get mediaSortDefault => 'Par défaut';

  @override
  String get mediaSortRating => 'Note';

  @override
  String get mediaSortReleaseDateNewest => 'Plus récents d\'abord';

  @override
  String get mediaSortReleaseDateOldest => 'Plus anciens d\'abord';

  @override
  String get mediaSortTitleAsc => 'Titre (A-Z)';

  @override
  String get mediaSortTitleDesc => 'Titre (Z-A)';

  @override
  String get mediaSortFavoritesFirst => 'Favoris en premier';

  @override
  String get liveTvSortDialogTitle => 'Trier les chaînes par';

  @override
  String get channelSortPlaylistOrder => 'Ordre de la playlist';

  @override
  String get channelSortChannelNumber => 'Numéro de chaîne';

  @override
  String get channelSortAlphabeticalAsc => 'Alphabétique (A-Z)';

  @override
  String get channelSortAlphabeticalDesc => 'Alphabétique (Z-A)';

  @override
  String get settingsDefaultStartPage => 'Page de démarrage par défaut';

  @override
  String get settingsHomeScreenStyle => 'Écran d\'accueil';

  @override
  String get settingsHomeScreenStyleSimplified => 'Simplifié';

  @override
  String get settingsHomeScreenStyleRich => 'Spotlight';

  @override
  String get settingsSectionPlayer => 'Lecteur';

  @override
  String get settingsVodPlayer => 'Lecteur des films et séries';

  @override
  String get settingsVodPlayerExoPlayerFirst => 'Essayer ExoPlayer d\'abord';

  @override
  String get settingsVodPlayerMpv => 'Utiliser mpv';

  @override
  String get settingsHdrMode => 'Mode HDR';

  @override
  String get settingsHdrModeHint =>
      'Autoriser les vidéos HDR à basculer l\'écran en mode HDR. Windows et Linux uniquement.';

  @override
  String get settingsMatchRefreshRate =>
      'Adapter la fréquence de rafraîchissement';

  @override
  String get settingsMatchRefreshRateHint =>
      'Bascule l\'écran sur la fréquence d\'images de la vidéo au démarrage de la lecture. L\'écran peut brièvement clignoter ou devenir noir.';

  @override
  String get settingsDeinterlace => 'Désentrelacer la vidéo';

  @override
  String get settingsDeinterlaceHint =>
      'Atténue les lignes en peigne des chaînes entrelacées (comme 1080i et 576i). Utilise davantage le processeur.';

  @override
  String get settingsBackgroundAudio => 'Audio en arrière-plan';

  @override
  String get settingsBackgroundAudioHint =>
      'Continue la lecture audio, avec les commandes sur l\'écran verrouillé et dans les notifications, lorsque vous quittez l\'app ou verrouillez l\'écran.';

  @override
  String get settingsPrebufferLive =>
      'Mettre en mémoire tampon les flux en direct avant la lecture';

  @override
  String get settingsPrebufferLiveHint =>
      'Attend quelques secondes de vidéo avant qu\'une chaîne ne démarre, pour que les flux irréguliers cessent de s\'interrompre pour charger. Les changements de chaîne prennent quelques secondes de plus.';

  @override
  String get settingsNavigationSound => 'Son de navigation';

  @override
  String get settingsNavigationSoundHint =>
      'Joue un son de clic lors du déplacement du focus avec la télécommande ou le clavier.';

  @override
  String get settingsToggleOn => 'Activé';

  @override
  String get settingsToggleOff => 'Désactivé';

  @override
  String get settingsOptimizeFor => 'Optimiser pour';

  @override
  String get settingsOptimizeForQuality => 'Qualité';

  @override
  String get settingsOptimizeForQualityHint =>
      'Images plus nettes, utilisation mémoire accrue.';

  @override
  String get settingsOptimizeForSpeed => 'Vitesse';

  @override
  String get settingsOptimizeForSpeedHint =>
      'Chargement plus rapide, qualité image réduite.';

  @override
  String get settingsFontSize => 'Taille d\'affichage';

  @override
  String get settingsFontSizeVerySmall => 'Très petit';

  @override
  String get settingsFontSizeSmall => 'Petit';

  @override
  String get settingsFontSizeNormal => 'Normal';

  @override
  String get settingsFontSizeLarge => 'Grand';

  @override
  String get settingsFontSizeVeryLarge => 'Très grand';

  @override
  String get personDetailsFilmography => 'Filmographie';

  @override
  String get personDetailsBioUnavailable => 'Aucune biographie disponible.';

  @override
  String get personDetailsEmpty => 'Aucune filmographie disponible.';

  @override
  String get personDetailsError =>
      'Impossible de charger la filmographie de cet acteur.';

  @override
  String get personDetailsFilterInLibrary => 'Dans la bibliothèque';

  @override
  String get personDetailsNoLibraryMatches =>
      'Aucun élément de la filmographie de cet acteur n\'est dans votre bibliothèque.';

  @override
  String get settingsLogsDiagnostics => 'Journaux et diagnostics';

  @override
  String get settingsLogsDiagnosticsSubtitle =>
      'Détails de l\'appareil et journaux de cette session, pour le dépannage';

  @override
  String get settingsPlaybackDiagnostics => 'Afficher le diagnostic de lecture';

  @override
  String get settingsPlaybackDiagnosticsHint =>
      'Affiche dans les commandes le lecteur actif et la raison de son changement, pour le dépannage.';

  @override
  String get diagnosticsUpload => 'Envoyer au serveur';

  @override
  String get diagnosticsRefresh => 'Actualiser';

  @override
  String get diagnosticsClear => 'Effacer les journaux';

  @override
  String get diagnosticsUploading => 'Envoi des journaux...';

  @override
  String diagnosticsUploaded(int id) {
    return 'Journaux envoyés (#$id). Un administrateur peut les consulter dans m3u-editor sous Appareils > Appareils enregistrés.';
  }

  @override
  String diagnosticsUploadFailed(String error) {
    return 'Impossible d\'envoyer les journaux : $error';
  }

  @override
  String get diagnosticsNotConnected =>
      'Connectez-vous à un serveur pour envoyer les journaux.';

  @override
  String get diagnosticsDeviceHeading => 'Appareil';

  @override
  String diagnosticsLogsHeading(int count) {
    return 'Journaux ($count)';
  }

  @override
  String get diagnosticsNoLogs =>
      'Rien n\'a encore été journalisé pendant cette session.';

  @override
  String get trailerButton => 'Bande-annonce';

  @override
  String trailerSeasonButton(int season) {
    return 'Bande-annonce saison $season';
  }

  @override
  String get trailerWatch => 'Regarder la bande-annonce';

  @override
  String get mediaSortRecentlyAdded => 'Ajouts récents';

  @override
  String get mediaSortRecentlyUpdated => 'Mis à jour récemment';

  @override
  String get playerTrackAudio => 'Audio';

  @override
  String get playerTrackSubtitles => 'Sous-titres';

  @override
  String get playerTrackAudioTitle => 'Piste audio';

  @override
  String get playerTrackSubtitleTitle => 'Piste de sous-titres';

  @override
  String get playerTrackAudioDisabled => 'Désactiver';

  @override
  String get playerTrackSubtitlesOff => 'Désactivés';

  @override
  String get playerOnlineSubtitlesSearch => 'Rechercher en ligne';

  @override
  String get playerOnlineSubtitlesTitle => 'Sous-titres en ligne';

  @override
  String get playerOnlineSubtitlesSearching => 'Recherche de sous-titres…';

  @override
  String get playerOnlineSubtitlesLoading => 'Chargement du sous-titre…';

  @override
  String get playerOnlineSubtitlesEmpty =>
      'Aucun sous-titre trouvé pour ce titre.';

  @override
  String get playerOnlineSubtitlesFailed =>
      'Impossible de charger les sous-titres. Vérifiez votre connexion et réessayez.';

  @override
  String get playerOnlineSubtitlesRetry => 'Réessayer';

  @override
  String get playerOnlineSubtitlesAllLanguages => 'Toutes les langues';

  @override
  String get settingsOnlineSubtitles => 'Sous-titres en ligne';

  @override
  String get settingsOnlineSubtitlesSubtitle =>
      'Trouvez des sous-titres pour les films et les épisodes depuis le menu des sous-titres du lecteur.';

  @override
  String get settingsOnlineSubtitlesAddress => 'Source des sous-titres';

  @override
  String get settingsOnlineSubtitlesAddressHint =>
      'Adresse de l\'extension de sous-titres Stremio';

  @override
  String get settingsOnlineSubtitlesAddressInvalid =>
      'Saisissez une adresse http ou https valide.';

  @override
  String get settingsOnlineSubtitlesUseDefault =>
      'Utiliser la valeur par défaut';

  @override
  String get playerHdrOn => 'HDR activé';

  @override
  String get playerHdrOff => 'HDR désactivé';

  @override
  String get playerStartOver => 'Recommencer';

  @override
  String get playerDiagBackend => 'Moteur';

  @override
  String get playerDiagFallback => 'Repli';

  @override
  String get playerDiagCodec => 'Codec';

  @override
  String get playerDiagTranscode => 'Transcodage';

  @override
  String get playerDiagCleanup => 'Nettoyage';

  @override
  String get metaWriter => 'Scénario';

  @override
  String get mediaClearSearch => 'Effacer la recherche';

  @override
  String seriesEpisodesLoadFailed(String error) {
    return 'Impossible de charger les épisodes : $error';
  }

  @override
  String get seriesNoEpisodes => 'Aucun épisode disponible';

  @override
  String get settingsConnecting => 'Connexion...';

  @override
  String get favoritesNoChannels => 'Aucune chaîne favorite';

  @override
  String get favoritesNoMovies => 'Aucun film favori';

  @override
  String get favoritesNoSeries => 'Aucune série favorite';

  @override
  String get seriesLoadFailed => 'Impossible de charger les séries';

  @override
  String get vodLoadFailed => 'Impossible de charger les films';

  @override
  String get vodNoSynopsis => 'Aucun synopsis disponible.';

  @override
  String get settingsConnectionFailed =>
      'Échec de la connexion. Vérifiez vos identifiants.';

  @override
  String get settingsConnectingSubtitle =>
      'Veuillez patienter pendant la connexion à votre service';

  @override
  String get settingsCreateViewerFailed =>
      'Impossible de créer le spectateur. Veuillez réessayer.';

  @override
  String get searchNoResults => 'Aucun résultat trouvé';

  @override
  String get playerLoadTimedOut =>
      'Le chargement du flux a expiré. Le serveur est peut-être injoignable ou l\'URL du flux est invalide.';

  @override
  String get playerErrorTitle => 'Erreur de lecture';

  @override
  String get navSports => 'Sports';

  @override
  String get sportsScopeAll => 'Toutes les ligues';

  @override
  String get sportsScopeMyTeams => 'Mes équipes';

  @override
  String get sportsSearchHint => 'Rechercher des équipes';

  @override
  String get sportsLeaguesButton => 'Ligues';

  @override
  String get sportsLeaguesTitle => 'Afficher les ligues';

  @override
  String sportsLeaguesShownCount(int shown, int total) {
    return '$shown sur $total affichées';
  }

  @override
  String get sportsDone => 'Terminé';

  @override
  String get sportsLiveNow => 'En direct';

  @override
  String get sportsLiveBadge => 'EN DIRECT';

  @override
  String get sportsFinal => 'Terminé';

  @override
  String get sportsPostponed => 'Reporté';

  @override
  String get sportsNoGames => 'Aucun match ce jour-là';

  @override
  String get sportsNoLeagues =>
      'Aucune ligue sélectionnée. Choisissez-en dans Ligues.';

  @override
  String get sportsMyTeamsEmpty =>
      'Vous ne suivez encore aucune équipe. Utilisez Équipes pour choisir les vôtres, ou appuyez longuement sur un match.';

  @override
  String get sportsMyTeamsNoGames => 'Aucune de vos équipes ne joue ce jour-là';

  @override
  String sportsChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chaînes',
      one: '1 chaîne',
    );
    return '$_temp0';
  }

  @override
  String get sportsNoChannel => 'Aucune chaîne';

  @override
  String get sportsEventChannel => 'Chaîne de l\'événement';

  @override
  String get sportsWatch => 'Regarder';

  @override
  String get sportsViewDetails => 'Détails du match';

  @override
  String get sportsDetailsTitle => 'Match';

  @override
  String get sportsFollow => 'Suivre';

  @override
  String get sportsFollowing => 'Suivi';

  @override
  String get sportsDetailsOnYourChannels => 'Sur vos chaînes';

  @override
  String get sportsDetailsLoadFailed =>
      'Impossible de charger les détails du match. Nouvel essai sous peu.';

  @override
  String get sportsDetailsUnavailable =>
      'Aucun autre détail n\'est encore disponible pour ce match.';

  @override
  String get sportsDetailsLineScore => 'Score par période';

  @override
  String get sportsDetailsTotalShort => 'T';

  @override
  String get sportsDetailsEvents => 'Moments clés';

  @override
  String get sportsDetailsStats => 'Statistiques d\'équipe';

  @override
  String get sportsDetailsSeasonStats => 'Statistiques de la saison';

  @override
  String get sportsDetailsLeaders => 'Meilleurs joueurs';

  @override
  String get sportsDetailsSeasonLeaders => 'Meneurs de la saison';

  @override
  String get sportsDetailsInfo => 'Infos du match';

  @override
  String get sportsDetailsStart => 'Heure de début';

  @override
  String get sportsDetailsVenue => 'Lieu';

  @override
  String get sportsDetailsAttendance => 'Affluence';

  @override
  String get sportsDetailsOfficials => 'Arbitres';

  @override
  String get sportsDetailsSeries => 'Série';

  @override
  String get sportsDetailsBroadcast => 'Diffusion';

  @override
  String sportsFollowTeam(String team) {
    return 'Suivre $team';
  }

  @override
  String sportsUnfollowTeam(String team) {
    return 'Ne plus suivre $team';
  }

  @override
  String sportsFollowingTeam(String team) {
    return 'Vous suivez $team';
  }

  @override
  String sportsUnfollowedTeam(String team) {
    return 'Vous ne suivez plus $team';
  }

  @override
  String sportsAddedToMultiview(String channel) {
    return '$channel ajoutée à Multiview';
  }

  @override
  String sportsFixtureAt(String away, String home) {
    return '$away chez $home';
  }

  @override
  String sportsFixtureVs(String home, String away) {
    return '$home contre $away';
  }

  @override
  String get sportsUnavailable =>
      'Les sports ne sont pas activés sur ce serveur. Un administrateur peut les activer dans M3U Editor sous Paramètres > Intégrations > Sports.';

  @override
  String get sportsLoadFailed =>
      'Impossible de charger les matchs. Nouvelle tentative sous peu.';

  @override
  String get sportsTeamsButton => 'Équipes';

  @override
  String get sportsTeamsTitle => 'Choisissez vos équipes';

  @override
  String get sportsTeamsLoadFailed =>
      'Impossible de charger les équipes. Choisissez à nouveau la ligue pour réessayer.';

  @override
  String get sportsNoTeams => 'Aucune équipe trouvée';

  @override
  String get homeAioStreamsBrowse => 'Parcourir vos catalogues AIOStreams';

  @override
  String get homeRequestsBrowse =>
      'Rechercher et demander des films et des séries';

  @override
  String get settingsNavLayout => 'Navigation et Accueil';

  @override
  String get settingsNavLayoutSubtitle =>
      'Réorganiser ou masquer des sections dans la navigation et sur l\'Accueil';

  @override
  String get settingsManagedByServer =>
      'Géré par votre serveur. Demandez à votre administrateur de le modifier.';

  @override
  String get settingsNavLayoutHintRemote =>
      'Appuyez sur OK sur une ligne pour la saisir, déplacez-la avec Haut et Bas, puis appuyez sur OK pour la déposer. Retour annule.';

  @override
  String get settingsNavLayoutHintTouch =>
      'Faites glisser une ligne par sa poignée pour la déplacer.';

  @override
  String get settingsNavLayoutPinned =>
      'Accueil et Rechercher restent en haut, Notifications et Paramètres restent en bas, et Reprendre reste en premier sur l\'Accueil.';

  @override
  String get settingsNavLayoutColumnNav => 'Nav';

  @override
  String get settingsNavLayoutReset => 'Rétablir les valeurs par défaut';

  @override
  String get settingsNavLayoutResetMessage =>
      'Cela rétablit l\'ordre et la visibilité d\'origine de ces sections.';

  @override
  String get settingsNavLayoutResetConfirm => 'Rétablir';

  @override
  String get dvrStatusProcessing => 'Traitement';

  @override
  String get dvrStatusCompleted => 'Terminé';

  @override
  String get dvrStatusCancelled => 'Annulé';

  @override
  String get dvrFilterAll => 'Tous';

  @override
  String dvrFilterWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get dvrFilterEmpty => 'Aucun enregistrement ne correspond à ce filtre';

  @override
  String dvrSortButton(String option) {
    return 'Trier : $option';
  }

  @override
  String get dvrSortDialogTitle => 'Trier les enregistrements';

  @override
  String get dvrSortNewest => 'Plus récents en premier';

  @override
  String get dvrSortOldest => 'Plus anciens en premier';

  @override
  String get dvrSortTitle => 'Titre (A-Z)';

  @override
  String get dvrLoadError =>
      'Impossible de charger vos enregistrements. Le serveur a renvoyé une erreur.';

  @override
  String get dvrLoadOffline =>
      'Impossible de joindre votre serveur. Vérifiez votre connexion et réessayez.';

  @override
  String get dvrLoadPartial =>
      'Certains enregistrements plus anciens n\'ont pas pu être chargés.';

  @override
  String get dvrLoadRefreshFailed =>
      'Impossible d\'actualiser vos enregistrements. La dernière liste chargée est affichée.';

  @override
  String get dvrRetry => 'Réessayer';

  @override
  String get requestsProviderHeading => 'Demander à';

  @override
  String get playerAudioSync => 'Synchro audio';

  @override
  String get playerSubtitleSync => 'Synchro des sous-titres';

  @override
  String playerSyncRow(String label, String value) {
    return '$label : $value';
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
  String get playerSyncReset => 'Réinitialiser';

  @override
  String get playerSyncDone => 'Terminé';

  @override
  String get playerAudioSyncHint =>
      'Plus retarde le son, moins l\'avance. Enregistré pour cette chaîne ou ce titre.';

  @override
  String get playerSubtitleSyncHint =>
      'Plus retarde les sous-titres, moins les avance. Enregistré pour cette chaîne ou ce titre.';

  @override
  String get carPlayFavorites => 'Favoris';

  @override
  String get carPlayNoFavorites => 'Aucune chaîne favorite pour l\'instant';

  @override
  String get carPlayNoFavoritesHint =>
      'Ajoutez des chaînes en favoris dans M3U TV sur votre iPhone pour les voir ici.';

  @override
  String get carPlaySignInHint =>
      'Ouvrez M3U TV sur votre iPhone pour vous connecter.';
}
