import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/formatters.dart';
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
  void Function(Progress)? onProgressFocused,
  HoverIntentCallback Function(Progress)? onProgressHoverChanged,
}) => progressList
    .where(isContinueWatchingEligible)
    .map(
      (p) => _resumePreviewItem(
        context,
        p,
        vodItems,
        seriesList,
        onProgressSelect,
        onProgressFocused,
        onProgressHoverChanged,
      ),
    )
    .whereType<MediaPreviewItem>()
    .toList(growable: false);

/// Same result as [continueWatchingPreviewItems], but resolves only the
/// VOD/series objects [progressList] actually references from the SQLite
/// catalog instead of requiring the caller to hold the full catalog in
/// memory. Progress lists are small (a few dozen entries at most), so this is
/// two bounded id-list queries, not a catalog scan.
Future<List<MediaPreviewItem>> continueWatchingPreviewItemsFromRepo(
  BuildContext context, {
  required List<Progress> progressList,
  required CatalogRepository repo,
  required void Function(Progress) onProgressSelect,
  void Function(Progress)? onProgressFocused,
  HoverIntentCallback Function(Progress)? onProgressHoverChanged,
}) async {
  final eligible = progressList.where(isContinueWatchingEligible).toList();
  final vodIds = <int>{
    for (final p in eligible)
      if (p.contentType == ContentType.vod) p.streamId,
  };
  final seriesIds = <int>{
    for (final p in eligible)
      if (p.contentType == ContentType.episode && p.seriesId != null)
        p.seriesId!,
  };
  final vodItems = vodIds.isEmpty
      ? const <VodItem>[]
      : await repo.activeItemsByIds<VodItem>(
          kind: kCatalogKindVod,
          ids: vodIds,
        );
  final seriesList = seriesIds.isEmpty
      ? const <Series>[]
      : await repo.activeItemsByIds<Series>(
          kind: kCatalogKindSeries,
          ids: seriesIds,
        );
  if (!context.mounted) return const <MediaPreviewItem>[];
  return continueWatchingPreviewItems(
    context,
    progressList: progressList,
    vodItems: vodItems,
    seriesList: seriesList,
    onProgressSelect: onProgressSelect,
    onProgressFocused: onProgressFocused,
    onProgressHoverChanged: onProgressHoverChanged,
  );
}

MediaPreviewItem? _resumePreviewItem(
  BuildContext context,
  Progress progress,
  List<VodItem> vodItems,
  List<Series> seriesList,
  void Function(Progress) onProgressSelect,
  void Function(Progress)? onProgressFocused,
  HoverIntentCallback Function(Progress)? onProgressHoverChanged,
) {
  final onFocused = onProgressFocused == null
      ? null
      : () => onProgressFocused(progress);
  final onHoverChanged = onProgressHoverChanged?.call(progress);
  final vodById = _catalogLookup.vodById(vodItems);
  final seriesById = _catalogLookup.seriesById(seriesList);
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
          ? vodById[progress.streamId]?.logoUrl
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
          ?formatRatingText(progress.rating),
          if (progress.runtime != null) progress.runtime!,
        ],
        onTap: () => onProgressSelect(progress),
        onFocused: onFocused,
        onHoverChanged: onHoverChanged,
      );
    }
    final item = vodById[progress.streamId];
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
        if (item.rating != null) formatRating(item.rating!),
      ],
      onTap: () => onProgressSelect(progress),
      onFocused: onFocused,
      onHoverChanged: onHoverChanged,
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
      final seriesFallback = seriesById[progress.seriesId];
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
          ?formatRatingText(progress.rating),
          if (progress.runtime != null) progress.runtime!,
        ],
        onTap: () => onProgressSelect(progress),
        onFocused: onFocused,
        onHoverChanged: onHoverChanged,
      );
    }
    if (progress.seriesId != null) {
      final series = seriesById[progress.seriesId];
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
        onFocused: onFocused,
        onHoverChanged: onHoverChanged,
      );
    }
  }

  return null;
}

/// Memoized id->item indexes for the VOD/series catalog lists, rebuilt only
/// when the list instance changes (a fresh catalog load), so resolving each
/// progress entry's VOD/series fallback is an O(1) lookup instead of an
/// O(catalog) linear scan repeated per entry - O(progress x catalog) overall
/// on every call otherwise.
class _CatalogLookup {
  List<VodItem>? _vodList;
  Map<int, VodItem> _vodById = const {};
  List<Series>? _seriesList;
  Map<int, Series> _seriesById = const {};

  Map<int, VodItem> vodById(List<VodItem> list) {
    if (!identical(list, _vodList)) {
      final byId = <int, VodItem>{};
      for (final item in list) {
        byId.putIfAbsent(item.id, () => item);
      }
      _vodList = list;
      _vodById = byId;
    }
    return _vodById;
  }

  Map<int, Series> seriesById(List<Series> list) {
    if (!identical(list, _seriesList)) {
      final byId = <int, Series>{};
      for (final series in list) {
        byId.putIfAbsent(series.id, () => series);
      }
      _seriesList = list;
      _seriesById = byId;
    }
    return _seriesById;
  }
}

final _catalogLookup = _CatalogLookup();
