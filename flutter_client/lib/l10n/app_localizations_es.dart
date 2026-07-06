// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get navHome => 'Inicio';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navLiveTv => 'TV en vivo';

  @override
  String get navVod => 'Películas';

  @override
  String get navSeries => 'Series';

  @override
  String get navDvr => 'DVR';

  @override
  String get navRequests => 'Solicitudes';

  @override
  String get navNotifications => 'Notificaciones';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navMore => 'Más';

  @override
  String get appBackToExit => 'Pulse atrás de nuevo para salir';

  @override
  String appRecordingScheduled(String title) {
    return 'Grabación programada: $title';
  }

  @override
  String appRecordingFailed(String error) {
    return 'No se pudo programar la grabación: $error';
  }

  @override
  String get appNotConfigured => 'Conecta tu servicio en Ajustes';

  @override
  String get cancel => 'Cancelar';

  @override
  String get disconnect => 'Desconectar';

  @override
  String get unknown => 'Desconocido';

  @override
  String get admin => 'Admin';

  @override
  String get liveTvSearchHint => 'Buscar TV en vivo…';

  @override
  String get liveTvNoChannels => 'No hay canales disponibles';

  @override
  String get liveTvAllChannels => 'Todos los canales';

  @override
  String get liveTvFavorites => '★ Favoritos';

  @override
  String get liveTvNoProgram => 'Sin información de programa';

  @override
  String get liveTvNext => 'SIGUIENTE';

  @override
  String get liveTvRecord => 'Grabar';

  @override
  String get liveTvFavorite => 'Favorito';

  @override
  String get liveTvRemoveFavorite => 'Quitar de favoritos';

  @override
  String get playerGoBack => 'Volver';

  @override
  String get playerResumeWatching => 'Continuar viendo';

  @override
  String get playerContinue => 'Continuar';

  @override
  String playerFromTime(String time) {
    return 'Desde $time';
  }

  @override
  String get playerStartFromBeginning => 'Empezar desde el principio';

  @override
  String get playerResume => 'Reanudar';

  @override
  String get searchHint => 'Buscar TV en vivo, películas y series…';

  @override
  String get searchSectionLiveTv => 'TV en vivo';

  @override
  String get searchSectionMovies => 'Películas';

  @override
  String get searchSectionSeries => 'Series';

  @override
  String get vodSearchHint => 'Buscar películas…';

  @override
  String get seriesSearchHint => 'Buscar series…';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsIntegrations => 'Integraciones';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Idioma del sistema';

  @override
  String get settingsLangEnglish => 'Inglés';

  @override
  String get settingsLangGerman => 'Alemán';

  @override
  String get settingsLangSpanish => 'Español';

  @override
  String get settingsLangFrench => 'Francés';

  @override
  String get settingsLangChinese => 'Chino (Simplificado)';

  @override
  String get settingsConnection => 'Conexión';

  @override
  String get settingsStatusConnected => 'Conectado';

  @override
  String get settingsStatusUnavailable => 'No disponible';

  @override
  String get settingsStatusLabel => 'Estado';

  @override
  String get settingsSourceLabel => 'Fuente';

  @override
  String get settingsLastError => 'Último error';

  @override
  String get settingsRetryConnection => 'Reintentar conexión';

  @override
  String get settingsEditServer => 'Editar configuración del servidor';

  @override
  String get settingsActiveViewer => 'Usuario activo';

  @override
  String get settingsClearCacheTitle => '¿Borrar caché y actualizar?';

  @override
  String get settingsClearCacheBody =>
      'Todo el contenido en caché se borrará y se volverá a cargar desde tu fuente.';

  @override
  String get settingsClearCacheConfirm => 'Borrar y actualizar';

  @override
  String get settingsCacheCleared =>
      'Caché borrada — el contenido se está actualizando en segundo plano.';

  @override
  String get settingsContentCache => 'Caché de contenido';

  @override
  String get settingsCacheSubtitle =>
      'El contenido en caché carga al instante. Los datos se actualizan automáticamente en segundo plano.';

  @override
  String get settingsEpgRefreshInterval => 'Intervalo de actualización de EPG';

  @override
  String settingsEpgDurationMinutes(int count) {
    return '$count min';
  }

  @override
  String get settingsEpgDurationHour => '1 hora';

  @override
  String settingsEpgDurationHours(int count) {
    return '$count horas';
  }

  @override
  String get settingsManageViewers => 'Gestionar usuarios';

  @override
  String get settingsAddViewer => 'Nuevo usuario';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get settingsDisconnectTitle => '¿Desconectar?';

  @override
  String get settingsDisconnectBody =>
      'Se cerrará tu sesión y deberás volver a introducir tus credenciales para reconectarte.';

  @override
  String get settingsDisconnectConfirm => 'Desconectar';

  @override
  String get homeContinueWatching => 'Continuar viendo';

  @override
  String get homeNoContinueWatching => 'Nada para continuar viendo';

  @override
  String get homeNoLiveTv => 'No hay TV en vivo disponible';

  @override
  String get homeNoMovies => 'No hay películas disponibles';

  @override
  String get homeLiveChannel => 'Canal en vivo';

  @override
  String get homeMovie => 'Película';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get notificationsTabNotifications => 'Notificaciones';

  @override
  String get notificationsTabChannelSettings => 'Ajustes de canales';

  @override
  String get notificationsMarkAllRead => 'Marcar todo como leído';

  @override
  String get notificationsEmpty => 'Aún no hay notificaciones';

  @override
  String get notificationsEmptyFiltered =>
      'No hay notificaciones para tus canales suscritos';

  @override
  String get notificationsChannelSubscriptions => 'Suscripciones de canales';

  @override
  String get notificationsChannelSubtitle =>
      'Selecciona qué canales quieres recibir. Deja todos sin seleccionar para recibir todo.';

  @override
  String get notificationsAllChannels => 'Todos los canales';

  @override
  String get notificationsNoChannels =>
      'Aún no hay canales — aparecerán aquí cuando lleguen notificaciones.';

  @override
  String get notificationsJustNow => 'justo ahora';

  @override
  String notificationsMinutesAgo(int count) {
    return 'hace ${count}m';
  }

  @override
  String notificationsHoursAgo(int count) {
    return 'hace ${count}h';
  }

  @override
  String notificationsDaysAgo(int count) {
    return 'hace ${count}d';
  }

  @override
  String notificationsReceivedAt(String time) {
    return 'Recibido $time';
  }

  @override
  String notificationsReadAt(String time) {
    return 'Leído $time';
  }

  @override
  String get homeNoSeries => 'No hay series disponibles';

  @override
  String homeSeason(int number) {
    return 'Temporada $number';
  }

  @override
  String get traktWatchHistory => 'Historial de visionado';

  @override
  String get traktWatchHistorySubtitle =>
      'Sincroniza tu historial de visionado con Trakt para seguir el progreso entre apps y servicios.';

  @override
  String get traktNotConfigured =>
      'Las credenciales del cliente Trakt no están configuradas.';

  @override
  String get traktNotConfiguredHint =>
      'Registra una app en trakt.tv/oauth/applications y establece el client ID y secret vía --dart-define en tiempo de compilación.';

  @override
  String get traktConnectPrompt =>
      'Conecta tu cuenta de Trakt para registrar automáticamente lo que ves.';

  @override
  String get traktConnectButton => 'Conectar con Trakt';

  @override
  String get traktScanQr => 'Escanear para abrir en tu teléfono';

  @override
  String get traktOpenBrowser => 'Abrir en el navegador';

  @override
  String get traktPendingGoTo => 'En tu teléfono u ordenador, ve a:';

  @override
  String get traktPendingEnterCode => 'Luego introduce este código:';

  @override
  String get traktPendingWaiting => 'Esperando autorización…';

  @override
  String get traktConnected => 'Conectado a Trakt';

  @override
  String get traktDisconnectButton => 'Desconectar Trakt';

  @override
  String get vodAllMovies => 'Todas las películas';

  @override
  String get seriesAllSeries => 'Todas las series';

  @override
  String homeConnectedSource(String label) {
    return 'Fuente conectada: $label';
  }

  @override
  String get searchTypeToSearch => 'Escribe para buscar';
}
