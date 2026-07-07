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
  String get liveTvFavorite => 'Favori';

  @override
  String get liveTvRemoveFavorite => 'Retirer des favoris';

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
  String get settingsDisconnectTitle => 'Se déconnecter ?';

  @override
  String get settingsDisconnectBody =>
      'Vous serez déconnecté et devrez saisir à nouveau vos identifiants pour vous reconnecter.';

  @override
  String get settingsDisconnectConfirm => 'Déconnecter';

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
}
