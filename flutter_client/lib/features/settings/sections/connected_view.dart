import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/features/settings/clear_cache_dialog.dart';
import 'package:m3u_tv/features/settings/diagnostics_screen.dart';
import 'package:m3u_tv/features/settings/release_notes_view.dart';
import 'package:m3u_tv/features/settings/sections/app_version_card.dart';
import 'package:m3u_tv/features/settings/sections/playback_settings_page.dart';
import 'package:m3u_tv/features/settings/sections/settings_status_row.dart';
import 'package:m3u_tv/features/settings/sections/trakt_card.dart';
import 'package:m3u_tv/features/settings/sections/view_settings_section.dart';
import 'package:m3u_tv/features/settings/sections/viewer_management_dialog.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

// ---------------------------------------------------------------------------
// Connected settings view
// ---------------------------------------------------------------------------

class ConnectedView extends StatefulWidget {
  const ConnectedView({
    super.key,
    required this.authNotifier,
    required this.traktService,
    this.activeViewer,
    this.viewers = const [],
    this.sourceLabel,
    this.serverTimezone,
    this.sourceError,
    this.epgRefreshInterval,
    this.epgRefreshOptions = const [],
    required this.onDisconnect,
    this.onSwitchViewer,
    this.onCreateViewer,
    this.onClearCache,
    this.onEpgIntervalChanged,
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
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
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
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final VoidCallback onDisconnect;
  final void Function(Viewer viewer)? onSwitchViewer;
  final Future<Viewer?> Function(String name)? onCreateViewer;
  final ValueChanged<CacheClearScope>? onClearCache;
  final void Function(Duration interval)? onEpgIntervalChanged;
  final Future<String> Function()? loadDiagnosticsHeader;
  final Future<int> Function(String report)? onUploadLogs;
  final Locale? locale;
  final void Function(Locale?)? onLocaleChanged;

  @override
  State<ConnectedView> createState() => _ConnectedViewState();
}

class _ConnectedViewState extends State<ConnectedView> {
  void _openViewerManagement(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => ViewerManagementDialog(
          viewers: widget.viewers.isNotEmpty
              ? widget.viewers
              : [widget.activeViewer!],
          activeViewer: widget.activeViewer!,
          onSwitch: widget.onSwitchViewer ?? (_) {},
          onCreateViewer: widget.onCreateViewer,
        ),
      ),
    );
  }

  Future<void> _handleClearCache() async {
    final scope = await showClearCacheDialog(context);
    if (scope == null || !mounted) return;
    widget.onClearCache?.call(scope);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final message = switch (scope) {
      CacheClearScope.all || CacheClearScope.content => l.settingsCacheCleared,
      CacheClearScope.epg => l.settingsEpgCacheCleared,
      CacheClearScope.images => l.settingsImageCacheCleared,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleDisconnect() async {
    final l = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      context,
      title: l.settingsDisconnectTitle,
      message: l.settingsDisconnectBody,
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

    return SingleChildScrollView(
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
                      epgRefreshInterval: widget.epgRefreshInterval,
                      epgRefreshOptions: widget.epgRefreshOptions,
                      onEpgIntervalChanged: widget.onEpgIntervalChanged,
                      onClearCache: _handleClearCache,
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
                          listenable: widget.traktService,
                          builder: (context, _) => SettingsCard(
                            child: TraktCard(
                              traktService: widget.traktService,
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
        if (widget.loadDiagnosticsHeader case final loadHeader?) ...[
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
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
                    onPressed: widget.onClearCache == null
                        ? null
                        : () => widget.onClearCache!(CacheClearScope.all),
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

// ---------------------------------------------------------------------------
// Confirm dialog helper
// ---------------------------------------------------------------------------

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final theme = Theme.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 480 * FontSizeScope.scaleOf(ctx),
        child: DpadRegion(
          memoryKey: 'confirm-dialog',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(message, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: AppLocalizations.of(ctx).cancel,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      autofocus: true,
                      variant: isDestructive
                          ? AppButtonVariant.destructive
                          : AppButtonVariant.primary,
                      label: confirmLabel,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}
