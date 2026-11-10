import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/features/settings/diagnostics_screen.dart';
import 'package:m3u_tv/features/settings/release_notes_view.dart';
import 'package:m3u_tv/features/settings/sections/app_version_card.dart';
import 'package:m3u_tv/features/settings/sections/online_subtitle_settings_group.dart';
import 'package:m3u_tv/features/settings/sections/playback_settings_page.dart';
import 'package:m3u_tv/features/settings/sections/playlists_page.dart';
import 'package:m3u_tv/features/settings/sections/settings_status_row.dart';
import 'package:m3u_tv/features/settings/sections/simkl_card.dart';
import 'package:m3u_tv/features/settings/sections/storage_page.dart';
import 'package:m3u_tv/features/settings/sections/trakt_card.dart';
import 'package:m3u_tv/features/settings/sections/view_settings_section.dart';
import 'package:m3u_tv/features/settings/sections/viewer_management_dialog.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/online_subtitle_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';
import 'package:m3u_tv/services/simkl_service.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// Connected settings view
// ---------------------------------------------------------------------------

class ConnectedView extends StatefulWidget {
  const ConnectedView({
    super.key,
    required this.authNotifier,
    required this.traktService,
    required this.simklService,
    this.onlineSubtitleSettings,
    this.activeViewer,
    this.viewers = const [],
    this.sourceLabel,
    this.serverTimezone,
    this.sourceError,
    required this.onDisconnect,
    this.onSwitchViewer,
    this.onCreateViewer,
    this.onClearCache,
    this.loadDiagnosticsHeader,
    this.onUploadLogs,
    this.locale,
    this.onLocaleChanged,
    this.proxyPlaybackSettings,
    this.comskipSettings,
    this.introDbSettings,
    this.viewSettingsService,
    this.deviceType,
    this.onHandleTopLevelBack,
    this.playlists,
    this.storage,
    this.devicePairingService,
    this.onPlaylistSwitched,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final SimklService simklService;
  final OnlineSubtitleSettings? onlineSubtitleSettings;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final IntroDbSettings? introDbSettings;
  final ViewSettingsService? viewSettingsService;
  final DeviceType? deviceType;
  final bool Function()? onHandleTopLevelBack;
  final Viewer? activeViewer;
  final List<Viewer> viewers;
  final String? sourceLabel;
  final String? serverTimezone;
  final String? sourceError;
  final VoidCallback onDisconnect;
  final void Function(Viewer viewer)? onSwitchViewer;
  final Future<Viewer?> Function(String name)? onCreateViewer;
  final ValueChanged<CacheClearScope>? onClearCache;
  final Future<String> Function()? loadDiagnosticsHeader;
  final Future<int> Function(String report)? onUploadLogs;
  final Locale? locale;
  final void Function(Locale?)? onLocaleChanged;

  /// Saved playlists. The Playlists row is hidden when null.
  final PlaylistManagement? playlists;

  /// What the app stores on the device. The Storage row is hidden when null.
  final StorageManagement? storage;

  /// For pairing a new playlist from the Playlists page.
  final DevicePairingService? devicePairingService;

  /// Runs after the Playlists page switches to, or adds, a playlist.
  final VoidCallback? onPlaylistSwitched;

  @override
  State<ConnectedView> createState() => _ConnectedViewState();
}

class _ConnectedViewState extends State<ConnectedView> {
  void _openViewerManagement(BuildContext context) {
    showAppDialog<void>(
      context: context,
      builder: (_) => ViewerManagementDialog(
        viewers: widget.viewers.isNotEmpty
            ? widget.viewers
            : [widget.activeViewer!],
        activeViewer: widget.activeViewer!,
        onSwitch: widget.onSwitchViewer ?? (_) {},
        onCreateViewer: widget.onCreateViewer,
      ),
    );
  }

  Future<void> _handleDisconnect() async {
    final l = AppLocalizations.of(context);
    final hasOtherPlaylists =
        (widget.playlists?.service.playlists.length ?? 0) > 1;
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsDisconnectTitle,
      message: hasOtherPlaylists
          ? l.settingsDisconnectBodyOtherPlaylists
          : l.settingsDisconnectBody,
      confirmLabel: l.settingsDisconnectConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    widget.onDisconnect();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = widget.authNotifier.authResponse;
    final hasViewSettings = widget.viewSettingsService != null;

    return SettingsScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                title: l.settingsGeneral,
                subtitle: l.settingsGeneralSubtitle,
                icon: Icons.settings_outlined,
                trailing: const SettingsChevron(),
                autofocus: true,
                onTap: () => unawaited(
                  pushSettingsSubpage<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsGeneral,
                    onBack: widget.onHandleTopLevelBack,
                    builder: _buildGeneralPageBody,
                  ),
                ),
              ),
              if (hasViewSettings)
                SettingsRow(
                  title: l.settingsAppearance,
                  subtitle: l.settingsAppearanceSubtitle,
                  icon: Icons.palette_outlined,
                  trailing: const SettingsChevron(),
                  onTap: () => unawaited(
                    pushSettingsSubpage<void>(
                      context,
                      title: (context) =>
                          AppLocalizations.of(context).settingsAppearance,
                      onBack: widget.onHandleTopLevelBack,
                      builder: (_) => ViewSettingsSection(
                        service: widget.viewSettingsService!,
                        deviceType: widget.deviceType,
                        onHandleTopLevelBack: widget.onHandleTopLevelBack,
                      ),
                    ),
                  ),
                ),
              SettingsRow(
                title: l.settingsPlayback,
                subtitle: l.settingsPlaybackSubtitle,
                icon: Icons.play_circle_outline,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsSubpage<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsPlayback,
                    onBack: widget.onHandleTopLevelBack,
                    builder: (_) => PlaybackSettingsPage(
                      proxyCapability: auth?.proxy,
                      proxyPlaybackSettings: widget.proxyPlaybackSettings,
                      comskipSettings: widget.comskipSettings,
                      viewSettingsService: widget.viewSettingsService,
                      onHandleTopLevelBack: widget.onHandleTopLevelBack,
                      isTv: widget.deviceType == DeviceType.tv,
                    ),
                  ),
                ),
              ),
              if (widget.storage case final storage?)
                SettingsRow(
                  title: l.settingsStorage,
                  subtitle: l.settingsStorageSubtitle,
                  icon: Icons.storage_outlined,
                  trailing: const SettingsChevron(),
                  onTap: () => unawaited(
                    pushSettingsSubpage<void>(
                      context,
                      title: (context) =>
                          AppLocalizations.of(context).settingsStorage,
                      onBack: widget.onHandleTopLevelBack,
                      builder: (_) => StoragePage(
                        storage: storage,
                        onHandleTopLevelBack: widget.onHandleTopLevelBack,
                      ),
                    ),
                  ),
                ),
              SettingsRow(
                title: l.settingsIntegrations,
                subtitle: l.settingsIntegrationsSubtitle,
                icon: Icons.sync_alt,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsSubpage<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsIntegrations,
                    onBack: widget.onHandleTopLevelBack,
                    builder: (_) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsSectionHeader(l.settingsSectionServices),
                        ListenableBuilder(
                          listenable: widget.simklService,
                          builder: (context, _) => SettingsCard(
                            child: SimklCard(
                              simklService: widget.simklService,
                              serverAccount: auth?.serverWatchHistory('simkl'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListenableBuilder(
                          listenable: widget.traktService,
                          builder: (context, _) => SettingsCard(
                            child: TraktCard(
                              traktService: widget.traktService,
                              serverAccount: auth?.serverWatchHistory('trakt'),
                            ),
                          ),
                        ),
                        if (widget.introDbSettings != null) ...[
                          const SizedBox(height: 12),
                          ListenableBuilder(
                            listenable: widget.introDbSettings!,
                            builder: (context, _) => SettingsGroup(
                              children: [
                                SettingsSwitchRow(
                                  title: l.settingsIntroDb,
                                  subtitle: l.settingsIntroDbSubtitle,
                                  leading: SvgPicture.asset(
                                    'assets/icons/introdb-logo.svg',
                                    height: 40 * FontSizeScope.scaleOf(context),
                                  ),
                                  value: widget.introDbSettings!.enabled,
                                  onChanged: (enabled) => unawaited(
                                    widget.introDbSettings!.setEnabled(
                                      enabled: enabled,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.onlineSubtitleSettings != null) ...[
                          const SizedBox(height: 12),
                          OnlineSubtitleSettingsGroup(
                            settings: widget.onlineSubtitleSettings!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SettingsRow(
                title: l.settingsReleaseNotesTab,
                subtitle: l.settingsReleaseNotesSubtitle,
                icon: Icons.new_releases_outlined,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsSubpageFullHeight<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsReleaseNotesTab,
                    onBack: widget.onHandleTopLevelBack,
                    builder: (_) => ReleaseNotesView(
                      isTv: widget.deviceType == DeviceType.tv,
                      onHandleTopLevelBack: widget.onHandleTopLevelBack,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SettingsSectionHeader(l.settingsAccount),
          SettingsGroup(
            children: [
              if (widget.playlists case final playlists?)
                ListenableBuilder(
                  listenable: playlists.service,
                  builder: (context, _) => SettingsRow(
                    title: l.settingsPlaylists,
                    subtitle: _activePlaylistName(playlists.service),
                    icon: Icons.playlist_play,
                    trailing: const SettingsChevron(),
                    onTap: () => unawaited(
                      openPlaylistsPage(
                        context,
                        playlists: playlists,
                        authNotifier: widget.authNotifier,
                        devicePairingService: widget.devicePairingService,
                        deviceType: widget.deviceType,
                        onSwitched: widget.onPlaylistSwitched,
                        onBack: widget.onHandleTopLevelBack,
                      ),
                    ),
                  ),
                ),
              if (widget.activeViewer != null)
                SettingsRow(
                  title: l.settingsActiveViewer,
                  subtitle: widget.activeViewer!.name,
                  icon: Icons.person_outline,
                  trailing: const SettingsChevron(),
                  onTap: () => _openViewerManagement(context),
                ),
              SettingsRow(
                title: l.disconnect,
                icon: Icons.logout,
                destructive: true,
                onTap: _handleDisconnect,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _activePlaylistName(SavedPlaylistsService service) {
    final active = service.find(widget.authNotifier.credentials);
    return active == null
        ? null
        : playlistDisplayName(active, service.playlists);
  }

  Widget _buildGeneralPageBody(BuildContext context) {
    final theme = Theme.of(context);
    final auth = widget.authNotifier.authResponse;
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.settingsSectionLanguageRegion),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsLanguage,
              subtitle: _localeLabel(context, widget.locale),
              icon: Icons.language,
              trailing: const SettingsChevron(),
              onTap: () => _openLanguagePicker(context, l),
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsApp),
        const SettingsCard(child: AppVersionCard()),
        if (widget.loadDiagnosticsHeader != null ||
            widget.viewSettingsService != null) ...[
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
              if (widget.loadDiagnosticsHeader case final loadHeader?)
                SettingsRow(
                  title: l.settingsLogsDiagnostics,
                  subtitle: l.settingsLogsDiagnosticsSubtitle,
                  icon: Icons.bug_report_outlined,
                  trailing: const SettingsChevron(),
                  onTap: () => unawaited(
                    pushSettingsSubpageFullHeight<void>(
                      context,
                      title: (context) =>
                          AppLocalizations.of(context).settingsLogsDiagnostics,
                      onBack: widget.onHandleTopLevelBack,
                      builder: (_) => DiagnosticsScreen(
                        loadHeader: loadHeader,
                        onUpload: widget.onUploadLogs,
                      ),
                    ),
                  ),
                ),
              if (widget.viewSettingsService case final viewSettings?)
                ListenableBuilder(
                  listenable: viewSettings,
                  builder: (context, _) => SettingsSwitchRow(
                    title: l.settingsPlaybackDiagnostics,
                    locked: viewSettings.isEnforced(
                      ViewSettingsService.showPlaybackDiagnosticsKey,
                    ),
                    subtitle: l.settingsPlaybackDiagnosticsHint,
                    icon: Icons.monitor_heart_outlined,
                    value: viewSettings.showPlaybackDiagnosticsSync,
                    onChanged: viewSettings.setShowPlaybackDiagnostics,
                  ),
                ),
            ],
          ),
        ],

        SettingsSectionHeader(l.settingsConnection),
        SettingsCard(
          child: Column(
            children: [
              SettingsStatusRow(
                label: l.settingsStatusLabel,
                value:
                    widget.sourceError != null && widget.sourceError!.isNotEmpty
                    ? l.settingsStatusUnavailable
                    : l.settingsStatusConnected,
                valueColor:
                    widget.sourceError != null && widget.sourceError!.isNotEmpty
                    ? Colors.orange
                    : Colors.green,
              ),
              if (widget.sourceLabel != null) ...[
                const Divider(),
                SettingsStatusRow(
                  label: l.settingsSourceLabel,
                  value: widget.sourceLabel!,
                ),
              ],
              if (widget.serverTimezone != null) ...[
                const Divider(),
                SettingsStatusRow(
                  label: l.settingsServerTimezone,
                  value: widget.serverTimezone!,
                ),
              ],
              if (auth != null) ...[
                const Divider(),
                SettingsStatusRow(
                  label: 'm3u-editor',
                  value: auth.m3uEditorVersion ?? l.unknown,
                ),
              ],
              if (widget.sourceError != null &&
                  widget.sourceError!.isNotEmpty) ...[
                const Divider(),
                SettingsStatusRow(
                  label: l.settingsLastError,
                  value: widget.sourceError!,
                  valueColor: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    autofocus: true,
                    icon: Icons.refresh,
                    label: l.settingsRetryConnection,
                    // Reconnects and reloads the shown playlist only; the
                    // others' stored content and the artwork stay.
                    onPressed: widget.onClearCache == null
                        ? null
                        : () => widget.onClearCache!(CacheClearScope.content),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    icon: Icons.settings,
                    label: l.settingsEditServer,
                    onPressed: _handleDisconnect,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openLanguagePicker(BuildContext context, AppLocalizations l) {
    unawaited(
      pushSettingsPicker<Locale?>(
        context,
        title: (context) => AppLocalizations.of(context).settingsLanguage,
        onBack: widget.onHandleTopLevelBack,
        selected: widget.locale,
        options: [
          SettingsPickerOption(value: null, label: l.settingsLanguageSystem),
          const SettingsPickerOption(value: Locale('en'), label: 'English'),
          const SettingsPickerOption(value: Locale('de'), label: 'Deutsch'),
          const SettingsPickerOption(value: Locale('es'), label: 'Español'),
          const SettingsPickerOption(value: Locale('fr'), label: 'Français'),
          const SettingsPickerOption(value: Locale('zh'), label: '简体中文'),
        ],
        onSelected: (locale) => widget.onLocaleChanged?.call(locale),
      ),
    );
  }

  String _localeLabel(BuildContext context, Locale? locale) {
    switch (locale?.languageCode) {
      case 'en':
        return 'English';
      case 'de':
        return 'Deutsch';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'zh':
        return '简体中文';
      default:
        return AppLocalizations.of(context).settingsLanguageSystem;
    }
  }
}
