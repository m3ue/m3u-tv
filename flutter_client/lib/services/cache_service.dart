// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

class CacheEntry<T> {
  const CacheEntry({required this.data, required this.isStale});

  final T data;
  final bool isStale;
}

class CacheService {
  CacheService({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
    this.refreshInterval = const Duration(hours: 1),
  }) : _memory = memory ?? <String, Object?>{},
       _store = store;

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;
  Duration refreshInterval;

  Future<void> set<T>(String key, T data) async {
    final stamped = _StampedValue<T>(data, DateTime.now());
    _memory['m3ue_cache_$key'] = stamped;
    final encoded = _encodeCacheData(key, data);
    if (encoded != null) {
      await _store?.write('m3ue_cache_$key', <String, Object?>{
        'timestamp': stamped.timestamp.toIso8601String(),
        'data': encoded,
      });
    }
  }

  Future<CacheEntry<T>?> get<T>(String key) async {
    var value = _memory['m3ue_cache_$key'];
    if (value is! _StampedValue && _store != null) {
      value = _decodeStampedValue<T>(key, await _store.read('m3ue_cache_$key'));
      if (value != null) _memory['m3ue_cache_$key'] = value;
    }
    if (value is! _StampedValue) return null;
    return CacheEntry<T>(
      data: value.data as T,
      isStale: DateTime.now().difference(value.timestamp) > refreshInterval,
    );
  }

  Future<void> clear() async {
    _memory.removeWhere((key, _) => key.startsWith('m3ue_cache_'));
    await _store?.removeWhere((key) => key.startsWith('m3ue_cache_'));
  }
}

class _StampedValue<T> {
  const _StampedValue(this.data, this.timestamp);

  final T data;
  final DateTime timestamp;
}

Object? _encodeCacheData(String key, Object? data) {
  if (data is List<Category>) {
    return data.map(_categoryToJson).toList(growable: false);
  }
  if (data is List<Channel>) {
    return data.map(_channelToJson).toList(growable: false);
  }
  if (data is List<VodItem>) {
    return data.map(_vodToJson).toList(growable: false);
  }
  if (data is List<Series>) {
    return data.map(_seriesToJson).toList(growable: false);
  }
  if (data is List<Viewer>) {
    return data.map((viewer) => viewer.toJson()).toList(growable: false);
  }
  if (data is String || data is num || data is bool || data == null) {
    return data;
  }
  return null;
}

_StampedValue<T>? _decodeStampedValue<T>(String key, Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, Object?>();
  final timestampText = json['timestamp'];
  final timestamp = timestampText is String
      ? DateTime.tryParse(timestampText)
      : null;
  if (timestamp == null) return null;
  final data = _decodeCacheData(key, json['data']);
  if (data == null) return null;
  return _StampedValue<T>(data as T, timestamp);
}

Object? _decodeCacheData(String key, Object? raw) {
  final list = raw is List ? raw.cast<Object?>() : null;
  return switch (key) {
    'liveCategories' || 'vodCategories' || 'seriesCategories' =>
      list
          ?.map((item) => Category.fromXtream(_asMap(item)))
          .toList(growable: false),
    'liveStreams' =>
      list
          ?.map((item) {
            final json = _asMap(item);
            return Channel(
              id: _asInt(json['stream_id']),
              name: '${json['name'] ?? ''}',
              streamUrl: '${json['stream_url'] ?? ''}',
              logoUrl: _nullableString(json['stream_icon']),
              categoryId: _nullableString(json['category_id']),
              groupTitle: _nullableString(json['group_title']),
              epgChannelId: _nullableString(json['epg_channel_id']),
              tvgName: _nullableString(json['tvg_name']),
            );
          })
          .toList(growable: false),
    'vodStreams' =>
      list
          ?.map((item) {
            final json = _asMap(item);
            return VodItem(
              id: _asInt(json['stream_id']),
              name: '${json['name'] ?? ''}',
              streamUrl: '${json['stream_url'] ?? ''}',
              containerExtension: '${json['container_extension'] ?? 'mp4'}',
              logoUrl: _nullableString(json['stream_icon']),
              categoryId: _nullableString(json['category_id']),
              rating: _asDouble(json['rating']),
            );
          })
          .toList(growable: false),
    'seriesStreams' =>
      list
          ?.map((item) => Series.fromXtream(_asMap(item)))
          .toList(growable: false),
    'viewers' =>
      list
          ?.map((item) => Viewer.fromJson(_asMap(item)))
          .toList(
            growable: false,
          ),
    _ => raw,
  };
}

Map<String, Object?> _categoryToJson(Category category) => <String, Object?>{
  'category_id': category.id,
  'category_name': category.name,
  'parent_id': category.parentId,
};

Map<String, Object?> _channelToJson(Channel channel) => <String, Object?>{
  'stream_id': channel.id,
  'name': channel.name,
  'stream_url': channel.streamUrl,
  if (channel.logoUrl != null) 'stream_icon': channel.logoUrl,
  if (channel.categoryId != null) 'category_id': channel.categoryId,
  if (channel.groupTitle != null) 'group_title': channel.groupTitle,
  if (channel.epgChannelId != null) 'epg_channel_id': channel.epgChannelId,
  if (channel.tvgName != null) 'tvg_name': channel.tvgName,
};

Map<String, Object?> _vodToJson(VodItem item) => <String, Object?>{
  'stream_id': item.id,
  'name': item.name,
  'stream_url': item.streamUrl,
  'container_extension': item.containerExtension,
  if (item.logoUrl != null) 'stream_icon': item.logoUrl,
  if (item.categoryId != null) 'category_id': item.categoryId,
  if (item.rating != null) 'rating': item.rating,
};

Map<String, Object?> _seriesToJson(Series series) => <String, Object?>{
  'series_id': series.id,
  'name': series.name,
  if (series.coverUrl != null) 'cover': series.coverUrl,
  if (series.categoryId != null) 'category_id': series.categoryId,
  if (series.plot != null) 'plot': series.plot,
  if (series.rating != null) 'rating_5based': series.rating,
};

Map<String, Object?> _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

int _asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}
