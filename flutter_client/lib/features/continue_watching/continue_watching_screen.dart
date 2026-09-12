import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Full "Continue Watching" list, pushed from the Home row's overflow tile
/// once there are more resumable titles than fit in the row (see
/// `_HomeScreenState.build` in app_shell.dart). Renders the exact same
/// [MediaPreviewCard]s the row uses - same landscape size, same fallback
/// art, same tap target - so the row-to-grid transition reads as one
/// continuous surface rather than a different screen.
class ContinueWatchingScreen extends StatelessWidget {
  const ContinueWatchingScreen({
    super.key,
    required this.progressList,
    required this.vodItems,
    required this.seriesList,
    required this.onProgressSelect,
    this.onSidebarActivate,
  });

  final List<Progress> progressList;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final void Function(Progress) onProgressSelect;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final items = continueWatchingPreviewItems(
      context,
      progressList: progressList,
      vodItems: vodItems,
      seriesList: seriesList,
      onProgressSelect: onProgressSelect,
    );

    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          onSidebarActivate?.call();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 32, 24, 8),
              child: Row(
                children: [
                  DpadInkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(50)),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, size: 24 * scale),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Text(
                    l.homeContinueWatching,
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        l.homeNoContinueWatching,
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  // ExcludeSemantics avoids the tvOS framework bug where
                  // ScrollableState.setIgnorePointer calls
                  // markNeedsSemanticsUpdate during the semantics flush
                  // phase, causing an assertion crash when scrolling
                  // quickly - same guard MediaPreviewSection uses.
                  : ExcludeSemantics(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Wrap(
                          spacing: MediaBrowsingMetrics.itemGap,
                          runSpacing: MediaBrowsingMetrics.itemGap,
                          children: [
                            for (var i = 0; i < items.length; i++)
                              MediaPreviewCard(
                                item: items[i],
                                landscapeStyle: true,
                                cardWidth:
                                    MediaBrowsingMetrics.landscapeCardWidth,
                                autofocus: i == 0,
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
