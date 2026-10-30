// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;

import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// A filtered, sorted slice of the active live channels in the SQLite
/// catalog: what a Live TV view shows, and what the player's channel up/down
/// then moves through.
class LiveChannelQuery {
  const LiveChannelQuery({
    this.categoryId,
    this.search,
    this.ids,
    this.sort = CatalogSort.providerOrder,
    this.favoritesFirst = const {},
  });

  final String? categoryId;
  final String? search;

  /// Only these channel ids (the Favorites tab), or every channel when null.
  final Set<int>? ids;
  final CatalogSort sort;
  final Set<int> favoritesFirst;

  Future<List<Channel>> page(
    CatalogRepository repo,
    int offset,
    int limit,
  ) => repo.pageActiveItems<Channel>(
    kind: kCatalogKindLive,
    categoryId: categoryId,
    search: search,
    ids: ids,
    sort: sort,
    favoritesFirst: favoritesFirst,
    offset: offset,
    limit: limit,
  );

  Future<int> count(CatalogRepository repo) => repo.countActiveItems(
    kind: kCatalogKindLive,
    categoryId: categoryId,
    search: search,
    ids: ids,
  );

  Future<int> maxCatchupDays(CatalogRepository repo) =>
      repo.maxActiveCatchupDays(
        categoryId: categoryId,
        search: search,
        ids: ids,
      );
}

/// The channels the player's channel up/down moves through: the slice the
/// user picked a channel from (a category, Favorites, search results), so
/// skipping stays inside it rather than walking the whole lineup.
abstract interface class ChannelContext {
  /// How many channels the context holds, as last known.
  int get length;

  /// The channel [step] places away from [channelId], wrapping around the
  /// ends. Null when [channelId] isn't in the context or it is empty.
  Future<Channel?> neighbour(int channelId, int step);

  /// [channelId] as this context knows it, or null.
  Future<Channel?> byId(int channelId);
}

/// A context over channels already in memory.
class ListChannelContext implements ChannelContext {
  const ListChannelContext(this.channels);

  static const ListChannelContext empty = ListChannelContext(<Channel>[]);

  final List<Channel> channels;

  @override
  int get length => channels.length;

  @override
  Future<Channel?> neighbour(int channelId, int step) async {
    final index = channels.indexWhere((c) => c.id == channelId);
    if (index == -1) return null;
    return channels[_wrap(index + step, channels.length)];
  }

  @override
  Future<Channel?> byId(int channelId) async {
    for (final channel in channels) {
      if (channel.id == channelId) return channel;
    }
    return null;
  }
}

/// A context over a [LiveChannelQuery], read from the catalog a row at a
/// time. `indexHint` (the tapped row's index) lets the first skip find the
/// current channel without scanning; each skip then keeps it up to date.
class CatalogChannelContext implements ChannelContext {
  CatalogChannelContext({
    required CatalogRepository repository,
    this.query = const LiveChannelQuery(),
    required int length,
    int? indexHint,
  }) : _repo = repository,
       _length = length,
       _indexHint = indexHint;

  final CatalogRepository _repo;
  final LiveChannelQuery query;
  int _length;
  int? _indexHint;

  /// Rows read per page while scanning for a channel the hint missed.
  static const int _scanPageSize = 500;

  @override
  int get length => _length;

  @override
  Future<Channel?> neighbour(int channelId, int step) async {
    final index = await _indexOf(channelId);
    if (index == null) return null;
    _length = await query.count(_repo);
    if (_length == 0) return null;
    final target = _wrap(index + step, _length);
    final rows = await query.page(_repo, target, 1);
    if (rows.isEmpty) return null;
    _indexHint = target;
    return rows.first;
  }

  @override
  Future<Channel?> byId(int channelId) =>
      _repo.activeItemById<Channel>(kind: kCatalogKindLive, id: channelId);

  /// [channelId]'s row index under [query]: checked around the hint first,
  /// then by scanning (the catalog can have changed under the hint).
  Future<int?> _indexOf(int channelId) async {
    final hint = _indexHint;
    if (hint != null) {
      final start = math.max(0, hint - 1);
      final rows = await query.page(_repo, start, 3);
      final found = rows.indexWhere((c) => c.id == channelId);
      if (found != -1) return start + found;
    }
    for (var offset = 0; ; offset += _scanPageSize) {
      final rows = await query.page(_repo, offset, _scanPageSize);
      final found = rows.indexWhere((c) => c.id == channelId);
      if (found != -1) return offset + found;
      if (rows.length < _scanPageSize) return null;
    }
  }
}

int _wrap(int index, int length) => (index % length + length) % length;
