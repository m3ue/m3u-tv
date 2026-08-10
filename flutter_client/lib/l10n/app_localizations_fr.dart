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
  String appRecordingScheduled(String title) {
    return 'Enregistrement programmé : $title';
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
  String get liveTvSearchHint => 'Rechercher dans la Télévision en direct…';

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
  String get playerResume => 'Reprendre';

  @override
  String get playerSkipPreviousTooltip => 'Chaîne précédente';

  @override
  String get playerSkipNextTooltip => 'Chaîne suivante';

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
  String get searchHint => 'Rechercher Télévision en direct, films et séries…';

  @override
  String get searchSectionLiveTv => 'Télévision en direct';

  @override
  String get searchSectionMovies => 'Films';

  @override
  String get searchSectionSeries => 'Série';

  @override
  String get vodSearchHint => 'Rechercher des films…';

  @override
  String get seriesSearchHint => 'Rechercher des séries…';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsGeneral => 'Général';

  @override
  String get settingsIntegrations => 'Intégrations';

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
  String get settingsClearCacheTitle => 'Vider le cache et actualiser ?';

  @override
  String get settingsClearCacheBody =>
      'Tout le contenu en cache sera effacé et rechargé depuis votre source.';

  @override
  String get settingsClearCacheConfirm => 'Vider et actualiser';

  @override
  String get settingsCacheCleared =>
      'Cache vidé — le contenu est en cours d\'actualisation en arrière-plan.';

  @override
  String get settingsContentCache => 'Cache de contenu';

  @override
  String get settingsCacheSubtitle =>
      'Le contenu en cache se charge instantanément. Les données se rafraîchissent automatiquement en arrière-plan.';

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
  String get settingsAppViewRelease => 'Voir la version';

  @override
  String get settingsAppScanQr => 'Scanner pour ouvrir sur votre téléphone';

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
  String get pairingOpenBrowser => 'Ouvrir dans le navigateur';

  @override
  String get pairingPendingGoTo =>
      'Sur votre téléphone ou ordinateur, allez sur :';

  @override
  String get pairingPendingEnterCode => 'Puis entrez ce code :';

  @override
  String get pairingPendingWaiting => 'En attente d\'approbation…';

  @override
  String get homeContinueWatching => 'Reprendre';

  @override
  String get homeNoContinueWatching => 'Rien à reprendre';

  @override
  String get homeNoLiveTv => 'Pas de Télévision en direct disponible';

  @override
  String get homeFavoriteChannels => 'Chaînes favorites';

  @override
  String get homeNoFavoriteChannels => 'Aucune chaîne favorite disponible';

  @override
  String get homeNoMovies => 'Pas de films disponibles';

  @override
  String get homeLiveChannel => 'Chaîne en direct';

  @override
  String get homeMovie => 'Film';

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
  String homeSeason(int number) {
    return 'Saison $number';
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
  String get traktDisconnectButton => 'Déconnecter Trakt';

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
  String get requestsSearchHint => 'Rechercher des films et séries…';

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
  String get dvrRecordingsTitle => 'Enregistrements DVR';

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
  String get dvrSeriesRulesTitle => 'Règles de séries';

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
  String get settingsEpgStartView => 'Le guide démarre à';

  @override
  String get settingsEpgStartViewCurrentTime => 'Heure actuelle';

  @override
  String get settingsEpgStartViewPrimeTime => 'Prime time';
}
