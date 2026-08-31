import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Whether [progress] belongs in "Continue Watching": not live, not
/// completed, and far enough in to be a meaningful resume point rather than
/// an accidental few-second tap. Synthetic "up next" entries are always
/// eligible - they have no position of their own.
bool isContinueWatchingEligible(Progress progress) {
  if (progress.contentType == ContentType.live) return false;
  if (progress.upNext) return true;
  return progress.positionSeconds >= 30 && !progress.completed;
}

/// Builds the full eligible "Continue Watching" list as [MediaPreviewItem]s.
/// Shared verbatim between the Home row and the full-list screen so both
/// render identical cards for the same underlying progress entry.
List<MediaPreviewItem> continueWatchingPreviewItems(
  BuildContext context, {
  required List<Progress> progressList,
  required List<VodItem> vodItems,
  required List<Series> seriesList,
  required void Function(Progress) onProgressSelect,
}) => progressList
    .where(isContinueWatchingEligible)
    .map(
      (p) => _resumePreviewItem(
        context,
        p,
        vodItems,
        seriesList,
        onProgressSelect,
      ),
    )
    .whereType<MediaPreviewItem>()
    .toList(growable: false);

MediaPreviewItem? _resumePreviewItem(
  BuildContext context,
  Progress progress,
  List<VodItem> vodItems,
  List<Series> seriesList,
  void Function(Progress) onProgressSelect,
) {
  if (progress.contentType == ContentType.vod) {
    if (progress.title != null) {
      final hasBackdrop = progress.backdropUrl != null;
      final fraction =
          (progress.durationSeconds != null && progress.durationSeconds! > 0)
          ? (progress.positionSeconds / progress.durationSeconds!).clamp(
              0.0,
              1.0,
            )
          : null;
      final plot = progress.plot;
      final subtitle = plot != null
          ? (plot.length > 120 ? '${plot.substring(0, 117)}…' : plot)
          : null;
      final vodFallbackLogo = (!hasBackdrop && progress.thumbnailUrl == null)
          ? vodItems.firstWhereOrNull((v) => v.id == progress.streamId)?.logoUrl
          : null;
      return MediaPreviewItem(
        title: progress.title!,
        subtitle: subtitle,
        imageUrl:
            progress.backdropUrl ?? progress.thumbnailUrl ?? vodFallbackLogo,
        fallbackIcon: Icons.movie,
        imageFit: hasBackdrop ? BoxFit.cover : BoxFit.contain,
        imageBackgroundColor: hasBackdrop ? null : Colors.black,
        fallbackTitle: progress.title,
        progressFraction: fraction,
        overlayLabel: progress.year,
        overlayBadges: <String>[
          if (progress.rating != null) '★ ${progress.rating}',
          if (progress.runtime != null) progress.runtime!,
        ],
        onTap: () => onProgressSelect(progress),
      );
    }
    final item = vodItems.firstWhereOrNull(
      (item) => item.id == progress.streamId,
    );
    if (item == null) return null;
    final fraction =
        (progress.durationSeconds != null && progress.durationSeconds! > 0)
        ? (progress.positionSeconds / progress.durationSeconds!).clamp(
            0.0,
            1.0,
          )
        : null;
    return MediaPreviewItem(
      title: item.name,
      imageUrl: item.logoUrl,
      fallbackIcon: Icons.movie,
      imageFit: BoxFit.contain,
      imageBackgroundColor: Colors.black,
      fallbackTitle: item.name,
      progressFraction: fraction,
      overlayBadges: <String>[
        if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
      ],
      onTap: () => onProgressSelect(progress),
    );
  }

  if (progress.contentType == ContentType.episode) {
    if (progress.seriesId != null &&
        (progress.seriesName != null || progress.title != null)) {
      final displayTitle = progress.seriesName ?? progress.title!;
      final fraction =
          (progress.durationSeconds != null && progress.durationSeconds! > 0)
          ? (progress.positionSeconds / progress.durationSeconds!).clamp(
              0.0,
              1.0,
            )
          : null;
      final episodeSubtitle =
          progress.episodeTitle ??
          (progress.seasonNumber != null
              ? 'Season ${progress.seasonNumber}'
              : null);
      final seriesFallback = seriesList.firstWhereOrNull(
        (s) => s.id == progress.seriesId,
      );
      return MediaPreviewItem(
        title: displayTitle,
        subtitle: episodeSubtitle,
        imageUrl:
            progress.thumbnailUrl ??
            progress.backdropUrl ??
            seriesFallback?.backdropUrl ??
            seriesFallback?.coverUrl,
        fallbackIcon: Icons.tv,
        fallbackTitle: displayTitle,
        progressFraction: progress.upNext ? null : fraction,
        upNextLabel: progress.upNext
            ? AppLocalizations.of(context).homeUpNext
            : null,
        overlayLabel: progress.seasonNumber != null
            ? 'S${progress.seasonNumber}${progress.episodeNumber != null ? ' E${progress.episodeNumber}' : ''}'
            : null,
        overlayBadges: <String>[
          if (progress.rating != null) '★ ${progress.rating}',
          if (progress.runtime != null) progress.runtime!,
        ],
        onTap: () => onProgressSelect(progress),
      );
    }
    if (progress.seriesId != null) {
      final series = seriesList.firstWhereOrNull(
        (series) => series.id == progress.seriesId,
      );
      if (series == null) return null;
      return MediaPreviewItem(
        title: series.name,
        imageUrl: series.backdropUrl ?? series.coverUrl,
        subtitle: progress.seasonNumber != null
            ? AppLocalizations.of(context).homeSeason(progress.seasonNumber!)
            : AppLocalizations.of(context).navSeries,
        fallbackIcon: Icons.tv,
        fallbackTitle: series.name,
        onTap: () => onProgressSelect(progress),
      );
    }
  }

  return null;
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
