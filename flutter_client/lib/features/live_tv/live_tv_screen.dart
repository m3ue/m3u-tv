import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

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
    this.onCatchupProgramSelect,
    this.onSidebarActivate,
    this.onScheduleProgram,
  });

  final FavoritesService favoritesService;
  final void Function(Channel) onChannelSelect;
  final CatchupProgramSelect? onCatchupProgramSelect;
  final VoidCallback? onSidebarActivate;
  final void Function(Channel, EpgProgram)? onScheduleProgram;

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

  @override
  void initState() {
    super.initState();
    widget.favoritesService.addListener(_onFavoritesChanged);
    unawaited(_initCategory());
  }

  @override
  void dispose() {
    widget.favoritesService.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    unawaited(_loadFavorites());
  }

  Future<void> _initCategory() async {
    final lastCat = await widget.favoritesService.getLastCategory();
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
      if (result != null) {
        _epgMap[channel.id] = result;
      }
    }
  }

  Future<void> _toggleFavorite(Channel channel) async {
    await widget.favoritesService.toggle(channel.id);
    await _loadFavorites();
  }

  Future<void> _openChannelContextMenu(
    BuildContext context,
    Channel channel,
    EpgCurrentNext? epg,
  ) async {
    final hasRecord = epg != null && widget.onScheduleProgram != null;
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
                    icon: Icons.fiber_manual_record,
                    label: AppLocalizations.of(dialogContext).liveTvRecord,
                    subtitle: epg.current.title,
                    autofocus: true,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(_ChannelContextAction.record),
                  ),
                _ContextMenuOption(
                  icon: isFavorite ? Icons.star : Icons.star_border,
                  label: isFavorite
                      ? AppLocalizations.of(dialogContext).liveTvRemoveFavorite
                      : AppLocalizations.of(dialogContext).liveTvFavorite,
                  autofocus: !hasRecord,
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

    switch (action) {
      case _ChannelContextAction.record:
        final current = epg?.current;
        if (current != null) widget.onScheduleProgram?.call(channel, current);
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
                    _ViewMode.epgGrid => _buildEpgGrid(filtered, epgService),
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
          unawaited(widget.favoritesService.setLastViewMode(next.name));
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
          final epg = _epgMap[channel.id];
          final isFav = _favoriteIds.contains(channel.id);
          return _ChannelRow(
            channel: channel,
            epg: epg,
            isFavorite: isFav,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: index == 0,
            onTap: () => widget.onChannelSelect(channel),
            onLongPress: () =>
                unawaited(_openChannelContextMenu(context, channel, epg)),
          );
        },
      ),
    );
  }

  Widget _buildEpgGrid(List<Channel> channels, EpgService epgService) {
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
        onChannelSelect: widget.onChannelSelect,
        onCatchupProgramSelect: widget.onCatchupProgramSelect,
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
          final epg = _epgMap[channel.id];
          final isFav = _favoriteIds.contains(channel.id);
          return _ChannelGridItem(
            channel: channel,
            isFavorite: isFav,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: index == 0,
            onTap: () => widget.onChannelSelect(channel),
            onLongPress: () =>
                unawaited(_openChannelContextMenu(context, channel, epg)),
          );
        },
      ),
    );
  }
}

enum _ChannelContextAction { record, toggleFavorite }

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
                            _RecordingDot(color: colorScheme.error),
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
                _RecordingDot(color: colorScheme.error),
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

/// Small themed dot marking a channel as currently recording. Deliberately
/// compact (no text label) so it holds up on narrow mobile widths; the
/// full description is exposed to screen readers via [Semantics].
class _RecordingDot extends StatelessWidget {
  const _RecordingDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).liveTvRecording,
      child: Container(
        key: const Key('recording-dot'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
