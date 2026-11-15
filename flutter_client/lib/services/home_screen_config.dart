import 'package:flutter/foundation.dart';
import 'package:m3u_tv/navigation/route_names.dart';

/// What a Home row draws. The server only sends kinds listed in
/// [HomeScreenConfig.supportedRowKinds]; anything else is dropped here.
enum HomeRowKind {
  /// The section's own row (Live TV, Movies, ...), as the app always drew it.
  builtIn('default'),

  /// One category (or Dynamic Group) of the section's content.
  category('category'),

  /// Games from chosen leagues, in the Sports section.
  sportsFixtures('sports_fixtures');

  const HomeRowKind(this.value);
  final String value;

  static HomeRowKind? tryParse(Object? value) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return null;
  }
}

/// A yearly MM-DD window a row shows in. It can wrap the new year.
@immutable
class HomeRowWindow {
  const HomeRowWindow({required this.from, required this.to});

  static HomeRowWindow? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final from = _monthDay(json['from']);
    final to = _monthDay(json['to']);
    if (from == null || to == null) return null;
    return HomeRowWindow(from: from, to: to);
  }

  /// `month * 100 + day`, e.g. 1201 for December 1.
  final int from;
  final int to;

  bool includes(DateTime date) {
    final today = date.month * 100 + date.day;
    return from <= to
        ? today >= from && today <= to
        : today >= from || today <= to;
  }

  Map<String, Object?> toJson() => {'from': _format(from), 'to': _format(to)};

  static int? _monthDay(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r'^(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return month * 100 + day;
  }

  static String _format(int monthDay) =>
      '${(monthDay ~/ 100).toString().padLeft(2, '0')}-'
      '${(monthDay % 100).toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is HomeRowWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// One row inside a Home section.
@immutable
class HomeRowSpec {
  const HomeRowSpec({
    required this.id,
    required this.kind,
    this.title,
    this.categoryId,
    this.leagueIds = const [],
    this.sportsDays = 1,
    this.limit,
    this.window,
  });

  static const builtIn = HomeRowSpec(id: 'default', kind: HomeRowKind.builtIn);

  static HomeRowSpec? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final kind = HomeRowKind.tryParse(json['kind']);
    if (kind == null) return null;
    if (kind == HomeRowKind.builtIn) return builtIn;
    final id = json['id'];
    final title = json['title'];
    final params = json['params'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      return null;
    }
    final paramsMap = params is Map ? params : const <Object?, Object?>{};
    final window = HomeRowWindow.tryFromJson(json['window']);
    switch (kind) {
      case HomeRowKind.category:
        final categoryId = paramsMap['category_id'];
        if (categoryId == null || '$categoryId'.isEmpty) return null;
        return HomeRowSpec(
          id: id,
          kind: kind,
          title: title,
          categoryId: '$categoryId',
          window: window,
        );
      case HomeRowKind.sportsFixtures:
        final leagues = paramsMap['leagues'];
        final leagueIds = [
          if (leagues is List)
            for (final league in leagues)
              if (league is String && league.isNotEmpty) league,
        ];
        if (leagueIds.isEmpty) return null;
        final limit = paramsMap['limit'];
        return HomeRowSpec(
          id: id,
          kind: kind,
          title: title,
          leagueIds: List.unmodifiable(leagueIds),
          sportsDays: paramsMap['range'] == 'next_3_days' ? 3 : 1,
          limit: limit is int && limit > 0 ? limit : null,
          window: window,
        );
      case HomeRowKind.builtIn:
        return builtIn;
    }
  }

  final String id;
  final HomeRowKind kind;
  final String? title;
  final String? categoryId;
  final List<String> leagueIds;

  /// How many days of games, starting today.
  final int sportsDays;
  final int? limit;
  final HomeRowWindow? window;

  bool get isBuiltIn => kind == HomeRowKind.builtIn;

  bool isShownOn(DateTime date) => window?.includes(date) ?? true;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.value,
    if (title != null) 'title': title,
    if (!isBuiltIn)
      'params': switch (kind) {
        HomeRowKind.category => {'category_id': categoryId},
        HomeRowKind.sportsFixtures => {
          'leagues': leagueIds,
          'range': sportsDays == 3 ? 'next_3_days' : 'today',
          if (limit != null) 'limit': limit,
        },
        HomeRowKind.builtIn => const <String, Object?>{},
      },
    if (window != null) 'window': window!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is HomeRowSpec &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.categoryId == categoryId &&
      listEquals(other.leagueIds, leagueIds) &&
      other.sportsDays == sportsDays &&
      other.limit == limit &&
      other.window == window;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    title,
    categoryId,
    Object.hashAll(leagueIds),
    sportsDays,
    limit,
    window,
  );
}

