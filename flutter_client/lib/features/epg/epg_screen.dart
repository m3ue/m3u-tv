import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

/// EPG screen showing current/next program info for live channels.
///
/// Can be used standalone (does its own EPG lookups) or embedded inside
/// another screen by passing [epgMap] directly from the parent, avoiding a
/// redundant second lookup. When [showHeader] is false the internal
/// list/grid toggle is hidden — use this when the parent already provides a
/// view-mode toggle.
class EpgScreen extends StatefulWidget {
  const EpgScreen({
    super.key,
    required this.channels,
    required this.epgService,
    required this.onChannelSelect,
    this.epgMap,
    this.showHeader = true,
  });

  final List<Channel> channels;
  final EpgService epgService;
  final void Function(Channel) onChannelSelect;

  /// Pre-populated EPG map from a parent widget. When provided, the screen
  /// uses this data directly instead of performing its own service lookups.
  /// The parent is responsible for keeping it fresh (e.g. on every build).
  final Map<int, EpgCurrentNext?>? epgMap;

  /// Whether to show the internal list/grid toggle header.
  /// Set to false when the parent already supplies a view-mode control.
  final bool showHeader;

  @override
  State<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends State<EpgScreen> {
  bool _isGridView = false;

  /// Always compute fresh from either the parent-supplied map or the service.
  /// Avoids stale state when the parent mutates the map or the service loads
  /// data after the first build.
  Map<int, EpgCurrentNext?> _resolveEpgMap() {
    if (widget.epgMap != null) return widget.epgMap!;
    final map = <int, EpgCurrentNext?>{};
    for (final channel in widget.channels) {
      final result = widget.epgService.lookupForChannel(channel);
      if (result != null) map[channel.id] = result;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final epgMap = _resolveEpgMap();
    return Column(
      children: [
        if (widget.showHeader)
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  tooltip: _isGridView ? 'List view' : 'Grid view',
                ),
                Text('EPG', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        Expanded(
          child: widget.channels.isEmpty
              ? Center(
                  child: Text(
                    'No channels available',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : _isGridView
              ? _buildGridView(epgMap)
              : _buildListView(epgMap),
        ),
      ],
    );
  }

  Widget _buildListView(Map<int, EpgCurrentNext?> epgMap) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: widget.channels.length,
      itemBuilder: (context, index) {
        final channel = widget.channels[index];
        final epg = epgMap[channel.id];
        return InkWell(
          onTap: () => widget.onChannelSelect(channel),
          child: Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      channel.logoUrl!,
                      width: 48,
                      height: 48,
                      errorBuilder: (_, _, _) => const Icon(Icons.tv, size: 48),
                    ),
                  )
                else
                  const Icon(Icons.tv, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (epg != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          epg.current.title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: epg.progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            colorScheme.primary,
                          ),
                        ),
                      ] else
                        Text(
                          'No program info',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                    ],
                  ),
                ),
                if (epg?.next != null)
                  SizedBox(
                    width: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'NEXT',
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridView(Map<int, EpgCurrentNext?> epgMap) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: widget.channels.length,
      itemBuilder: (context, index) {
        final channel = widget.channels[index];
        final epg = epgMap[channel.id];
        return InkWell(
          onTap: () => widget.onChannelSelect(channel),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  channel.name,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (epg != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    epg.current.title,
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: epg.progress,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ] else
                  Text(
                    'No program info',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
