import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/features/settings/sections/settings_status_row.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';
import 'package:m3u_tv/services/storage_usage.dart';
import 'package:m3u_tv/shared/formatters.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// What Settings > Storage reads and changes.
class StorageManagement {
  const StorageManagement({
    required this.loadUsage,
    required this.onClearPlaylist,
    required this.onClear,
    required this.cachedPlaylistLimit,
    required this.cachedPlaylistLimitOptions,
    required this.onCachedPlaylistLimitChanged,
    required this.epgRefreshInterval,
    required this.epgRefreshOptions,
    required this.onEpgRefreshIntervalChanged,
  });

  final Future<StorageUsage> Function() loadUsage;

  /// Frees a saved playlist's stored catalog: the active one's downloads
  /// again right away, another's when it is next used.
  final Future<void> Function(String playlistId) onClearPlaylist;

  /// Refreshes the guide, empties the artwork cache, or clears everything.
  final Future<void> Function(CacheClearScope scope) onClear;

  final int Function() cachedPlaylistLimit;
  final List<int> cachedPlaylistLimitOptions;
  final Future<void> Function(int limit) onCachedPlaylistLimitChanged;

  final Duration Function() epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final Future<void> Function(Duration interval) onEpgRefreshIntervalChanged;
}

/// Settings > Storage: what the app keeps on the device (each playlist's
/// catalog, the guide, artwork), with a way to clear each.
class StoragePage extends StatefulWidget {
  const StoragePage({
    super.key,
    required this.storage,
    this.onHandleTopLevelBack,
  });

  final StorageManagement storage;
  final bool Function()? onHandleTopLevelBack;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  StorageUsage? _usage;
  int _loads = 0;

  StorageManagement get _storage => widget.storage;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final load = ++_loads;
    try {
      final usage = await _storage.loadUsage();
      if (mounted && load == _loads) setState(() => _usage = usage);
    } on Object catch (error) {
      debugPrint('Storage: could not measure usage: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearPlaylist(PlaylistStorage entry, String name) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsStorageClearPlaylistTitle,
      message: entry.isShown
          ? l.settingsStorageClearActiveBody(name)
          : l.settingsStorageClearPlaylistBody(name),
      confirmLabel: entry.isShown
          ? l.settingsClearCacheConfirm
          : l.settingsStorageClear,
      isDestructive: !entry.isShown,
    );
    if (!confirmed || !mounted) return;
    final clearing = _storage.onClearPlaylist(entry.playlist.id);
    if (entry.isShown) {
      // Downloading it again takes a while; it carries on in the background.
      _showMessage(l.settingsCacheCleared);
      unawaited(clearing.whenComplete(_reload));
      return;
    }
    await clearing;
    if (!mounted) return;
    _showMessage(l.settingsStorageCleared);
    await _reload();
  }

