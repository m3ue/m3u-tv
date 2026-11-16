import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:material_ui/material_ui.dart';

/// Lets a section screen (Live TV, Movies, Series) open on a category another
/// screen asked for through [categoryOpenRequestProvider]: Home's View all on
/// a server category row.
///
/// Covers both a screen that is already alive in its shell branch (it
/// listens) and one built by the navigation itself (it reads the pending
/// request on mount). Call [listenForCategoryRequests] from `initState`.
mixin CategoryOpenRequestListener<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// The route this screen answers for (a `RouteNames` main route).
  String get categoryRoute;

  /// Shows [categoryId]. Called at most once per request.
  void openRequestedCategory(String categoryId);

  void listenForCategoryRequests() {
    ref.listenManual<CategoryOpenRequest?>(
      categoryOpenRequestProvider,
      (_, request) => _take(request),
      fireImmediately: true,
    );
  }

  void _take(CategoryOpenRequest? request) {
    if (request == null || request.route != categoryRoute) return;
    openRequestedCategory(request.categoryId);
    // After the frame: a provider can't change while widgets are building,
    // which is where a freshly mounted screen reads it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(categoryOpenRequestProvider.notifier);
      if (pending.state == request) pending.state = null;
    });
  }
}
