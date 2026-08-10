import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/epg/epg_recording_index.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dvr_action_dialogs.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/recording_dot.dart';

enum _ViewMode { list, logoGrid, epgGrid }

/// Live TV screen with category filtering, EPG info, and favorites.
///
/// Mirrors the RN LiveTVScreen behavior:
/// - All Channels + ★ Favorites pseudo-category + real categories
/// - List view with EPG current/next info and progress bars
/// - Toggle between list and grid view modes
/// - Long-press context menu for favorites and recording actions
/// - Lazy EPG loading for visible channels
class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({
    super.key,
    required this.favoritesService,
    required this.onChannelSelect,
    this.viewSettingsService,
    this.onChannelContextChanged,
    this.onCatchupProgramSelect,
    this.onSidebarActivate,
    this.onScheduleProgram,
    this.onEnsureEpg,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onRecordSeries,
  });

  final FavoritesService favoritesService;
  final ViewSettingsService? viewSettingsService;
  final void Function(Channel) onChannelSelect;

  /// Called with the filtered channel list (category/favorites/search) right
  /// before [onChannelSelect], so the player's skip-previous/skip-next stays
  /// within this view instead of the full unfiltered channel list.
  final void Function(List<Channel>)? onChannelContextChanged;
  final CatchupProgramSelect? onCatchupProgramSelect;
  final VoidCallback? onSidebarActivate;
  final void Function(Channel, EpgProgram)? onScheduleProgram;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;

  /// Wired by AppShell against `XtreamService.createDvrSeriesRule`. Receives
  /// the long-pressed channel and the program whose title should be matched
  /// by the new series rule. Returns the outcome so the caller can
  /// distinguish created / duplicate / failed instead of collapsing every
  /// non-success into a generic failure SnackBar.
  final Future<CreateDvrSeriesRuleOutcome> Function(
    Channel channel,
    EpgProgram program,
  )?
  onRecordSeries;

  /// Requests EPG data for the given channels be fetched (lazily, debounced)
  /// if not already fresh. Called per-item as the visible list/grid builds,
  /// so only channels actually scrolled into view get fetched.
  final EnsureEpg? onEnsureEpg;

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  static const _favoritesCategoryId = '__FAVORITES__';
  String? _selectedCategory;
  String _query = '';
  Set<int> _favoriteIds = {};
  final Map<int, EpgCurrentNext?> _epgMap = {};
  _ViewMode _viewMode = _ViewMode.list;
  EpgStartView _epgStartView = EpgStartView.currentTime;
  int _viewSettingsGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.favoritesService.addListener(_onFavoritesChanged);
    _attachViewSettingsListener();
    unawaited(_initCategory());
  }

  @override
  void didUpdateWidget(covariant LiveTvScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewSettingsService != widget.viewSettingsService) {
      _viewSettingsGeneration++;
      _detachViewSettingsListener(oldWidget.viewSettingsService);
      _attachViewSettingsListener();
      unawaited(_reloadViewSettings());
    }
  }

  @override
  void dispose() {
    widget.favoritesService.removeListener(_onFavoritesChanged);
    _detachViewSettingsListener(widget.viewSettingsService);
    super.dispose();
  }

  void _attachViewSettingsListener() {
    widget.viewSettingsService?.addListener(_onViewSettingsChanged);
  }

  void _detachViewSettingsListener(ViewSettingsService? service) {
    service?.removeListener(_onViewSettingsChanged);
  }

  void _onViewSettingsChanged() {
    _viewSettingsGeneration++;
    unawaited(_reloadViewSettings());
  }

  Future<void> _reloadViewSettings() async {
    final generation = _viewSettingsGeneration;
    final loaded = await _loadViewSettings();
    if (loaded == null || !mounted || generation != _viewSettingsGeneration) {
      return;
    }
    setState(() {
      _viewMode = _layoutToViewMode(loaded.layout);
      _epgStartView = loaded.epgStartView;
    });
  }

  Future<({LiveTvLayout layout, EpgStartView epgStartView})?>
  _loadViewSettings() async {
    final viewSettings = widget.viewSettingsService;
    if (viewSettings == null) return null;
    final results = await Future.wait([
      viewSettings.liveTvLayout(),
      viewSettings.epgStartView(),
    ]);
    return (
      layout: results[0] as LiveTvLayout,
      epgStartView: results[1] as EpgStartView,
    );
  }

  void _onFavoritesChanged() {
    unawaited(_loadFavorites());
  }

  Future<void> _initCategory() async {
    final lastCat = await widget.favoritesService.getLastCategory();
    final viewSettings = widget.viewSettingsService;
    if (viewSettings != null) {
      if (!await viewSettings.hasLiveTvLayout()) {
        final legacyMode = await widget.favoritesService.getLastViewMode();
        if (legacyMode != null) {
          final legacyViewMode = _ViewMode.values.firstWhere(
            (m) => m.name == legacyMode,
            orElse: () => _ViewMode.list,
          );
          await viewSettings.setLiveTvLayout(_viewModeToLayout(legacyViewMode));
        }
      }
      final generation = _viewSettingsGeneration;
      final loaded = await _loadViewSettings();
      if (mounted && generation == _viewSettingsGeneration) {
        setState(() {
          _selectedCategory = lastCat;
          if (loaded != null) {
            _viewMode = _layoutToViewMode(loaded.layout);
            _epgStartView = loaded.epgStartView;
          }
        });
      }
    } else {
      final lastMode = await widget.favoritesService.getLastViewMode();
      if (mounted) {
        setState(() {
          _selectedCategory = lastCat;
          if (lastMode != null) {
            _viewMode = _ViewMode.values.firstWhere(
              (m) => m.name == lastMode,
              orElse: () => _ViewMode.list,
            );
          }
        });
      }
    }
    await _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final ids = await widget.favoritesService.all();
    if (mounted) {
      setState(() {
        _favoriteIds = ids;
      });
    }
  }

  List<Channel> _filteredChannels(List<Channel> channels) {
    final selectedCategory = _selectedCategory;
    final categoryFiltered =
        selectedCategory == null || selectedCategory.isEmpty
        ? channels
        : selectedCategory == _favoritesCategoryId
        ? channels.where((channel) => _favoriteIds.contains(channel.id))
        : channels.where(
            (channel) => channel.categoryId == selectedCategory,
          );
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return categoryFiltered.toList(growable: false);
    }
    return categoryFiltered
        .where(
          (channel) => channel.name.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
  }

  static _ViewMode _layoutToViewMode(LiveTvLayout layout) => switch (layout) {
    LiveTvLayout.list => _ViewMode.list,
    LiveTvLayout.grid => _ViewMode.logoGrid,
    LiveTvLayout.timeline => _ViewMode.epgGrid,
  };

  static LiveTvLayout _viewModeToLayout(_ViewMode mode) => switch (mode) {
    _ViewMode.list => LiveTvLayout.list,
    _ViewMode.logoGrid => LiveTvLayout.grid,
    _ViewMode.epgGrid => LiveTvLayout.timeline,
  };

  List<CategoryTabData> _categoryTabs(List<Category> categories) {
    return [
      CategoryTabData(
        id: '',
        name: AppLocalizations.of(context).liveTvAllChannels,
      ),
      CategoryTabData(
        id: _favoritesCategoryId,
        name: AppLocalizations.of(context).liveTvFavorites,
      ),
      ...categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];
  }

  void _loadEpgForChannels(List<Channel> channels, EpgService epgService) {
    for (final channel in channels) {
      final result = epgService.lookupForChannel(channel);
      _epgMap[channel.id] = result;
    }
  }

  Future<void> _toggleFavorite(Channel channel) async {
    await widget.favoritesService.toggle(channel.id);
    await _loadFavorites();
  }

  Future<void> _openChannelContextMenu(
    BuildContext context,
    Channel channel,
    // The program "Record" would act on if tapped — the channel's current
    // program from the list/grid views, or whichever block was long-pressed
    // in the EPG timeline (which may be a future program, schedulable ahead
    // of time same as the editor supports; a past program is not, so callers
    // pass null for those).
    EpgProgram? pressedProgram,
  ) async {
    DvrRecording? activeRecording;
    for (final recording in ref.read(dvrRecordingsProvider)) {
      if (recording.channelId == channel.id && recording.isInProgress) {
        activeRecording = recording;
        break;
      }
    }
    final recordableProgram =
        pressedProgram != null &&
            pressedProgram.end.isAfter(ref.read(epgServiceProvider).now)
        ? pressedProgram
        : null;
    final hasRecord = activeRecording != null
        ? widget.onCancelRecording != null
        : recordableProgram != null && widget.onScheduleProgram != null;
    final hasSeriesRule =
        recordableProgram != null && widget.onRecordSeries != null;
    final isFavorite = _favoriteIds.contains(channel.id);

    final action = await showDialog<_ChannelContextAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Row(
          children: [
            const Icon(Icons.tv, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: [
          DpadRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasRecord)
                  _ContextMenuOption(
                    icon: activeRecording != null
                        ? Icons.stop_circle
                        : Icons.fiber_manual_record,
                    label: activeRecording != null
                        ? AppLocalizations.of(dialogContext).liveTvStopRecording
                        : AppLocalizations.of(dialogContext).liveTvRecord,
                    subtitle: activeRecording != null
                        ? null
                        : recordableProgram?.title,
                    autofocus: true,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(_ChannelContextAction.record),
                  ),
                if (hasSeriesRule)
                  _ContextMenuOption(
                    icon: Icons.fiber_new,
                    label: AppLocalizations.of(dialogContext).epgRecordSeries,
                    subtitle: recordableProgram.title,
                    autofocus: !hasRecord,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(_ChannelContextAction.recordSeries),
                  ),
                _ContextMenuOption(
                  icon: isFavorite ? Icons.star : Icons.star_border,
                  label: isFavorite
                      ? AppLocalizations.of(dialogContext).liveTvRemoveFavorite
                      : AppLocalizations.of(dialogContext).liveTvFavorite,
                  autofocus: !hasRecord && !hasSeriesRule,
                  onTap: () => Navigator.of(
                    dialogContext,
                  ).pop(_ChannelContextAction.toggleFavorite),
                ),
                _ContextMenuOption(
                  icon: Icons.close,
                  label: AppLocalizations.of(dialogContext).cancel,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    switch (action) {
      case _ChannelContextAction.record:
        if (activeRecording != null) {
          if (widget.onCancelRecording == null) return;
          await confirmStopOrDeleteRecording(
            context,
            recording: activeRecording,
            onCancel: widget.onCancelRecording!,
            onCancelAndDelete: widget.onCancelAndDeleteRecording,
          );
        } else {
          final program = recordableProgram;
          if (program != null) {
            widget.onScheduleProgram?.call(channel, program);
          }
        }
      case _ChannelContextAction.recordSeries:
        final program = recordableProgram;
        if (program == null || widget.onRecordSeries == null) return;
        final messenger = ScaffoldMessenger.of(context);
        final l10n = AppLocalizations.of(context);
        try {
          final outcome = await widget.onRecordSeries!(channel, program);
          if (!context.mounted) return;
          final message = switch (outcome) {
            CreateDvrSeriesRuleOutcome.created => l10n.epgRecordSeriesSuccess(
              program.title,
            ),
            CreateDvrSeriesRuleOutcome.duplicate =>
              l10n.epgRecordSeriesDuplicate,
            CreateDvrSeriesRuleOutcome.failed => l10n.epgRecordSeriesFailed,
          };
          messenger.showSnackBar(SnackBar(content: Text(message)));
        } on Object catch (_) {
          if (!context.mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.epgRecordSeriesFailed)),
          );
        }
      case _ChannelContextAction.toggleFavorite:
        await _toggleFavorite(channel);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final isLoading = ref.watch(isLoadingContentProvider);
    final channels = ref.watch(liveChannelsProvider);
    final categories = ref.watch(liveCategoriesProvider);
    final epgService = ref.watch(epgServiceProvider);
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final filtered = _filteredChannels(channels);
    _loadEpgForChannels(filtered, epgService);

    return Scaffold(
      body: Column(
        children: [
          _buildSearchField(),
          _buildCategoryBar(categories),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context).liveTvNoChannels,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : switch (_viewMode) {
                    _ViewMode.epgGrid => _buildEpgGrid(
                      filtered,
                      epgService,
                      recordingChannelIds,
                      EpgRecordingIndex.fromRecordings(
                        ref.watch(dvrRecordingsProvider),
                      ),
                    ),
                    _ViewMode.logoGrid => _buildGridView(
                      filtered,
                      recordingChannelIds,
                    ),
                    _ViewMode.list => _buildListView(
                      filtered,
                      recordingChannelIds,
                    ),
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MediaBrowsingMetrics.contentPadding,
        MediaBrowsingMetrics.contentPadding,
        MediaBrowsingMetrics.contentPadding,
        0,
      ),
      child: InlineMediaSearchField(
        query: _query,
        hintText: AppLocalizations.of(context).liveTvSearchHint,
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildCategoryBar(List<Category> categories) {
    return ScrollableCategoryBar(
      tabs: _categoryTabs(categories),
      selectedId: _selectedCategory ?? '',
      onSelected: (id) => setState(() => _selectedCategory = id),
      leading: IconButton(
        icon: Icon(switch (_viewMode) {
          _ViewMode.list => Icons.grid_view,
          _ViewMode.logoGrid => Icons.view_list,
          _ViewMode.epgGrid => Icons.list,
        }),
        onPressed: () {
          final next = switch (_viewMode) {
            _ViewMode.list => _ViewMode.logoGrid,
            _ViewMode.logoGrid => _ViewMode.epgGrid,
            _ViewMode.epgGrid => _ViewMode.list,
          };
          setState(() => _viewMode = next);
          final viewSettings = widget.viewSettingsService;
          if (viewSettings != null) {
            unawaited(viewSettings.setLiveTvLayout(_viewModeToLayout(next)));
          } else {
            unawaited(widget.favoritesService.setLastViewMode(next.name));
          }
        },
        tooltip: switch (_viewMode) {
          _ViewMode.list => 'Logo grid',
          _ViewMode.logoGrid => 'EPG grid',
          _ViewMode.epgGrid => 'List view',
        },
      ),
    );
  }

  Widget _buildListView(List<Channel> channels, Set<int> recordingChannelIds) {
    return DpadRegion(
      memoryKey: 'live-tv/list',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ScrollbarListView(
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          widget.onEnsureEpg?.call([channel]);
          final epg = _epgMap[channel.id];
          final isFav = _favoriteIds.contains(channel.id);
          return _ChannelRow(
            channel: channel,
            epg: epg,
            isFavorite: isFav,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: index == 0,
            onTap: () {
              widget.onChannelContextChanged?.call(channels);
              widget.onChannelSelect(channel);
            },
            onLongPress: () => unawaited(
              _openChannelContextMenu(context, channel, epg?.current),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEpgGrid(
    List<Channel> channels,
    EpgService epgService,
    Set<int> recordingChannelIds,
    EpgRecordingIndex recordingIndex,
  ) {
    return DpadRegion(
      memoryKey: 'live-tv/epg',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: TimelineEpgView(
        channels: channels,
        epgService: epgService,
        recordingChannelIds: recordingChannelIds,
        recordingStateFor: (channel, program) => recordingIndex.stateFor(
          channelId: channel.id,
          programStart: program.start,
          programEnd: program.end,
        ),
        epgStartView: _epgStartView,
        onChannelSelect: (channel) {
          widget.onChannelContextChanged?.call(channels);
          widget.onChannelSelect(channel);
        },
        onCatchupProgramSelect: widget.onCatchupProgramSelect,
        onEnsureEpg: widget.onEnsureEpg,
        onChannelLongPress: (channel, program) => unawaited(
          // Pass the exact block that was pressed — schedulable for both
          // the currently-airing and future programs, same as the editor
          // supports; _openChannelContextMenu withholds "Record" itself
          // if this program has already ended.
          _openChannelContextMenu(context, channel, program),
        ),
      ),
    );
  }

  Widget _buildGridView(List<Channel> channels, Set<int> recordingChannelIds) {
    return DpadRegion(
      memoryKey: 'live-tv/grid',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ScrollbarGridView(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisExtent: 120,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          widget.onEnsureEpg?.call([channel]);
          final epg = _epgMap[channel.id];
          final isFav = _favoriteIds.contains(channel.id);
          return _ChannelGridItem(
            channel: channel,
            isFavorite: isFav,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: index == 0,
            onTap: () {
              widget.onChannelContextChanged?.call(channels);
              widget.onChannelSelect(channel);
            },
            onLongPress: () => unawaited(
              _openChannelContextMenu(context, channel, epg?.current),
            ),
          );
        },
      ),
    );
  }
}

enum _ChannelContextAction { record, recordSeries, toggleFavorite }

class _ContextMenuOption extends StatelessWidget {
  const _ContextMenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: subtitle != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    this.epg,
    required this.isFavorite,
    required this.isRecording,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final EpgCurrentNext? epg;
  final bool isFavorite;
  final bool isRecording;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DpadInkWell(
        autofocus: autofocus,
        onTap: onTap,
        onLongTap: onLongPress,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Channel logo
                ResilientMediaImage(
                  imageUrl: channel.logoUrl,
                  fallbackIcon: Icons.tv,
                  width: MediaBrowsingMetrics.logoSize,
                  height: MediaBrowsingMetrics.logoSize,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 14),
                // Channel info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isRecording) ...[
                            RecordingDot(color: colorScheme.error),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              channel.name,
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (epg != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          epg!.current.title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        LinearProgressIndicator(
                          value: epg!.progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            colorScheme.primary,
                          ),
                        ),
                      ] else
                        Text(
                          AppLocalizations.of(context).liveTvNoProgram,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                    ],
                  ),
                ),
                // Favorite star
                if (isFavorite)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.star,
                      color: colorScheme.tertiary,
                      size: 20,
                    ),
                  ),
                // Next program
                if (epg?.next != null)
                  SizedBox(
                    width: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          AppLocalizations.of(context).liveTvNext,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          epg!.next!.title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
              ],
            ), // Row
          ), // inner Padding
        ), // SizedBox
      ), // DpadInkWell
    ); // outer Padding
  }
}

class _ChannelGridItem extends StatelessWidget {
  const _ChannelGridItem({
    required this.channel,
    required this.isFavorite,
    required this.isRecording,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final bool isFavorite;
  final bool isRecording;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      onLongTap: onLongPress,
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ResilientMediaImage(
            imageUrl: channel.logoUrl,
            fallbackIcon: Icons.tv,
            width: MediaBrowsingMetrics.logoSize,
            height: MediaBrowsingMetrics.logoSize,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRecording) ...[
                RecordingDot(color: colorScheme.error),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  channel.name,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (isFavorite)
            Icon(Icons.star, color: colorScheme.tertiary, size: 16),
        ],
      ),
    );
  }
}
