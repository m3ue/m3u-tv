import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Builds the [PlayerArgs] for playing a series [episode]. Shared by the series
/// detail screen and the in-player "up next" overlay so the metadata handed to
/// the player is assembled identically. Returns null when the episode has no
/// playable stream URL.
PlayerArgs? episodePlayerArgs({
  required Episode episode,
  required int seriesId,
  required String seriesName,
  Series? series,
  double? startPosition,
}) {
  final streamUrl = episode.streamUrl;
  if (streamUrl == null || streamUrl.isEmpty) return null;

  return PlayerArgs(
    streamUrl: streamUrl,
    title: episode.title,
    type: 'series',
    streamId: int.tryParse(episode.id),
    seriesId: seriesId,
    seasonNumber: episode.seasonNumber,
    startPosition: startPosition,
    metadata: <String, Object?>{
      'container_extension': episode.containerExtension,
      'season_number': episode.seasonNumber,
      'episode_number': episode.episodeNumber,
      'episode_title': episode.title,
      'series_name': seriesName,
      if (series?.tmdbId != null) 'tmdb_id': series!.tmdbId,
      if (series?.backdropUrl != null) 'backdrop_url': series!.backdropUrl,
      if (episode.thumbnailUrl != null) 'thumbnail_url': episode.thumbnailUrl,
      if (episode.rating != null) 'rating': '${episode.rating}',
      if (episode.duration != null) 'duration': episode.duration,
      if (episode.plot != null && episode.plot!.isNotEmpty)
        'plot': episode.plot
      else if (series?.plot != null)
        'plot': series!.plot,
      if (episode.edlUrl != null) 'edl_url': episode.edlUrl,
    },
  );
}

/// The next episode after ([seasonNumber], [episodeNumber]) within [info]:
/// the next episode in the same season, or - failing that - the first episode
/// of the next season with a higher number. Returns null past the end.
Episode? nextEpisodeInSeries(
  SeriesInfo info, {
  required int? seasonNumber,
  required int? episodeNumber,
}) {
  if (seasonNumber == null || episodeNumber == null) return null;

  final thisSeason = info.episodesBySeason[seasonNumber] ?? const <Episode>[];
  final laterInSeason =
      thisSeason.where((e) => e.episodeNumber > episodeNumber).toList()
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
  if (laterInSeason.isNotEmpty) return laterInSeason.first;

  final nextSeasons =
      info.episodesBySeason.keys.where((s) => s > seasonNumber).toList()
        ..sort();
  for (final season in nextSeasons) {
    final episodes =
        (info.episodesBySeason[season] ?? const <Episode>[]).toList()
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    if (episodes.isNotEmpty) return episodes.first;
  }
  return null;
}
