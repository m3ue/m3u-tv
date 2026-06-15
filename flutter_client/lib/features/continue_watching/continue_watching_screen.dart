import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Continue Watching screen showing resume-able content.
///
/// Mirrors the RN HomeScreen "Continue Watching" row behavior:
/// - Shows VOD and episode items with stored progress > 30 seconds
/// - Displays progress bar showing position/duration
/// - Prompts resume vs start-over when tapping an item
/// - Updates progress every 10 seconds (handled by player, not this screen)
class ContinueWatchingScreen extends StatefulWidget {
  const ContinueWatchingScreen({
    super.key,
    required this.progressList,
    required this.vodItems,
    required this.seriesList,
    required this.isConfigured,
    required this.onResume,
  });

  final List<Progress> progressList;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final bool isConfigured;
  final void Function(Progress) onResume;

  @override
  State<ContinueWatchingScreen> createState() => _ContinueWatchingScreenState();
}

class _ContinueWatchingScreenState extends State<ContinueWatchingScreen> {
  /// Filter progress items: only show non-live content with position > 30 seconds
  List<Progress> get _eligibleItems => widget.progressList
      .where(
        (p) =>
            p.contentType != ContentType.live &&
            p.positionSeconds >= 30 &&
            !p.completed,
      )
      .toList();

  String _getTitle(Progress progress) {
    if (progress.contentType == ContentType.vod) {
      final vod = widget.vodItems
          .where((v) => v.id == progress.streamId)
          .firstOrNull;
      return vod?.name ?? 'Movie ${progress.streamId}';
    } else if (progress.contentType == ContentType.episode) {
      final series = progress.seriesId != null
          ? widget.seriesList
                .where((s) => s.id == progress.seriesId)
                .firstOrNull
          : null;
      return series?.name ?? 'Episode ${progress.streamId}';
    }
    return 'Stream ${progress.streamId}';
  }

  String? _getCoverUrl(Progress progress) {
    if (progress.contentType == ContentType.vod) {
      final vod = widget.vodItems
          .where((v) => v.id == progress.streamId)
          .firstOrNull;
      return vod?.logoUrl;
    } else if (progress.contentType == ContentType.episode) {
      final series = progress.seriesId != null
          ? widget.seriesList
                .where((s) => s.id == progress.seriesId)
                .firstOrNull
          : null;
      return series?.coverUrl;
    }
    return null;
  }

  double _getProgress(Progress progress) {
    if (progress.durationSeconds != null && progress.durationSeconds! > 0) {
      return (progress.positionSeconds / progress.durationSeconds!).clamp(
        0.0,
        1.0,
      );
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final items = _eligibleItems;

    if (items.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'No continue watching items',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return Scaffold(
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final progress = items[index];
          final title = _getTitle(progress);
          final coverUrl = _getCoverUrl(progress);
          final pct = _getProgress(progress);

          return _ContinueWatchingCard(
            title: title,
            coverUrl: coverUrl,
            progress: pct,
            onTap: () => widget.onResume(progress),
          );
        },
      ),
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.title,
    this.coverUrl,
    required this.progress,
    required this.onTap,
  });

  final String title;
  final String? coverUrl;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover image
              Expanded(
                child: coverUrl != null && coverUrl!.isNotEmpty
                    ? Image.network(
                        coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.play_circle_outline, size: 48),
                      )
                    : const Icon(Icons.play_circle_outline, size: 48),
              ),
              // Progress bar
              if (progress > 0)
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
              // Title
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
