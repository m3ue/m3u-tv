import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// One seeded in-memory catalog per channel list within a test, so
/// re-pumping the same list keeps the same catalog. (Const lists are shared
/// across tests, so a catalog an earlier test closed is replaced.)
final _catalogs = Expando<CatalogRepository>();
CatalogRepository catalogWith(List<Channel> channels) {
  final existing = _catalogs[channels];
  if (existing != null && !existing.isClosed) return existing;
  final repo = CatalogRepository(CatalogDatabase.memory());
  addTearDown(repo.close);
  unawaited(
    repo.replaceItems(
      sourceKey: CatalogRepository.activeSource,
      kind: kCatalogKindLive,
      items: channels,
    ),
  );
  return _catalogs[channels] = repo;
}
