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
  String get navLiveTv => 'Televisión en vivo';

  @override
  String get navVod => 'Cine';

  @override
  String get navSeries => 'Serie';

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
  String get notificationsDesktopOpen => 'Abrir';

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
  String get admin => 'Administración';

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
  String get liveTvSearchHint => 'Buscar…';

  @override
  String get liveTvUpcomingAirings => 'Próximamente';

  @override
  String get liveTvSearchFilterAll => 'Todo';

  @override
  String get liveTvShowResultsLoading => 'Buscando programas…';

  @override
  String get liveTvOnNow => 'En vivo';

  @override
  String liveTvAiringUntil(String time) {
    return 'Hasta $time';
  }

  @override
  String liveTvAiringTomorrow(String time) {
    return 'Mañana $time';
  }

  @override
  String liveTvMoreAirings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count más',
      one: '+1 más',
    );
    return '$_temp0';
  }

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
  String get liveTvRecording => 'Grabando';

  @override
  String get liveTvFavorite => 'Favorito';

  @override
  String get liveTvRemoveFavorite => 'Quitar de favoritos';

  @override
  String get liveTvCatchupShows => 'Programas de catchup';

  @override
  String get catchupShowsEmpty => 'No hay programas de catchup disponibles';

  @override
  String get liveTvAddMultiview => 'Añadir a Multivista';

  @override
  String get liveTvRemoveMultiview => 'Quitar de Multivista';

  @override
  String get liveTvMultiviewFull =>
      'Multivista está lleno (máx. 9 transmisiones)';

  @override
  String get multiviewTitle => 'Multivista';

  @override
  String get multiviewEmpty =>
      'Sin transmisiones - mantén pulsado un canal en Live TV y elige Añadir a Multivista';

  @override
  String get multiviewMove => 'Mover';

  @override
  String get multiviewOpenFullscreen => 'Abrir en pantalla completa';

  @override
  String get multiviewMakeFeatured => 'Destacar';

  @override
  String get multiviewPictureInPicture => 'Imagen en imagen';

  @override
  String get multiviewBackToGrid => 'Volver a la cuadrícula';

  @override
  String get multiviewRemove => 'Quitar de Multivista';

  @override
  String get multiviewRetry =>
      'No se pudo reproducir - selecciona para reintentar';

  @override
  String get multiviewManageTitle => 'Gestionar Multivista';

  @override
  String get multiviewClearAll => 'Quitar todo';

  @override
  String multiviewRemoveChannel(String channel) {
    return 'Quitar $channel';
  }

  @override
  String get close => 'Cerrar';

  @override
  String get catchupBadgeAvailable => 'Catchup disponible';

  @override
  String catchupBadgeAvailableDays(int days) {
    return 'Catchup disponible: $days d';
  }

  @override
  String get catchupProgramReplayable => 'Repetición por catchup disponible';

  @override
  String get epgPreviousDay => 'Día anterior';

  @override
  String get epgNow => 'Ahora';

  @override
  String get epgNextDay => 'Día siguiente';

  @override
  String get epgChannels => 'CANALES';

  @override
  String get epgNoData => 'No hay datos de EPG';

  @override
  String get epgProgramScheduledToRecord => 'Programado para grabar';

  @override
  String get epgProgramCurrentlyRecording => 'Grabando ahora';

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
  String get playerSkipPreviousTooltip => 'Canal anterior';

  @override
  String get playerSkipNextTooltip => 'Canal siguiente';

  @override
  String get playerNowPlayingMovie => 'Película';

  @override
  String get playerNowPlayingSeries => 'Serie';

  @override
  String playerNowPlayingSeasonEpisode(int season, int episode) {
    return 'T$season · E$episode';
  }

  @override
  String get playerCommercialSkipped => 'Anuncio omitido';

  @override
  String get playerSkipCommercial => 'Omitir anuncio';

  @override
  String get playerSkipCredits => 'Omitir créditos';

  @override
  String get playerSkipIntro => 'Omitir introducción';

  @override
  String get searchHint => 'Buscar Televisión en vivo, cine y series…';

  @override
  String get searchSectionLiveTv => 'Televisión en vivo';

  @override
  String get searchSectionMovies => 'Cine';

  @override
  String get searchSectionSeries => 'Serie';

  @override
  String get vodSearchHint => 'Buscar…';

  @override
  String get seriesSearchHint => 'Buscar…';

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
  String get settingsServerTimezone => 'Zona horaria del servidor';

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
  String get settingsSwitchViewer => 'Cambiar usuario';

  @override
  String get settingsViewerNameLabel => 'Nombre de usuario';

  @override
  String get settingsCreate => 'Crear';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get settingsProxyPlayback => 'Reproducción por proxy';

  @override
  String get settingsProxyPlaybackSubtitle =>
      'Transmite a través del proxy de m3u-editor con un perfil de transcodificación opcional para este dispositivo.';

  @override
  String get settingsProxyUse => 'Usar proxy';

  @override
  String get settingsProxyForced =>
      'El proxy está habilitado a nivel de lista y no se puede desactivar.';

  @override
  String get settingsProxyLiveProfile => 'Perfil de transcodificación en vivo';

  @override
  String get settingsProxyVodProfile =>
      'Perfil de transcodificación de VOD y series';

  @override
  String get settingsProxyProfileDefault => 'Predeterminado';

  @override
  String get settingsProxyProfileDirect => 'Directo (sin transcodificación)';

  @override
  String get settingsProxyNoProfiles =>
      'No hay perfiles de transcodificación disponibles; las transmisiones usan el proxy directo.';

  @override
  String get settingsDvr => 'DVR';

  @override
  String get settingsDvrSubtitle =>
      'Ajustes para la reproducción de contenido grabado.';

  @override
  String get settingsComskip => 'Omisión de anuncios';

  @override
  String get settingsComskipSubtitle =>
      'Controla cómo reacciona el reproductor a los anuncios detectados en las grabaciones DVR.';

  @override
  String get settingsComskipAutoSkip => 'Omitir anuncios automáticamente';

  @override
  String get settingsDisconnectTitle => '¿Desconectar?';

  @override
  String get settingsDisconnectBody =>
      'Se cerrará tu sesión y deberás volver a introducir tus credenciales para reconectarte.';

  @override
  String get settingsDisconnectConfirm => 'Desconectar';

  @override
  String get settingsApp => 'Aplicación';

  @override
  String get settingsAppVersion => 'Versión';

  @override
  String get settingsAppUpdateStatus => 'Actualización';

  @override
  String get settingsAppVersionChecking => 'Buscando actualizaciones…';

  @override
  String get settingsAppUpToDate => 'Actualizado';

  @override
  String settingsAppUpdateAvailable(String version) {
    return 'Actualización disponible: $version';
  }

  @override
  String get settingsAppViewRelease => 'Ver versión';

  @override
  String get settingsAppScanQr => 'Escanear para abrir en tu teléfono';

  @override
  String get settingsFillAllFields => 'Por favor completa todos los campos';

  @override
  String get settingsConnectionSettings => 'Configuración de conexión';

  @override
  String get settingsConnectionSettingsSubtitle =>
      'Ingresa los datos de tu Xtream Codes';

  @override
  String get settingsConnectionSettingsHelp =>
      'Usa los datos de conexión Xtream de la lista de reproducción de m3u-editor, no tu inicio de sesión web de m3u-editor. Necesitas la URL del servidor, el nombre de usuario Xtream y la contraseña Xtream.';

  @override
  String get settingsServerUrl => 'URL del servidor';

  @override
  String get settingsUsername => 'Usuario';

  @override
  String get settingsPassword => 'Contraseña';

  @override
  String get settingsConnect => 'Conectar';

  @override
  String get settingsPairWithCode => 'Vincular con código';

  @override
  String get settingsTabPair => 'Vincular';

  @override
  String get settingsTabSignIn => 'Iniciar sesión';

  @override
  String get settingsPairTabSubtitle =>
      'Introduce la dirección de tu servidor y luego vincula este televisor con un código.';

  @override
  String get pairingEnterServerFirst => 'Ingresa primero la URL de tu servidor';

  @override
  String get pairingErrorGeneric =>
      'La vinculación falló o el código expiró. Inténtalo de nuevo.';

  @override
  String get pairingScanQr =>
      'Escanea para abrir la página de vinculación en tu teléfono';

  @override
  String get pairingOpenBrowser => 'Abrir en el navegador';

  @override
  String get pairingPendingGoTo => 'En tu teléfono u ordenador, ve a:';

  @override
  String get pairingPendingEnterCode => 'Código de emparejamiento:';

  @override
  String get pairingPendingWaiting => 'Esperando aprobación…';

  @override
  String get homeContinueWatching => 'Continuar viendo';

  @override
  String get homeNoContinueWatching => 'Nada para continuar viendo';

  @override
  String get homeContinueWatchingSeeAll => 'Ver todo';

  @override
  String homeContinueWatchingMoreCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count más',
      one: '+1 más',
    );
    return '$_temp0';
  }

  @override
  String get homeNoLiveTv => 'No hay Televisión en vivo disponible';

  @override
  String get homeFavoriteChannels => 'Canales favoritos';

  @override
  String get homeNoFavoriteChannels => 'No hay canales favoritos disponibles';

  @override
  String get homeNoMovies => 'No hay cine disponible';

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
  String get vodAllMovies => 'Todo el cine';

  @override
  String get seriesAllSeries => 'Todas las series';

  @override
  String homeConnectedSource(String label) {
    return 'Fuente conectada: $label';
  }

  @override
  String get searchTypeToSearch => 'Escribe para buscar';

  @override
  String get vodPlayMovie => 'Reproducir película';

  @override
  String get vodContinueMovie => 'Continuar película';

  @override
  String vodTimeLeftMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Quedan $minutes min',
      one: 'Queda 1 min',
    );
    return '$_temp0';
  }

  @override
  String vodTimeLeftHoursMinutes(int hours, int minutes) {
    return 'Quedan $hours h $minutes min';
  }

  @override
  String get navAioStreams => 'AIOStreams';

  @override
  String get aiostreamsGetStreams => 'Obtener fuentes';

  @override
  String get aiostreamsLoadingStreams => 'Cargando fuentes…';

  @override
  String get aiostreamsNoStreams => 'No se encontraron fuentes';

  @override
  String get aiostreamsSelectStream => 'Seleccionar fuente';

  @override
  String get aiostreamsLoadMore => 'Cargar más';

  @override
  String get aiostreamsSearchHint => 'Buscar películas y series…';

  @override
  String get aiostrreamsCatalogEmpty => 'Nada aquí todavía';

  @override
  String get aiostreamsToggleFavorite => 'Favorito';

  @override
  String get aiostreamsMyFavorites => 'Mis Favoritos';

  @override
  String get aiostreamsContinueWatching => 'Continuar Viendo';

  @override
  String get aiostreamsSearch => 'Buscar en AIOStreams';

  @override
  String get aiostreamsSearchResults => 'Resultados de búsqueda';

  @override
  String get aiostreamsNoResults => 'No se encontraron resultados';

  @override
  String get aiostreamsSearchAll => 'Todo';

  @override
  String get requestsTitle => 'Solicitudes';

  @override
  String get requestsTabSearch => 'Buscar';

  @override
  String get requestsTabMyRequests => 'Mis Solicitudes';

  @override
  String get requestsSearchHint => 'Buscar…';

  @override
  String get requestsNoResults => 'No se encontraron resultados';

  @override
  String get requestsAlreadyAvailable => 'Ya disponible';

  @override
  String get requestsAlreadyRequested => 'Ya solicitado';

  @override
  String get requestsRequestButton => 'Solicitar';

  @override
  String get requestsSeasonsHeading => 'Temporadas';

  @override
  String get requestsSeasonSpecials => 'Especiales';

  @override
  String get requestsSelectAllSeasons => 'Seleccionar todo';

  @override
  String get requestsClearSeasons => 'Borrar';

  @override
  String requestsSubmitted(String title) {
    return '\"$title\" fue solicitado';
  }

  @override
  String requestsSubmittedPendingApproval(String title) {
    return '\"$title\" fue enviado para aprobación';
  }

  @override
  String requestsSubmitFailed(String title, String error) {
    return 'No se pudo solicitar \"$title\": $error';
  }

  @override
  String get requestsMyRequestsEmpty => 'Todavía no has solicitado nada';

  @override
  String get requestsDismiss => 'Descartar';

  @override
  String requestsDismissFailed(String error) {
    return 'No se pudo descartar la solicitud: $error';
  }

  @override
  String get requestsStatusPendingApproval => 'Pendiente de Aprobación';

  @override
  String get requestsStatusApproved => 'Aprobado';

  @override
  String get requestsStatusRejected => 'Rechazado';

  @override
  String get requestsStatusCompleted => 'Completado';

  @override
  String get requestsStatusUnknown => 'Desconocido';

  @override
  String get dvrRecordingsTitle => 'Grabaciones DVR';

  @override
  String get dvrRecordingsSubtitle => 'Grabaciones completadas y en curso';

  @override
  String get dvrNoRecordings => 'No hay grabaciones DVR disponibles';

  @override
  String get dvrNotConfigured =>
      'Por favor, conéctate a tu servicio en Ajustes';

  @override
  String get dvrCancel => 'Cancelar';

  @override
  String get dvrDelete => 'Eliminar';

  @override
  String dvrStopTitle(String title) {
    return 'Detener grabación — $title';
  }

  @override
  String get dvrStopMessage =>
      '¿Mantenerla en tu lista de grabaciones o eliminarla ahora?';

  @override
  String get dvrStopKeep => 'Mantener grabación';

  @override
  String get dvrStopDelete => 'Eliminar grabación';

  @override
  String get dvrStopBack => 'Atrás';

  @override
  String get dvrCancelSuccess => 'Grabación cancelada';

  @override
  String get dvrCancelFailed => 'No se pudo cancelar la grabación';

  @override
  String get dvrDeleteTitle => '¿Eliminar grabación?';

  @override
  String get dvrDeleteMessage => 'Esta grabación se eliminará permanentemente.';

  @override
  String get dvrDeleteDismiss => 'Mantener';

  @override
  String get dvrDeleteConfirm => 'Eliminar grabación';

  @override
  String get dvrDeleteSuccess => 'Grabación eliminada';

  @override
  String get dvrDeleteFailed => 'No se pudo eliminar la grabación';

  @override
  String get liveTvStopRecording => 'Detener grabación';

  @override
  String get playerRecordNowTooltip => 'Grabar programa actual';

  @override
  String get playerStopRecordingTooltip => 'Detener grabación';

  @override
  String get dvrMoreActions => 'Más acciones';

  @override
  String get dvrPlay => 'Reproducir';

  @override
  String get dvrSelect => 'Seleccionar';

  @override
  String get dvrStop => 'Detener';

  @override
  String get dvrStatusRecording => 'Grabando';

  @override
  String get dvrStatusScheduled => 'Programada';

  @override
  String get dvrStatusFailed => 'Fallida';

  @override
  String get dvrExitSelection => 'Salir de la selección';

  @override
  String dvrSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos seleccionados',
      one: '1 elemento seleccionado',
      zero: 'Ningún elemento seleccionado',
    );
    return '$_temp0';
  }

  @override
  String get dvrStorageTitle => 'Almacenamiento DVR';

  @override
  String get dvrStorageUnlimited => 'Ilimitado';

  @override
  String dvrStorageUsedUnlimited(String used) {
    return '$used utilizado';
  }

  @override
  String dvrStorageUsedWithQuota(String used, String quota) {
    return '$used de $quota utilizado';
  }

  @override
  String dvrStorageRecordingCount(int count) {
    return '$count grabaciones';
  }

  @override
  String get dvrSeriesChannel => 'Canal';

  @override
  String get dvrSeriesStartEarly => 'Iniciar antes';

  @override
  String get dvrSeriesUseDefault => 'Predeterminado';

  @override
  String dvrEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios',
      one: '1 episodio',
    );
    return '$_temp0';
  }

  @override
  String get dvrDeleteSeriesRule => 'Eliminar regla';

  @override
  String get dvrEditSeriesRule => 'Editar regla';

  @override
  String get dvrUpdateSeriesRuleFailed =>
      'No se pudo actualizar la regla de serie';

  @override
  String get dvrSeriesSave => 'Guardar';

  @override
  String get dvrSeriesSecondsSuffix => 'seg';

  @override
  String get dvrSeriesMode => 'Modo de serie';

  @override
  String get dvrUpdateSeriesRuleSuccess => 'Regla de serie actualizada';

  @override
  String get dvrSeriesModeAll => 'Todos los episodios';

  @override
  String get dvrSeriesMatchModeStartsWith => 'Comienza con';

  @override
  String get dvrDeleteSeriesRuleConfirm => '¿Eliminar esta regla de serie?';

  @override
  String get dvrSeriesCancel => 'Cancelar';

  @override
  String get dvrDeleteSeriesRuleSuccess => 'Regla de serie eliminada';

  @override
  String get dvrSeriesRulesTitle => 'Reglas de series';

  @override
  String get dvrSeriesMatchModeContains => 'Contiene';

  @override
  String get dvrSeriesMatchModeExact => 'Exacto';

  @override
  String get dvrSeriesModeUseDefault => 'Predeterminado';

  @override
  String get dvrSeriesModeNewFlag => 'Solo nuevos';

  @override
  String get dvrDeleteSeriesRuleFailed =>
      'No se pudo eliminar la regla de serie';

  @override
  String get dvrSeriesKeepLast => 'Mantener última';

  @override
  String get dvrSeriesModeUniqueSe => 'S-E único';

  @override
  String get dvrSeriesAnyChannel => 'Cualquier canal';

  @override
  String get dvrSeriesMatchMode => 'Modo de coincidencia';

  @override
  String get dvrSeriesEndLate => 'Terminar tarde';

  @override
  String get dvrSeriesOptions => 'Opciones';

  @override
  String dvrSeriesOptionsFor(String title) {
    return 'Opciones: $title';
  }

  @override
  String get dvrSeriesAllEpisodesWarning =>
      'Grabar todos los episodios en cualquier canal puede crear duplicados — usa Solo nuevos o S-E único para desduplicar.';

  @override
  String get dvrSeriesRulesEmpty => 'No hay reglas de series';

  @override
  String get dvrSeriesPriority => 'Prioridad';

  @override
  String get epgRecordSeries => 'Grabar serie';

  @override
  String epgRecordSeriesSuccess(String title) {
    return 'Grabación de serie configurada para $title';
  }

  @override
  String get epgRecordSeriesFailed =>
      'No se pudo configurar la grabación de la serie';

  @override
  String get epgRecordSeriesDuplicate =>
      'La grabación de la serie ya está configurada';

  @override
  String get navShows => 'Shows';

  @override
  String get showAiringNext => 'Próxima emisión';

  @override
  String get showAiringNone => 'No hay episodios próximos en la EPG';

  @override
  String showChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count canales',
      one: '1 canal',
    );
    return '$_temp0';
  }

  @override
  String get showDeleteRule => 'Eliminar regla de serie';

  @override
  String showDeleteRuleConfirm(String title) {
    return '¿Eliminar la regla de serie para $title? Los episodios futuros no se grabarán. Las grabaciones ya realizadas no se eliminarán.';
  }

  @override
  String get showSeriesRuleActive => 'Regla de serie activa';

  @override
  String get showScheduled => 'Programada';

  @override
  String showBatchRecord(int count) {
    return 'Grabar ($count)';
  }

  @override
  String showBatchScheduleSummary(int scheduled, int failed) {
    String _temp0 = intl.Intl.pluralLogic(
      scheduled,
      locale: localeName,
      other: 'Se programaron $scheduled episodios',
      one: 'Se programó 1 episodio',
    );
    String _temp1 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: 'Fallaron $failed.',
      one: 'Falló 1.',
      zero: 'Todos exitosos.',
    );
    return '$_temp0. $_temp1';
  }

  @override
  String showBatchScheduleFailures(String titles) {
    return 'Fallaron: $titles';
  }

  @override
  String get showDetailTitle => 'Detalles del show';

  @override
  String showEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodios',
      one: '1 episodio',
    );
    return '$_temp0';
  }

  @override
  String get showRecordSeries => 'Grabar serie';

  @override
  String showRecordSeriesConfirm(String title, String channel) {
    return '¿Grabar cada episodio de $title en $channel?';
  }

  @override
  String showRecordSeriesFailed(String title) {
    return 'No se pudo configurar la grabación de la serie para $title';
  }

  @override
  String showRecordSeriesSuccess(String title) {
    return 'Grabación de serie configurada para $title';
  }

  @override
  String showRecordSeriesDuplicate(String title) {
    return 'La grabación de la serie ya está configurada para $title';
  }

  @override
  String get showsError => 'No se pudieron buscar shows';

  @override
  String get showsNoResults => 'Ningún show coincide con tu búsqueda';

  @override
  String get showsSearchError => 'Búsqueda fallida';

  @override
  String get showsSearchHint => 'Buscar shows por título';

  @override
  String get showsTitle => 'Shows';

  @override
  String showNotFound(String title) {
    return 'Show «$title» no encontrado';
  }

  @override
  String get settingsView => 'Vista';

  @override
  String get settingsLiveTvLayout => 'Diseño de TV en vivo';

  @override
  String get settingsLiveTvLayoutList => 'Lista';

  @override
  String get settingsLiveTvLayoutGrid => 'Cuadrícula';

  @override
  String get settingsLiveTvLayoutTimeline => 'Línea temporal';

  @override
  String get settingsLiveTvChannelColumn => 'Columna de canales';

  @override
  String get settingsLiveTvChannelColumnLogoTitle => 'Logo + Título';

  @override
  String get settingsLiveTvChannelColumnLogoOnly => 'Solo logo';

  @override
  String get settingsLiveTvChannelColumnTitleOnly => 'Solo título';

  @override
  String get settingsEpgStartView => 'La guía empieza a las';

  @override
  String get settingsEpgStartViewCurrentTime => 'Hora actual';

  @override
  String get settingsEpgStartViewPrimeTime => 'Horario estelar';

  @override
  String get settingsDefaultStartPage => 'Página de inicio predeterminada';

  @override
  String get settingsHdrMode => 'Modo HDR';

  @override
  String get settingsHdrModeHint =>
      'Permite que los vídeos HDR cambien la pantalla al modo HDR. Solo Windows y Linux.';

  @override
  String get settingsMatchRefreshRate => 'Ajustar frecuencia de actualización';

  @override
  String get settingsMatchRefreshRateHint =>
      'Cambia el monitor a la frecuencia de fotogramas del vídeo al iniciar la reproducción. Puede dejar la pantalla en negro un instante. Solo Windows.';

  @override
  String get settingsToggleOn => 'Activado';

  @override
  String get settingsToggleOff => 'Desactivado';
}
