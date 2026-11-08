import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/features/settings/sections/connection_section.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

/// What the Playlists settings page needs from the app.
class PlaylistManagement {
  const PlaylistManagement({
    required this.service,
    required this.onSwitch,
    required this.onRename,
    required this.onRemove,
  });

  final SavedPlaylistsService service;

  /// Switches to (or adds) the playlist for the given login. Resolves null
  /// once it is active, else the error to show.
  final Future<String?> Function(UserCredentials credentials) onSwitch;
  final Future<void> Function(String id, String? name) onRename;
  final Future<void> Function(String id) onRemove;
}

/// Pushes the Playlists page: every playlist saved on this device, with
/// switching, adding, renaming and removing. [onSwitched] runs after the page
/// closes on a successful switch or add.
Future<void> openPlaylistsPage(
  BuildContext context, {
  required PlaylistManagement playlists,
  required AuthNotifier authNotifier,
  DevicePairingService? devicePairingService,
  DeviceType? deviceType,
  VoidCallback? onSwitched,
  bool Function()? onBack,
}) => pushSettingsSubpage<void>(
  context,
  title: (context) => AppLocalizations.of(context).settingsPlaylists,
  onBack: onBack,
  builder: (_) => PlaylistsPage(
    playlists: playlists,
    authNotifier: authNotifier,
    devicePairingService: devicePairingService,
    deviceType: deviceType,
    onSwitched: onSwitched,
    onBack: onBack,
  ),
);

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    super.key,
    required this.playlists,
    required this.authNotifier,
    this.devicePairingService,
    this.deviceType,
    this.onSwitched,
    this.onBack,
  });

  final PlaylistManagement playlists;
  final AuthNotifier authNotifier;
  final DevicePairingService? devicePairingService;
  final DeviceType? deviceType;
  final VoidCallback? onSwitched;
  final bool Function()? onBack;

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

enum _PlaylistAction { switchTo, rename, remove }

class _PlaylistsPageState extends State<PlaylistsPage> {
  SavedPlaylistsService get _service => widget.playlists.service;