  Future<void> _refreshGuide() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsStorageClearGuideTitle,
      message: l.settingsClearCacheEpgHint,
      confirmLabel: l.settingsClearCacheConfirm,
    );
    if (!confirmed || !mounted) return;
    await _storage.onClear(CacheClearScope.epg);
    if (!mounted) return;
    _showMessage(l.settingsEpgCacheCleared);
    await _reload();
  }

  Future<void> _clearArtwork() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsStorageClearArtworkTitle,
      message: l.settingsClearCacheImagesHint,
      confirmLabel: l.settingsStorageClear,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _storage.onClear(CacheClearScope.images);
    if (!mounted) return;
    _showMessage(l.settingsImageCacheCleared);
    await _reload();
  }

  Future<void> _clearEverything() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsStorageClearAll,
      message: l.settingsStorageClearAllBody,
      confirmLabel: l.settingsClearCacheConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    _showMessage(l.settingsCacheCleared);
    unawaited(_storage.onClear(CacheClearScope.all).whenComplete(_reload));
  }

  void _pickPlaylistLimit() {
    unawaited(
      pushSettingsPicker<int>(
        context,
        title: (context) =>
            AppLocalizations.of(context).settingsStorageKeepPlaylists,
        onBack: widget.onHandleTopLevelBack,
        options: [
          for (final count in _storage.cachedPlaylistLimitOptions)
            SettingsPickerOption(
              value: count,
              label: AppLocalizations.of(
                context,
              ).settingsStorageKeepPlaylistsValue(count),
            ),
        ],
        selected: _storage.cachedPlaylistLimit(),
        onSelected: (count) => unawaited(() async {
          await _storage.onCachedPlaylistLimitChanged(count);
          if (!mounted) return;
          setState(() {});
          await _reload();
        }()),
      ),
    );
  }

  void _pickEpgRefreshInterval() {
    final l = AppLocalizations.of(context);
    unawaited(
      pushSettingsPicker<Duration>(
        context,
        title: (context) =>
            AppLocalizations.of(context).settingsEpgRefreshInterval,
        onBack: widget.onHandleTopLevelBack,
        options: [
          for (final interval in _storage.epgRefreshOptions)
            SettingsPickerOption(
              value: interval,
              label: _intervalLabel(l, interval),
            ),
        ],
        selected: _storage.epgRefreshInterval(),
        onSelected: (interval) => unawaited(() async {
          await _storage.onEpgRefreshIntervalChanged(interval);
          if (mounted) setState(() {});
        }()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final usage = _usage;
    String size(int? bytes) => usage == null
        ? l.settingsStorageCalculating
        : bytes == null
        ? l.settingsStorageUnavailable
        : formatBytes(bytes);
    final entries = usage?.playlists ?? const <PlaylistStorage>[];
    final allPlaylists = [for (final entry in entries) entry.playlist];
    final playlistBytes = usage?.playlists.fold<int>(
      0,
      (sum, entry) => sum + entry.bytesOnDisk,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          child: Column(
            children: [
              SettingsStatusRow(
                label: l.settingsStorageTotal,
                value: size(usage?.totalBytes),
              ),
              const Divider(),
              // Each playlist's guide is counted in its own size.
              SettingsStatusRow(
                label: l.settingsPlaylists,
                value: size(playlistBytes),
              ),
              const Divider(),
              SettingsStatusRow(
                label: l.settingsStorageArtwork,
                value: size(usage?.artworkBytes),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l.settingsCacheSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        SettingsSectionHeader(l.settingsPlaylists),
        SettingsGroup(
          children: [
            for (final entry in entries)
              _playlistRow(
                entry,
                name: playlistDisplayName(entry.playlist, allPlaylists),
                l: l,
                theme: theme,
              ),
            SettingsRow(
              title: l.settingsStorageKeepPlaylists,
              subtitle: l.settingsStorageKeepPlaylistsValue(
                _storage.cachedPlaylistLimit(),
              ),
              icon: Icons.inventory_2_outlined,
              trailing: const SettingsChevron(),
              onTap: _pickPlaylistLimit,
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsStorageGuide),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsStorageGuideData,
              subtitle: usage == null
                  ? l.settingsStorageCalculating
                  : '${formatBytes(usage.guideBytes)} · '
                        '${l.settingsStorageProgrammes(usage.guideProgrammes)}',
              icon: Icons.event_note_outlined,
              trailing: const Icon(Icons.refresh),
              onTap: _refreshGuide,
            ),
            SettingsRow(
              title: l.settingsEpgRefreshInterval,
              subtitle: _intervalLabel(l, _storage.epgRefreshInterval()),
              icon: Icons.schedule,
              trailing: const SettingsChevron(),
              onTap: _pickEpgRefreshInterval,
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsStorageArtwork),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsStorageArtworkCache,
              subtitle: size(usage?.artworkBytes),
              icon: Icons.image_outlined,
              onTap: _clearArtwork,
            ),
          ],
        ),

        const SizedBox(height: 24),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsStorageClearAll,
              icon: Icons.delete_sweep_outlined,
              destructive: true,
              onTap: _clearEverything,
            ),
          ],
        ),
      ],
    );
  }

  Widget _playlistRow(
    PlaylistStorage entry, {
    required String name,
    required AppLocalizations l,
    required ThemeData theme,
  }) {
    final stored = entry.usage != null;
    return SettingsRow(
      title: name,
      subtitle: stored
          ? l.settingsStorageItems(entry.itemCount)
          : l.settingsStorageNotStored,
      icon: Icons.playlist_play,
      titleTrailing: entry.isShown
          ? Icon(
              Icons.check,
              size: 20 * FontSizeScope.scaleOf(context),
              color: theme.colorScheme.primary,
            )
          : null,
      trailing: stored
          ? Text(
              formatBytes(entry.bytesOnDisk),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      // Nothing stored, nothing to clear.
      onTap: stored ? () => _clearPlaylist(entry, name) : null,
    );
  }
}

String _intervalLabel(AppLocalizations l, Duration d) {
  if (d.inHours >= 1) {
    final h = d.inHours;
    return h == 1 ? l.settingsEpgDurationHour : l.settingsEpgDurationHours(h);
  }
  return l.settingsEpgDurationMinutes(d.inMinutes);
}
