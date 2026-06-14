import 'package:flutter/material.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class VodDetailsScreen extends StatefulWidget {
  const VodDetailsScreen({super.key, required this.item, this.xtreamService});

  final VodItem item;
  final XtreamService? xtreamService;

  @override
  State<VodDetailsScreen> createState() => _VodDetailsScreenState();
}

class _VodDetailsScreenState extends State<VodDetailsScreen> {
  late final Future<VodInfo?>? _future = widget.xtreamService?.getVodInfo(
    widget.item.id,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: SafeArea(
        child: _future == null
            ? _VodDetailsBody(item: widget.item)
            : FutureBuilder<VodInfo?>(
                future: _future,
                builder: (context, snapshot) {
                  return _VodDetailsBody(
                    item: widget.item,
                    info: snapshot.hasError ? null : snapshot.data,
                    isLoading: snapshot.connectionState != ConnectionState.done,
                  );
                },
              ),
      ),
    );
  }
}

class _VodDetailsBody extends StatelessWidget {
  const _VodDetailsBody({
    required this.item,
    this.info,
    this.isLoading = false,
  });

  final VodItem item;
  final VodInfo? info;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _ResolvedVodDetails(item, info);
    final backdrop = details.backdropUrl;

    final content = Padding(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: AspectRatio(
              aspectRatio: 0.68,
              child: ResilientMediaImage(
                imageUrl: details.coverUrl,
                fallbackIcon: Icons.movie,
                borderRadius: MediaBrowsingMetrics.cardRadius,
                fallbackTitle: details.name,
              ),
            ),
          ),
          const SizedBox(width: MediaBrowsingMetrics.pagePadding),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(details.name, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: MediaBrowsingMetrics.itemGap),
                  Wrap(
                    spacing: MediaBrowsingMetrics.itemGap,
                    runSpacing: MediaBrowsingMetrics.chipGap,
                    children: [
                      if (details.year != null)
                        _MetadataChip(label: details.year!),
                      if (details.genre != null)
                        _MetadataChip(label: details.genre!),
                      if (details.duration != null)
                        _MetadataChip(label: details.duration!),
                      if (details.rating != null)
                        _MetadataChip(label: '★ ${details.rating}'),
                      if (details.containerExtension != null)
                        _MetadataChip(
                          label: details.containerExtension!.toUpperCase(),
                        ),
                    ],
                  ),
                  const SizedBox(height: MediaBrowsingMetrics.contentPadding),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () => _play(context, details),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play movie'),
                  ),
                  const SizedBox(height: MediaBrowsingMetrics.pagePadding),
                  if (isLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: MediaBrowsingMetrics.contentPadding),
                  ],
                  Text(
                    details.plot ?? 'No synopsis available.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (details.director != null || details.cast != null) ...[
                    const SizedBox(height: MediaBrowsingMetrics.contentPadding),
                    if (details.director != null)
                      _CreditLine(label: 'Director', value: details.director!),
                    if (details.cast != null)
                      _CreditLine(label: 'Cast', value: details.cast!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (backdrop == null) return content;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(backdrop, fit: BoxFit.cover),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.85),
                theme.colorScheme.surface,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        content,
      ],
    );
  }

  void _play(BuildContext context, _ResolvedVodDetails details) {
    Navigator.of(context).pushNamed(
      RouteNames.player,
      arguments: PlayerArgs(
        streamUrl: item.streamUrl,
        title: details.name,
        type: 'vod',
        streamId: item.id,
        metadata: <String, Object?>{
          if (details.containerExtension != null)
            'container_extension': details.containerExtension,
          if (details.duration != null) 'duration': details.duration,
          if (details.rating != null) 'rating': details.rating,
        },
      ),
    );
  }
}

class _ResolvedVodDetails {
  _ResolvedVodDetails(this.item, this.info);

  final VodItem item;
  final VodInfo? info;

  String get name => _notEmpty(info?.name) ?? item.name;
  String? get plot => _notEmpty(info?.plot);
  String? get genre => _notEmpty(info?.genre);
  String? get director => _notEmpty(info?.director);
  String? get cast => _notEmpty(info?.cast);
  String? get year => _notEmpty(info?.year) ?? _notEmpty(info?.releaseDate);
  String? get duration => _notEmpty(info?.duration);
  double? get rating => info?.rating ?? item.rating;
  String? get coverUrl => _notEmpty(info?.coverUrl) ?? _notEmpty(item.logoUrl);
  String? get backdropUrl => _notEmpty(info?.backdropUrl);
  String? get containerExtension =>
      _notEmpty(info?.containerExtension) ?? item.containerExtension;
}

class _CreditLine extends StatelessWidget {
  const _CreditLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MediaBrowsingMetrics.chipGap),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}

String? _notEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
