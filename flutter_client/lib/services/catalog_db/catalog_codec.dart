import 'package:m3u_tv/services/domain_models.dart';

/// Single source of truth for the on-storage JSON shape of catalog domain
/// objects. The `encode*` helpers produce the payload stored in the
/// `CatalogItems.json` column; the `decode*` helpers rebuild the domain object
/// from it. Categories and EPG programmes are reconstructed straight from their
/// promoted columns, so only [decodeCategory] is needed on that side.

const String kCatalogKindLive = 'live';
const String kCatalogKindVod = 'vod';
const String kCatalogKindSeries = 'series';

Category decodeCategory(Map<String, Object?> json) => Category.fromXtream(json);

Map<String, Object?> encodeChannel(Channel channel) => <String, Object?>{
  'stream_id': channel.id,
  'name': channel.name,
  'stream_url': channel.streamUrl,
  if (channel.logoUrl != null) 'stream_icon': channel.logoUrl,
  if (channel.categoryId != null) 'category_id': channel.categoryId,
  if (channel.groupTitle != null) 'group_title': channel.groupTitle,
  if (channel.epgChannelId != null) 'epg_channel_id': channel.epgChannelId,
  if (channel.tvgName != null) 'tvg_name': channel.tvgName,
  if (channel.catchupSupported) 'catchup_supported': channel.catchupSupported,
  if (channel.catchupDays != null) 'catchup_days': channel.catchupDays,
  if (channel.catchupSource != null) 'catchup_source': channel.catchupSource,
};

Channel decodeChannel(Map<String, Object?> json) => Channel(
  id: asInt(json['stream_id']),
  name: '${json['name'] ?? ''}',
  streamUrl: '${json['stream_url'] ?? ''}',
  logoUrl: nullableString(json['stream_icon']),
  categoryId: nullableString(json['category_id']),
  groupTitle: nullableString(json['group_title']),
  epgChannelId: nullableString(json['epg_channel_id']),
  tvgName: nullableString(json['tvg_name']),
  catchupSupported: asBool(json['catchup_supported']),
  catchupDays: asIntOrNull(json['catchup_days']),
  catchupSource: nullableString(json['catchup_source']),
);

Map<String, Object?> encodeVod(VodItem item) => <String, Object?>{
  'stream_id': item.id,
  'name': item.name,
  'stream_url': item.streamUrl,
  'container_extension': item.containerExtension,
  if (item.logoUrl != null) 'stream_icon': item.logoUrl,
  if (item.categoryId != null) 'category_id': item.categoryId,
  if (item.categoryIds.isNotEmpty) 'category_ids': item.categoryIds,
  if (item.rating != null) 'rating': item.rating,
};

VodItem decodeVod(Map<String, Object?> json) => VodItem(
  id: asInt(json['stream_id']),
  name: '${json['name'] ?? ''}',
  streamUrl: '${json['stream_url'] ?? ''}',
  containerExtension: '${json['container_extension'] ?? 'mp4'}',
  logoUrl: nullableString(json['stream_icon']),
  categoryId: nullableString(json['category_id']),
  categoryIds: stringList(json['category_ids']),
  rating: asDouble(json['rating']),
);

Map<String, Object?> encodeSeries(Series series) => <String, Object?>{
  'series_id': series.id,
  'name': series.name,
  if (series.coverUrl != null) 'cover': series.coverUrl,
  if (series.backdropUrl != null) 'backdrop_path': series.backdropUrl,
  if (series.categoryId != null) 'category_id': series.categoryId,
  // Decoded via Series.fromXtream, which reads `category_ids` natively.
  if (series.categoryIds.isNotEmpty) 'category_ids': series.categoryIds,
  if (series.plot != null) 'plot': series.plot,
  if (series.rating != null) 'rating': series.rating,
  if (series.tmdbId != null) 'tmdb_id': series.tmdbId,
};

Series decodeSeries(Map<String, Object?> json) => Series.fromXtream(json);

// ---------------------------------------------------------------------------
// Loose-value coercion shared by every decoder above (provider payloads mix
// string / int / bool representations freely).
// ---------------------------------------------------------------------------

Map<String, Object?> asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

int asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

bool asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = '$value'.trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

List<String> stringList(Object? value) => value is List
    ? value.map(nullableString).whereType<String>().toList(growable: false)
    : const <String>[];

String? nullableString(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}
