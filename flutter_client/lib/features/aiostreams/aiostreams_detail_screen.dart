import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class AIOStreamsDetailScreen extends StatefulWidget {
  const AIOStreamsDetailScreen({
    super.key,
    required this.item,
    required this.integrationId,
    required this.apiService,
    required this.onPlay,
    this.onSidebarActivate,
  });

  final AIOStreamsItem item;
  final int integrationId;
  final AIOStreamsApiService apiService;
  final void Function(PlayerArgs) onPlay;
  final VoidCallback? onSidebarActivate;

  @override
  State<AIOStreamsDetailScreen> createState() => _AIOStreamsDetailScreenState();
}

class _AIOStreamsDetailScreenState extends State<AIOStreamsDetailScreen> {
  AIOStreamsItem? _enrichedItem;
  bool _loadingMeta = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeta());
  }

  Future<void> _loadMeta() async {
    final meta = await widget.apiService.getMeta(
      widget.integrationId,
      widget.item.type,
      widget.item.id,
    );
    if (mounted) {
      setState(() {
        _enrichedItem = meta ?? widget.item;
        _loadingMeta = false;
      });
    }
  }

  AIOStreamsItem get _displayItem => _enrichedItem ?? widget.item;

  void _getStreams() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _StreamPickerSheet(
          item: _displayItem,
          integrationId: widget.integrationId,
          apiService: widget.apiService,
          onStreamSelected: (stream) {
            Navigator.of(context).pop();
            widget.onPlay(
              PlayerArgs(
                streamUrl: stream.url,
                title: _displayItem.name,
                type: 'vod',
                metadata: <String, Object?>{
                  'aiostreams': true,
                  'source': stream.name,
                  'quality': stream.title,
                },
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _displayItem;
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (item.background != null)
              Positioned.fill(
                child: ResilientMediaImage(
                  imageUrl: item.background,
                  fallbackIcon: Icons.movie,
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.transparent,
                      theme.colorScheme.surface.withAlpha(230),
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 160,
                          height: 240,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ResilientMediaImage(
                              imageUrl: item.poster,
                              fallbackIcon: Icons.movie,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DpadInkWell(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(50),
                            ),
                            onTap: () => Navigator.of(context).maybePop(),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            item.name,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _MetaRow(item: item),
                          if (item.description != null &&
                              item.description!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              item.description!,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (_loadingMeta)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            DpadInkWell(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(8),
                              ),
                              onTap: _getStreams,
                              autofocus: true,
                              child: FilledButton.icon(
                                onPressed: _getStreams,
                                icon: const Icon(Icons.play_arrow),
                                label: Text(l.aiostreamsGetStreams),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.item});

  final AIOStreamsItem item;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (item.year != null) item.year!,
      if (item.imdbRating != null) '★ ${item.imdbRating}',
      ...item.genres.take(3),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: chips
          .map(
            (c) => Chip(
              label: Text(c, style: const TextStyle(fontSize: 12)),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StreamPickerSheet extends StatefulWidget {
  const _StreamPickerSheet({
    required this.item,
    required this.integrationId,
    required this.apiService,
    required this.onStreamSelected,
  });

  final AIOStreamsItem item;
  final int integrationId;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsStream) onStreamSelected;

  @override
  State<_StreamPickerSheet> createState() => _StreamPickerSheetState();
}

class _StreamPickerSheetState extends State<_StreamPickerSheet> {
  late final Future<List<AIOStreamsStream>> _future = widget.apiService
      .getStreams(widget.integrationId, widget.item.type, widget.item.id);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DpadRegion(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                l.aiostreamsSelectStream,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<AIOStreamsStream>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(l.aiostreamsLoadingStreams),
                          ],
                        ),
                      ),
                    );
                  }

                  final streams = snapshot.data ?? const [];

                  if (streams.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(l.aiostreamsNoStreams)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: streams.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final stream = streams[index];
                      return DpadInkWell(
                        borderRadius: BorderRadius.zero,
                        onTap: () => widget.onStreamSelected(stream),
                        autofocus: index == 0,
                        child: ListTile(
                          leading: const Icon(Icons.play_circle_outline),
                          title: Text(
                            stream.name.isEmpty ? stream.title : stream.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: stream.title.isEmpty
                              ? null
                              : Text(
                                  stream.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.onStreamSelected(stream),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
