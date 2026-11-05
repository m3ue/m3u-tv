import 'package:flutter/foundation.dart';
import 'package:m3u_tv/navigation/route_names.dart';

/// The user's arrangement of the main destinations: one shared order that
/// drives both the nav and the Home rows, plus separate on/off choices for
/// each. Home and Search stay first and Notifications and Settings stay last,
/// so only the destinations between them are customizable.
///
/// Availability (DVR, Requests, Sports, AIOStreams) is not part of the layout:
/// a destination the current playlist lacks keeps its place and choices here,
/// for when it comes back.
@immutable
class NavLayout {
  const NavLayout._({
    required this.order,
    required this.hiddenFromNav,
    required this.homeRowChoices,
  });

  /// Reads a stored layout. Routes this version doesn't know are dropped, and
  /// routes the stored value doesn't know (added by a later release) join at
  /// their default position.
  factory NavLayout.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final known = customizableRoutes.toSet();
    final storedOrder = raw['order'];
    final order = <String>[
      if (storedOrder is List)
        for (final route in storedOrder.whereType<String>().toSet())
          if (known.contains(route)) route,
    ];
    for (var i = 0; i < customizableRoutes.length; i++) {
      final route = customizableRoutes[i];
      if (order.contains(route)) continue;
      final previousIndex = i == 0
          ? -1
          : order.indexOf(customizableRoutes[i - 1]);
      order.insert(previousIndex + 1, route);
    }
    final storedHidden = raw['navHidden'];
    final storedHome = raw['home'];
    return NavLayout._(
      order: List.unmodifiable(order),
      hiddenFromNav: Set.unmodifiable(<String>{
        if (storedHidden is List)
          for (final route in storedHidden.whereType<String>())
            if (known.contains(route)) route,
      }),
      homeRowChoices: Map.unmodifiable(<String, bool>{
        if (storedHome is Map)
          for (final entry in storedHome.entries)
            if (known.contains(entry.key) && entry.value is bool)
              entry.key as String: entry.value as bool,
      }),
    );
  }

  static const List<String> pinnedFirst = [RouteNames.home, RouteNames.search];
  static const List<String> pinnedLast = [
    RouteNames.notifications,
    RouteNames.settings,
  ];

  /// In default order, which is the order of [RouteNames.mainRoutes].
  static final List<String> customizableRoutes = List.unmodifiable(
    RouteNames.mainRoutes.where(
      (route) => !pinnedFirst.contains(route) && !pinnedLast.contains(route),
    ),
  );

  /// Entry-point rows that are opt-in, so a layout nobody touched keeps
  /// showing exactly the Home it always has.
  static const Set<String> homeRowsOffByDefault = {
    RouteNames.aiostreams,
    RouteNames.requests,
  };

  static final NavLayout defaults = NavLayout._(
    order: customizableRoutes,
    hiddenFromNav: const {},
    homeRowChoices: const {},
  );

  /// The customizable routes in display order.
  final List<String> order;
  final Set<String> hiddenFromNav;

  /// Only the choices the user made; everything else uses its default.
  final Map<String, bool> homeRowChoices;

  Map<String, Object?> toJson() => {
    'order': order,
    'navHidden': hiddenFromNav.toList(growable: false),
    'home': homeRowChoices,
  };

  bool showsInNav(String route) => !hiddenFromNav.contains(route);

  bool showsHomeRow(String route) =>
      homeRowChoices[route] ?? !homeRowsOffByDefault.contains(route);

  /// The destinations the sidebar and bottom bar list, out of [available].
  List<String> navRoutes(Iterable<String> available) {
    final availableRoutes = available.toSet();
    return [
      for (final route in [...pinnedFirst, ...order, ...pinnedLast])
        if (availableRoutes.contains(route) && showsInNav(route)) route,
    ];
  }

  /// The routes with a Home row turned on, top to bottom. Each row applies its
  /// own availability.
  List<String> get homeRowRoutes => [
    for (final route in order)
      if (showsHomeRow(route)) route,
  ];

  NavLayout withNav(String route, {required bool shown}) => NavLayout._(
    order: order,
    hiddenFromNav: Set.unmodifiable(
      shown ? hiddenFromNav.difference({route}) : hiddenFromNav.union({route}),
    ),
    homeRowChoices: homeRowChoices,
  );

  NavLayout withHomeRow(String route, {required bool shown}) => NavLayout._(
    order: order,
    hiddenFromNav: hiddenFromNav,
    homeRowChoices: Map.unmodifiable({...homeRowChoices, route: shown}),
  );

  /// Moves [route] by [delta] places among [available] routes. Unavailable
  /// routes aren't on screen to move past, so they keep their exact slots.
  NavLayout moved(String route, int delta, Iterable<String> available) {
    final availableRoutes = available.toSet();
    final movable = order.where(availableRoutes.contains).toList();
    final from = movable.indexOf(route);
    if (from < 0) return this;
    final to = (from + delta).clamp(0, movable.length - 1);
    if (to == from) return this;
    movable
      ..removeAt(from)
      ..insert(to, route);
    var next = 0;
    return NavLayout._(
      order: List.unmodifiable([
        for (final existing in order)
          if (availableRoutes.contains(existing)) movable[next++] else existing,
      ]),
      hiddenFromNav: hiddenFromNav,
      homeRowChoices: homeRowChoices,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NavLayout &&
      listEquals(order, other.order) &&
      setEquals(hiddenFromNav, other.hiddenFromNav) &&
      mapEquals(homeRowChoices, other.homeRowChoices);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(order),
    Object.hashAllUnordered(hiddenFromNav),
    Object.hashAllUnordered(
      homeRowChoices.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}