/// One of the app's customizable sections, as the server lays it out.
@immutable
class HomeSection {
  const HomeSection({
    required this.route,
    required this.showInNav,
    required this.showOnHome,
    required this.rows,
  });

  final String route;
  final bool showInNav;
  final bool showOnHome;

  /// Always holds the built-in row once.
  final List<HomeRowSpec> rows;

  @override
  bool operator ==(Object other) =>
      other is HomeSection &&
      other.route == route &&
      other.showInNav == showInNav &&
      other.showOnHome == showOnHome &&
      listEquals(other.rows, rows);

  @override
  int get hashCode =>
      Object.hash(route, showInNav, showOnHome, Object.hashAll(rows));
}

/// A playlist's Home screen from M3U Editor (`client_config.home_screen`).
@immutable
class HomeScreenConfig {
  const HomeScreenConfig({required this.enforced, required this.sections});

  /// The row kinds this version can draw, sent as `row_kinds`.
  static const supportedRowKinds = <String>[
    'default',
    'category',
    'sports_fixtures',
  ];

  /// The editor's section keys. Never renamed on the server.
  static const sectionRoutes = <String, String>{
    'live_tv': RouteNames.liveTv,
    'sports': RouteNames.sports,
    'movies': RouteNames.vod,
    'series': RouteNames.series,
    'aiostreams': RouteNames.aiostreams,
    'dvr': RouteNames.dvr,
    'requests': RouteNames.requests,
  };

  static HomeScreenConfig? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final rawSections = json['sections'];
    if (rawSections is! List) return null;
    final seen = <String>{};
    final sections = <HomeSection>[];
    for (final raw in rawSections) {
      if (raw is! Map) continue;
      final route = sectionRoutes[raw['section']];
      if (route == null || !seen.add(route)) continue;
      final rows = <HomeRowSpec>[];
      final rowIds = <String>{};
      final rawRows = raw['rows'];
      if (rawRows is List) {
        for (final rawRow in rawRows) {
          final row = HomeRowSpec.tryFromJson(rawRow);
          if (row != null && rowIds.add(row.id)) rows.add(row);
        }
      }
      if (!rows.any((row) => row.isBuiltIn)) {
        rows.insert(0, HomeRowSpec.builtIn);
      }
      sections.add(
        HomeSection(
          route: route,
          showInNav: raw['nav'] != false,
          showOnHome: raw['home'] != false,
          rows: List.unmodifiable(rows),
        ),
      );
    }
    return HomeScreenConfig(
      enforced: json['mode'] == 'enforced',
      sections: List.unmodifiable(sections),
    );
  }

  final bool enforced;
  final List<HomeSection> sections;

  HomeSection? sectionFor(String route) {
    for (final section in sections) {
      if (section.route == route) return section;
    }
    return null;
  }

  /// The section order and toggles in the shape `NavLayout.fromJson` reads.
  /// Sections the server didn't send keep their default place.
  Map<String, Object?> navLayoutJson() => {
    'order': [for (final section in sections) section.route],
    'navHidden': [
      for (final section in sections)
        if (!section.showInNav) section.route,
    ],
    'home': {
      for (final section in sections) section.route: section.showOnHome,
    },
  };

  Map<String, Object?> toJson() {
    final keysByRoute = {
      for (final MapEntry(:key, :value) in sectionRoutes.entries) value: key,
    };
    return {
      'mode': enforced ? 'enforced' : 'default',
      'sections': [
        for (final section in sections)
          {
            'section': keysByRoute[section.route],
            'nav': section.showInNav,
            'home': section.showOnHome,
            'rows': [for (final row in section.rows) row.toJson()],
          },
      ],
    };
  }

  @override
  bool operator ==(Object other) =>
      other is HomeScreenConfig &&
      other.enforced == enforced &&
      listEquals(other.sections, sections);

  @override
  int get hashCode => Object.hash(enforced, Object.hashAll(sections));
}
