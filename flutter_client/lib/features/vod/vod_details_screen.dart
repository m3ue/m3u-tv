import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class VodDetailsScreen extends StatefulWidget {
  const VodDetailsScreen({
    super.key,
    required this.item,
    this.xtreamService,
    this.onPlay,
  });

  final VodItem item;
  final XtreamService? xtreamService;
  final void Function(PlayerArgs)? onPlay;

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
      appBar: AppBar(
        title: Text(widget.item.name),
        automaticallyImplyLeading: false,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: DpadFocusable(
            onSelect: () => Navigator.of(context).maybePop(),
            effects: const [
              DpadBorderEffect(
                borderRadius: BorderRadius.all(Radius.circular(50)),
              ),
            ],
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      body: _future == null
          ? _VodDetailsBody(item: widget.item, onPlay: widget.onPlay)
          : FutureBuilder<VodInfo?>(
              future: _future,
              builder: (context, snapshot) {
                return _VodDetailsBody(
                  item: widget.item,
                  info: snapshot.hasError ? null : snapshot.data,
                  isLoading: snapshot.connectionState != ConnectionState.done,
                  onPlay: widget.onPlay,
                );
              },
            ),
    );
  }
}

class _VodDetailsBody extends StatelessWidget {
  const _VodDetailsBody({
    required this.item,
    this.info,
    this.isLoading = false,
    this.onPlay,
  });

  final VodItem item;
  final VodInfo? info;
  final bool isLoading;
  final void Function(PlayerArgs)? onPlay;

  static const double _wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _ResolvedVodDetails(item, info);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return _buildNarrow(context, theme, details);
        }
        return _buildWide(context, theme, details);
      },
    );
  }

  Widget _buildWide(
    BuildContext context,
    ThemeData theme,
    _ResolvedVodDetails details,
  ) {
    final backdrop = details.backdropUrl;
    final content = Padding(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
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
            child: SingleChildScrollView(child: _infoColumn(theme, details)),
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
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.sizeOf(context).height * 0.1,
            ),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(
    BuildContext context,
    ThemeData theme,
    _ResolvedVodDetails details,
  ) {
    final backdrop = details.backdropUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop != null)
                Image.network(backdrop, fit: BoxFit.cover)
              else
                ResilientMediaImage(
                  imageUrl: details.coverUrl,
                  fallbackIcon: Icons.movie,
                  borderRadius: 0,
                  fallbackTitle: details.name,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, theme.colorScheme.surface],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _infoColumn(theme, details, fullWidthButton: true),
          ),
        ),
      ],
    );
  }

  Widget _infoColumn(
    ThemeData theme,
    _ResolvedVodDetails details, {
    bool fullWidthButton = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(details.name, style: theme.textTheme.headlineMedium),
        const SizedBox(height: MediaBrowsingMetrics.itemGap),
        Wrap(
          spacing: MediaBrowsingMetrics.itemGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          children: [
            if (details.year != null) _MetadataChip(label: details.year!),
            if (details.genre != null) _MetadataChip(label: details.genre!),
            if (details.duration != null)
              _MetadataChip(label: details.duration!),
            if (details.rating != null)
              _MetadataChip(label: '★ ${details.rating}'),
            if (details.containerExtension != null)
              _MetadataChip(label: details.containerExtension!.toUpperCase()),
          ],
        ),
        const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        if (fullWidthButton)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              autofocus: true,
              onPressed: () => _play(details),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play movie'),
            ),
          )
        else
          FilledButton.icon(
            autofocus: true,
            onPressed: () => _play(details),
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
    );
  }

  void _play(_ResolvedVodDetails details) {
    onPlay?.call(
      PlayerArgs(
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