  Future<void> _openOptions(
    SavedPlaylist playlist, {
    required bool isActive,
  }) async {
    final playlists = _service.playlists;
    final action = await showAppDialog<_PlaylistAction>(
      context: context,
      builder: (_) => _PlaylistOptionsDialog(
        title: playlistDisplayName(playlist, playlists),
        details: _details(
          AppLocalizations.of(context),
          playlist,
          playlists,
          isActive: isActive,
        ),
        isActive: isActive,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PlaylistAction.switchTo:
        await _switchTo(playlist.credentials);
      case _PlaylistAction.rename:
        await _rename(playlist);
      case _PlaylistAction.remove:
        await _remove(playlist, isActive: isActive);
    }
  }

  Future<void> _switchTo(UserCredentials credentials) async {
    final error = await _runSwitch(
      context,
      () => widget.playlists.onSwitch(credentials),
    );
    if (!mounted) return;
    if (error == null) {
      _closeAfterSwitch();
      return;
    }
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.isEmpty
              ? l.settingsConnectionFailed
              : l.settingsSwitchPlaylistFailed(error),
        ),
      ),
    );
  }

  Future<void> _rename(SavedPlaylist playlist) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => _RenamePlaylistDialog(
        currentName: playlist.name,
        defaultName: playlistDefaultName(playlist, _service.playlists),
      ),
    );
    if (name == null || !mounted) return;
    await widget.playlists.onRename(playlist.id, name);
  }

  Future<void> _remove(SavedPlaylist playlist, {required bool isActive}) async {
    final l = AppLocalizations.of(context);
    final String message;
    if (!isActive) {
      message = l.settingsRemovePlaylistBody(
        playlistDisplayName(playlist, _service.playlists),
      );
    } else if (_service.playlists.length > 1) {
      message = l.settingsDisconnectBodyOtherPlaylists;
    } else {
      message = l.settingsDisconnectBody;
    }
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsRemovePlaylistTitle,
      message: message,
      confirmLabel: l.settingsRemovePlaylist,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.playlists.onRemove(playlist.id);
    // Removing the active playlist signs out of it: leave for the connect
    // screen behind this page.
    if (isActive && mounted) Navigator.of(context).pop();
  }

  Future<void> _openAddPlaylist() async {
    final added = await pushSettingsSubpageFullHeight<bool>(
      context,
      title: (context) => AppLocalizations.of(context).settingsAddPlaylist,
      onBack: widget.onBack,
      builder: (_) => _AddPlaylistBody(
        onAdd: widget.playlists.onSwitch,
        onPaired: _service.adoptPaired,
        devicePairingService: widget.devicePairingService,
        deviceType: widget.deviceType,
      ),
    );
    if (added == true && mounted) _closeAfterSwitch();
  }

  void _closeAfterSwitch() {
    Navigator.of(context).pop();
    widget.onSwitched?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_service, widget.authNotifier]),
      builder: (context, _) {
        final saved = _service.playlists;
        final activeId = _service.find(widget.authNotifier.credentials)?.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (saved.isNotEmpty) ...[
              SettingsGroup(
                children: [
                  for (var i = 0; i < saved.length; i++)
                    SettingsRow(
                      title: playlistDisplayName(saved[i], saved),
                      subtitle: _details(
                        l,
                        saved[i],
                        saved,
                        isActive: saved[i].id == activeId,
                      ),
                      icon: Icons.playlist_play,
                      autofocus: i == 0,
                      trailing: saved[i].id == activeId
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : const SettingsChevron(),
                      onTap: () => unawaited(
                        _openOptions(
                          saved[i],
                          isActive: saved[i].id == activeId,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            SettingsGroup(
              children: [
                SettingsRow(
                  title: l.settingsAddPlaylist,
                  icon: Icons.add,
                  autofocus: saved.isEmpty,
                  onTap: () => unawaited(_openAddPlaylist()),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// "Active playlist", and the default name under a custom one.
  String? _details(
    AppLocalizations l,
    SavedPlaylist playlist,
    List<SavedPlaylist> playlists, {
    required bool isActive,
  }) {
    final parts = <String>[
      if (isActive) l.settingsPlaylistActive,
      if (playlist.name != null) playlistDefaultName(playlist, playlists),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Runs [task] behind a "Connecting..." dialog that Back can't dismiss, so a
/// switch can't be abandoned halfway. Resolves to the task's result: null on
/// success, else the error.
Future<String?> _runSwitch(
  BuildContext context,
  Future<String?> Function() task,
) async {
  final outcome = await showAppDialog<({String? error})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SwitchingDialog(task: task),
  );
  return outcome?.error;
}

class _SwitchingDialog extends StatefulWidget {
  const _SwitchingDialog({required this.task});

  final Future<String?> Function() task;

  @override
  State<_SwitchingDialog> createState() => _SwitchingDialogState();
}

class _SwitchingDialogState extends State<_SwitchingDialog> {
  @override
  void initState() {
    super.initState();
    // After this frame: the task notifies app state (and Riverpod) as soon
    // as it starts, which is not allowed while the dialog is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    String? error;
    try {
      error = await widget.task();
    } on Object catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    Navigator.of(context).pop((error: error));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        child: SizedBox(
          width: 480 * scale,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const AppLoadingIndicator(),
                SizedBox(width: 24 * scale),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.settingsConnecting,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.settingsConnectingSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistOptionsDialog extends StatelessWidget {
  const _PlaylistOptionsDialog({
    required this.title,
    required this.details,
    required this.isActive,
  });

  final String title;
  final String? details;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final details = this.details;
    void choose(_PlaylistAction action) => Navigator.of(context).pop(action);
    return Dialog(
      child: SizedBox(
        width: 480 * scale,
        child: DpadRegion(
          memoryKey: 'playlist-options',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (details != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (!isActive) ...[
                  AppButton(
                    autofocus: true,
                    variant: AppButtonVariant.primary,
                    icon: Icons.swap_horiz,
                    label: l.settingsSwitchPlaylist,
                    onPressed: () => choose(_PlaylistAction.switchTo),
                  ),
                  const SizedBox(height: 8),
                ],
                AppButton(
                  autofocus: isActive,
                  icon: Icons.edit_outlined,
                  label: l.settingsRenamePlaylist,
                  onPressed: () => choose(_PlaylistAction.rename),
                ),
                const SizedBox(height: 8),
                AppButton(
                  variant: AppButtonVariant.destructive,
                  icon: Icons.delete_outline,
                  label: l.settingsRemovePlaylist,
                  onPressed: () => choose(_PlaylistAction.remove),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: l.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves to the new label (blank restores the default name), or null when
/// cancelled.
class _RenamePlaylistDialog extends StatefulWidget {
  const _RenamePlaylistDialog({
    required this.currentName,
    required this.defaultName,
  });

  final String? currentName;

  /// Shown as the hint: what a blank name falls back to.
  final String defaultName;

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final _controller = TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return Dialog(
      child: SizedBox(
        width: 480 * scale,
        child: DpadRegion(
          memoryKey: 'rename-playlist',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.settingsRenamePlaylist,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.settingsPlaylistNameLabel,
                    hintText: widget.defaultName,
                    border: const OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12 * scale,
                      vertical: 16 * scale,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: l.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      variant: AppButtonVariant.primary,
                      label: l.settingsSave,
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Pair / Sign In form, adding a playlist. Pops with true once the new
/// playlist is active.
class _AddPlaylistBody extends StatefulWidget {
  const _AddPlaylistBody({
    required this.onAdd,
    this.onPaired,
    this.devicePairingService,
    this.deviceType,
  });

  final Future<String?> Function(UserCredentials credentials) onAdd;
  final Future<void> Function(List<PairedPlaylist> playlists)? onPaired;
  final DevicePairingService? devicePairingService;
  final DeviceType? deviceType;

  @override
  State<_AddPlaylistBody> createState() => _AddPlaylistBodyState();
}

class _AddPlaylistBodyState extends State<_AddPlaylistBody> {
  UserCredentials? _lastCredentials;
  String? _error;

  /// Bumped after a failed attempt to remount the form, resetting a
  /// finished pairing back to the tabs, the way the connect screen does.
  int _formGeneration = 0;

  @override
  void dispose() {
    // Backing out mid-pairing stops the poll for a code nobody will enter.
    final pairing = widget.devicePairingService;
    if (pairing != null && pairing.status != DevicePairingStatus.idle) {
      pairing.cancel();
    }
    super.dispose();
  }

  Future<void> _add(UserCredentials credentials) async {
    _lastCredentials = credentials;
    final error = await _runSwitch(context, () => widget.onAdd(credentials));
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    widget.devicePairingService?.cancel();
    setState(() {
      _error = error.isEmpty
          ? AppLocalizations.of(context).settingsConnectionFailed
          : error;
      _formGeneration += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConnectionFormBody(
      key: ValueKey(_formGeneration),
      onConnect: _add,
      onPaired: widget.onPaired,
      initialValues: _lastCredentials,
      error: _error,
      devicePairingService: widget.devicePairingService,
      deviceType: widget.deviceType,
    );
  }
}
