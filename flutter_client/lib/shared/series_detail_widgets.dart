import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:intl/intl.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_strip.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart' show isDesktopPlatform;
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart'
    show detailAppBarHeight;
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Shared building blocks for the series-style detail screens (Xtream Series
/// and the AIOStreams series body): the season picker, the locked-focus
/// episode strip and its cards, the vertical row-scroll region that stacks the
/// episode strip over the cast row on TV/desktop, and the mark-watched
/// confirmation modal. Extracted from `series_details_screen.dart` so both
/// screens render the exact same, on-device-tuned D-pad behaviour.

const double kEpisodeCardWidthWide = 340;
const double kEpisodeCardWidthCompact = 250;

/// Text area under an episode thumbnail (3-line plot + date + padding).
const double kEpisodeCardTextHeight = 96;

String? trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Formats an episode air date ("2025-10-01") as "Oct 1, 2025". Falls back to
/// the raw string when it will not parse.
String? formatEpisodeDate(String? raw, String localeTag) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return raw.trim();
  try {
    return DateFormat.yMMMd(localeTag).format(parsed);
  } on Object catch (_) {
    return DateFormat.yMMMd().format(parsed);
  }
}

/// Shared confirmation modal for the mark-watched long-press affordances.
/// Resolves to the chosen watched state, or null when dismissed. Pass
/// [presetWatched] to offer only that single action (episode toggle); leave it
/// null to offer both watched and unwatched (season bulk action).
Future<bool?> confirmMarkWatched(
  BuildContext context, {
  required String title,
  required String message,
  bool? presetWatched,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmMarkDialog(
      title: title,
      message: message,
      presetWatched: presetWatched,
    ),
  );
}

class _ConfirmMarkDialog extends StatefulWidget {
  const _ConfirmMarkDialog({
    required this.title,
    required this.message,
    this.presetWatched,
  });

  final String title;
  final String message;
  final bool? presetWatched;

  @override
  State<_ConfirmMarkDialog> createState() => _ConfirmMarkDialogState();
}

class _ConfirmMarkDialogState extends State<_ConfirmMarkDialog> {
  // The D-pad long-press that opens this dialog is still physically held; on
  // release the package routes a phantom "select" to whichever button now has
  // focus, which would instantly confirm. Ignore every action until a short
  // arm delay has passed (matches the guard style in `dpad_ink_well.dart`).
  bool _armed = false;
  Timer? _armTimer;

  @override
  void initState() {
    super.initState();
    _armTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  void _pop(bool? result) {
    if (!_armed) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final preset = widget.presetWatched;
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
        DpadRegion(
          memoryKey: 'series/mark-watched-dialog-actions',
          // OverflowBar (not Row) so the buttons stack vertically on a narrow
          // dialog instead of overflowing. Same shared-button treatment as the
          // resume and DVR modals.
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              AppButton(
                label: l.cancel,
                onPressed: () => _pop(null),
              ),
              if (preset != true)
                AppButton(
                  label: l.seriesMarkUnwatched,
                  variant: preset == false
                      ? AppButtonVariant.primary
                      : AppButtonVariant.tonal,
                  autofocus: preset == false,
                  onPressed: () => _pop(false),
                ),
              if (preset != false)
                AppButton(
                  label: l.seriesMarkWatched,
                  variant: AppButtonVariant.primary,
                  autofocus: true,
                  onPressed: () => _pop(true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dropdown button that opens a poster + overview season picker (a centered
/// dialog on TV/desktop, a bottom sheet on a phone). Long-pressing it, when
/// [canMarkWatched] is set, offers a bulk mark-watched for the current season.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selectedSeason,
    required this.canMarkWatched,
    required this.compact,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.onSeasonSelected,
    required this.onMarkSeason,
    this.focusNode,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;

  /// Optional focus node for the picker button, so a sibling (e.g. the
  /// episode strip's "exit top" hop) can return focus to it.
  final FocusNode? focusNode;

  /// Phone layout: the picker opens as a bottom sheet instead of a centered
  /// dialog.
  final bool compact;

  /// Episode tally for a given season number (0 when unknown).
  final int Function(int seasonNumber) episodeCountFor;

  /// Series poster, shown in the pick-list when a season has no art of its own.
  final String? fallbackPosterUrl;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<bool> onMarkSeason;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final current = selectedSeason;
    final count = current != null ? episodeCountFor(current) : 0;
    // No size overrides - shares AppButton's default metrics so it lines up
    // with the play / start-over buttons beside it.
    return AppButton(
      focusNode: focusNode,
      label: current != null ? l.homeSeason(current) : l.seriesSeasons,
      icon: Icons.arrow_drop_down,
      badgeCount: count > 0 ? count : null,
      // Muted, not the default error red - this is an episode tally, not an
      // unwatched/new alert.
      badgeColor: scheme.surfaceContainerHighest,
      badgeTextColor: scheme.onSurfaceVariant,
      onPressed: () => _showPicker(context),
      onLongPress: canMarkWatched && current != null
          ? () => unawaited(_showMarkSeasonSheet(context, current))
          : null,
    );
  }

  void _showPicker(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Focus lands on the current season (or the first one) so the list is
    // immediately drivable by D-pad.
    final focusSeason = selectedSeason ?? seasons.first.number;

    // Header (title + close affordance) and the season rows live in ONE
    // DpadRegion, so D-pad up from the first row reaches the close button.
    // Traversal stops at the region edges instead of escaping the
    // sheet/dialog. The list is height-capped with a ConstrainedBox (not
    // Flexible) so the layout stays deterministic inside AlertDialog's
    // intrinsic sizing - a Flexible there lets the rows overflow the dialog's
    // clip and drop out of hit-testing.
    //
    // [modalContext] is the sheet/dialog builder's own context: every dismiss
    // (close button, a season pick) must pop through it, NOT the outer
    // `_showPicker` context, which resolves to the screen's navigator and
    // would pop the whole route while leaving the modal on the root navigator.
    Widget pickerBody(
      BuildContext modalContext, {
      required EdgeInsetsGeometry listPadding,
      required double maxListHeight,
      bool showThumb = false,
    }) {
      return DpadRegion(
        verticalEdge: DpadEdgeBehavior.stop,
        horizontalEdge: DpadEdgeBehavior.stop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.seriesSeasons,
                      style: Theme.of(modalContext).textTheme.titleLarge,
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close,
                    dense: true,
                    tooltip: l.cancel,
                    onPressed: () => Navigator.of(modalContext).pop(),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: Scrollbar(
                thumbVisibility: showThumb,
                child: ListView(
                  shrinkWrap: true,
                  // Inset so a focused row's gradient border sits clear of the
                  // container edge and the scrollbar.
                  padding: listPadding,
                  children: seasons
                      .map(
                        (season) => _seasonTile(
                          modalContext,
                          season,
                          autofocus: season.number == focusSeason,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;

    if (compact) {
      // Phone: a bottom sheet reads more naturally than a centered dialog and
      // keeps the tap targets in thumb reach.
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: pickerBody(
              sheetContext,
              listPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              maxListHeight: viewportHeight * 0.7,
            ),
          ),
        ),
      );
      return;
    }

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          clipBehavior: Clip.antiAlias,
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          content: SizedBox(
            width: 460 * FontSizeScope.scaleOf(dialogContext),
            child: pickerBody(
              dialogContext,
              listPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              maxListHeight: viewportHeight * 0.65,
              showThumb: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _seasonTile(
    BuildContext context,
    Season season, {
    required bool autofocus,
  }) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = episodeCountFor(season.number);
    final seasonCover = trimmedOrNull(season.coverUrl);
    final overview = trimmedOrNull(season.overview);
    final selected = season.number == selectedSeason;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DpadInkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        onTap: () {
          onSeasonSelected(season.number);
          Navigator.of(context).pop();
        },
        // Poster + text laid out by hand (not a ListTile) so nothing gets
        // crushed to fit a short two-line row.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: AspectRatio(
                  aspectRatio: 0.68,
                  child: ResilientMediaImage(
                    imageUrl: seasonCover ?? fallbackPosterUrl,
                    fallbackImageUrls:
                        seasonCover != null && fallbackPosterUrl != null
                        ? <String>[fallbackPosterUrl!]
                        : const <String>[],
                    fallbackIcon: Icons.tv,
                    borderRadius: 6,
                    fallbackTitle: season.name,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        season.name.isNotEmpty
                            ? season.name
                            : l.homeSeason(season.number),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (count > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l.seriesEpisodeCount(count),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (overview != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            overview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // A plain checkmark (not primary-tinted text) marks the active
              // season, so it reads as "this one is selected" rather than
              // being mistaken for the D-pad cursor.
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Icon(Icons.check, size: 22, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMarkSeasonSheet(
    BuildContext context,
    int seasonNumber,
  ) async {
    final l = AppLocalizations.of(context);
    final choice = await confirmMarkWatched(
      context,
      title: l.homeSeason(seasonNumber),
      message: l.seriesMarkSeasonPrompt(seasonNumber),
    );
    if (choice != null) onMarkSeason(choice);
  }
}

/// Horizontal strip of episode thumbnail cards: a 16:9 still with the title,
/// SxEy, rating and runtime overlaid, the plot synopsis below, and a progress
/// bar / watched check when the viewer has history. Long-pressing a card
/// toggles its watched state.
class EpisodeStrip extends StatefulWidget {
  const EpisodeStrip({
    super.key,
    required this.episodes,
    required this.progressList,
    required this.onEpisodeSelected,
    required this.onMarkEpisode,
    required this.cardWidth,
    this.canMarkWatched = false,
    this.autofocusFirst = true,
    this.horizontal = true,
    this.progressResolver,
  });

  final List<Episode> episodes;
  final List<Progress> progressList;

  /// Resolves the watch-progress row for an episode. Defaults to matching
  /// `int.tryParse(episode.id)` against `Progress.streamId` (Xtream, where the
  /// episode id IS the stream id). AIOStreams episode ids are Stremio strings,
  /// so it passes a resolver that matches on season + episode number instead.
  final Progress? Function(Episode episode)? progressResolver;
  final void Function(Episode episode, {double? startPosition})
  onEpisodeSelected;
  final void Function(Episode episode, {required bool watched}) onMarkEpisode;
  final double cardWidth;
  final bool canMarkWatched;
  final bool autofocusFirst;

  /// Horizontal thumbnail strip (TV/desktop) vs. a vertical list (phone).
  final bool horizontal;

  @override
  State<EpisodeStrip> createState() => EpisodeStripState();
}

class EpisodeStripState extends State<EpisodeStrip>
    with SingleTickerProviderStateMixin
    implements LockedRow {
  final ScrollController _controller = ScrollController();

  // Drives the fade + slight rightward slide the strip plays on first build
  // and each time the season (and with it the whole episode list) changes,
  // so the new episodes ease in rather than snapping over the old ones.
  late final AnimationController _seasonAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _seasonFade = CurvedAnimation(
    parent: _seasonAnim,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _seasonSlide =
      Tween<Offset>(
        begin: const Offset(0.05, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: _seasonAnim, curve: Curves.easeOutCubic),
      );

  // TV / desktop only: the whole strip is one focus stop. `_focusedIndex` is
  // the highlighted card; `_hasFocus` mirrors the strip node so the cards
  // only paint a border while the row actually holds focus.
  final FocusNode _focusNode = FocusNode(debugLabel: 'episodeStrip');
  final SelectHold _selectHold = SelectHold();
  int _focusedIndex = 0;
  bool _hasFocus = false;

  /// Set on the wide layout: the enclosing scroll region this strip is a row
  /// of. Drives both the into-view reveal and up/down row hops. Null on the
  /// phone layout (plain page scroll, no region).
  RowScrollRegionState? _region;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    unawaited(_seasonAnim.forward());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.horizontal) return;
    final region = RowScrollRegion.of(context);
    if (region != _region) {
      _region?.unregisterRow(this);
      _region = region;
      _region?.registerRow(this);
    }
  }

  @override
  void didUpdateWidget(EpisodeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A season switch swaps the episode list under the row; keep the cursor
    // in range so the next left/right starts from a real card, and replay the
    // ease-in so the new season's episodes animate over the old ones instead
    // of snapping.
    if (!identical(oldWidget.episodes, widget.episodes)) {
      unawaited(_seasonAnim.forward(from: 0));
    }
    if (_focusedIndex >= widget.episodes.length) {
      _focusedIndex = widget.episodes.isEmpty ? 0 : widget.episodes.length - 1;
    }
  }

  @override
  void dispose() {
    _region?.unregisterRow(this);
    _selectHold.dispose();
    _seasonAnim.dispose();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      // Focus can also arrive from outside the region (autofocus on load, or
      // down from the Play button via dpad traversal). Centre the cursor and
      // reveal the strip either way; focusRow() does the same when the hop
      // comes from a sibling row.
      _centerFocused(animate: false);
      _region?.reveal(context);
    }
  }

  @override
  void focusRow() {
    _focusNode.requestFocus();
    _centerFocused(animate: false);
    _region?.reveal(context);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (SelectHold.isSelectKey(key)) {
      return _selectHold.handle(
        event,
        isActive: () => mounted,
        onTap: _selectFocused,
        onLongPress: widget.canMarkWatched ? _longSelectFocused : null,
      );
    }
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isDown) _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isDown) _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final region = _region;
      if (region == null) return KeyEventResult.ignored;
      if (isDown) region.navigateVertical(this, up: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final region = _region;
      if (region == null) return KeyEventResult.ignored;
      if (isDown) region.navigateVertical(this, up: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double get _itemExtent => widget.cardWidth + MediaBrowsingMetrics.itemGap;

  /// Scroll the row's OWN controller so the focused card is centered. This is
  /// the only place the strip scrolls horizontally and it never walks an
  /// ancestor scrollable - the reason left/right navigation no longer drags
  /// the page. (dpad's focus-follow reveal only ever pulled the page when
  /// each card was its own focus node.)
  ///
  /// KNOWN ISSUE (not yet bullet-proof - needs more device testing): under
  /// aggressive fast left/right key-repeat this `animateTo` can still land its
  /// `DrivenScrollActivity` goBallistic -> goIdle transition inside the
  /// semantics flush, tripping Flutter's
  /// `!attached || !owner!._debugDoingSemantics` assertion storm
  /// (`ScrollableState.setIgnorePointer` -> `RenderIgnorePointer.ignoring=` ->
  /// `markNeedsSemanticsUpdate`). It is visually harmless (debug-only assert)
  /// and self-recovers, but the real fix is still open. A
  /// `FrameSafeScrollController` that deferred/collapsed these jumps out of the
  /// frame pipeline killed the asserts but broke normal recenter (focus
  /// advanced, scroll lagged a frame and sometimes never landed), so it was
  /// reverted. Candidate directions to try next: gate the recenter to
  /// KeyDown-only (skip KeyRepeat), debounce `_centerFocused`, or drop the
  /// tween for an unconditional `jumpTo` on repeat.
  void _centerFocused({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final target =
          (_focusedIndex * _itemExtent +
                  widget.cardWidth / 2 -
                  position.viewportDimension / 2)
              .clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      if (animate) {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ),
        );
      } else {
        position.jumpTo(target);
      }
    });
  }

  void _moveFocus(int delta) {
    if (widget.episodes.isEmpty) return;
    final target = (_focusedIndex + delta).clamp(0, widget.episodes.length - 1);
    if (target == _focusedIndex) return;
    setState(() => _focusedIndex = target);
    _centerFocused();
  }

  Episode? get _focusedEpisode =>
      (_focusedIndex >= 0 && _focusedIndex < widget.episodes.length)
      ? widget.episodes[_focusedIndex]
      : null;

  void _selectFocused() {
    final episode = _focusedEpisode;
    if (episode != null) widget.onEpisodeSelected(episode);
  }

  Progress? _progressFor(Episode episode) {
    final resolver = widget.progressResolver;
    if (resolver != null) return resolver(episode);
    final streamId = int.tryParse(episode.id);
    if (streamId == null) return null;
    return widget.progressList._firstWhereOrNull((p) => p.streamId == streamId);
  }

  void _longSelectFocused() {
    final episode = _focusedEpisode;
    if (episode == null) return;
    final progress = _progressFor(episode);
    unawaited(
      _confirmEpisode(episode, watched: !(progress?.completed ?? false)),
    );
  }

  Future<void> _confirmEpisode(
    Episode episode, {
    required bool watched,
  }) async {
    final choice = await confirmMarkWatched(
      context,
      title: 'S${episode.seasonNumber}E${episode.episodeNumber}',
      message: episode.title,
      presetWatched: watched,
    );
    if (choice != null) widget.onMarkEpisode(episode, watched: choice);
  }

  Widget _card(BuildContext context, int index) {
    final episode = widget.episodes[index];
    final progress = _progressFor(episode);
    final completed = progress?.completed ?? false;
    final fraction =
        (progress != null &&
            progress.durationSeconds != null &&
            progress.durationSeconds! > 0 &&
            !completed)
        ? (progress.positionSeconds / progress.durationSeconds!).clamp(0.0, 1.0)
        : null;

    return EpisodeCard(
      episode: episode,
      width: widget.cardWidth,
      horizontal: widget.horizontal,
      completed: completed,
      progressFraction: fraction,
      dateLabel: formatEpisodeDate(
        episode.releaseDate,
        Localizations.localeOf(context).toLanguageTag(),
      ),
      // Horizontal (TV/desktop): the strip owns focus, the card only shows the
      // border when it is the current index. Vertical (phone): each card owns
      // its focus node, so the first one autofocuses.
      focused: widget.horizontal && _hasFocus && index == _focusedIndex,
      autofocus: !widget.horizontal && widget.autofocusFirst && index == 0,
      onTap: () => widget.onEpisodeSelected(episode),
      onLongTap: widget.canMarkWatched
          ? () => unawaited(_confirmEpisode(episode, watched: !completed))
          : null,
    );
  }

  /// Wraps the strip in the fade + slide the season transition plays.
  Widget _withSeasonTransition(Widget child) => FadeTransition(
    opacity: _seasonFade,
    child: SlideTransition(position: _seasonSlide, child: child),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.horizontal) {
      // Phone: a plain vertical column - the page's own scroll view drives it,
      // so no inner ListView / ScrollController.
      return _withSeasonTransition(
        DpadRegion(
          verticalEdge: DpadEdgeBehavior.stop,
          child: Column(
            children: [
              for (var i = 0; i < widget.episodes.length; i++) ...[
                if (i > 0) const SizedBox(height: MediaBrowsingMetrics.itemGap),
                _card(context, i),
              ],
            ],
          ),
        ),
      );
    }
    // TV / desktop: a "locked focus" row, modelled on Plezy. The whole strip
    // is ONE plain Focus stop whose onKeyEvent handles every arrow + select
    // key itself and always consumes them - so nothing ever reaches dpad's
    // directional traversal / "scroll for more" retry, which was leaving
    // focus a row behind and the strip clipped on tvOS. left/right move an
    // internal index and scroll this row's own controller; up/down go to the
    // enclosing RowScrollRegion.
    // No Scrollbar wrapper: it reacts to every scroll-position change and,
    // under fast key-repeat, its interplay with the ListView's own
    // ignore-pointer toggling during scroll-activity transitions throws the
    // `!_debugDoingSemantics` assertion storm. The cast row (identical minus
    // the Scrollbar) never races - so the strip drops it too. Desktop still
    // scrolls the ListView with the mouse wheel directly.
    return _withSeasonTransition(
      Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocusFirst,
        descendantsAreFocusable: false,
        onKeyEvent: _handleKeyEvent,
        // Desktop mouse users get hover arrows (the scrollbar is hidden); TV /
        // phone pass straight through and D-pad / touch drive the scroll.
        child: HoverScrollArrows(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: widget.episodes.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(
                right: MediaBrowsingMetrics.itemGap,
              ),
              child: _card(context, index),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single episode card. Horizontal (TV/desktop): a fixed-width 16:9 still
/// with title + SxEy + rating + runtime overlaid over a bottom-up scrim, plot
/// synopsis and air date beneath. Vertical (phone): a full-width row with a
/// small thumbnail on the left and the title / meta / plot / date beside it.
class EpisodeCard extends StatelessWidget {
  const EpisodeCard({
    super.key,
    required this.episode,
    required this.width,
    required this.completed,
    required this.progressFraction,
    required this.dateLabel,
    required this.autofocus,
    required this.onTap,
    this.onLongTap,
    this.horizontal = true,
    this.focused = false,
  });

  final Episode episode;
  final double width;
  final bool completed;
  final double? progressFraction;
  final String? dateLabel;

  /// Vertical (phone) only: this card owns its focus node and grabs focus on
  /// first build.
  final bool autofocus;

  /// Horizontal (TV/desktop) only: the parent [EpisodeStrip] owns focus and
  /// tells this card when it is the highlighted one, so it paints its border.
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback? onLongTap;
  final bool horizontal;

  Widget _pill(BuildContext context, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: child,
    ),
  );

  Widget _pillText(BuildContext context, String text) => _pill(
    context,
    Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final runtime = episode.duration;

    if (!horizontal) {
      return _buildVertical(context, theme, colorScheme, runtime);
    }

    final imageHeight = width * 9 / 16;
    final titleBase = theme.textTheme.titleSmall;
    // ~60% larger than the stock card title.
    final titleStyle = titleBase?.copyWith(
      fontSize: (titleBase.fontSize ?? 14) * 1.6,
      height: 1.15,
      color: Colors.white,
      fontWeight: FontWeight.w700,
      shadows: const [
        Shadow(blurRadius: 4, color: Colors.black87, offset: Offset(0, 1)),
      ],
    );

    final radius = BorderRadius.circular(MediaBrowsingMetrics.cardRadius);
    // Not focusable on its own: the enclosing EpisodeStrip is the single dpad
    // stop and passes `focused` down. The Material + InkWell keep the pointer
    // ripple; the border is painted by the same GradientBorderEffect a
    // DpadInkWell would apply.
    Widget body = Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongTap,
        borderRadius: radius,
        canRequestFocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: width,
              height: imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ResilientMediaImage(
                    imageUrl: episode.thumbnailUrl,
                    fallbackIcon: Icons.tv,
                    width: width,
                    height: imageHeight,
                    fallbackTitle: episode.title,
                    borderRadius: 0,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Color(0xE0000000),
                        ],
                        stops: [0.0, 0.35, 1.0],
                      ),
                    ),
                  ),
                  if (completed)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _pill(
                        context,
                        const Icon(
                          Icons.check,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: progressFraction != null ? 8 : 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          episode.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _pillText(
                              context,
                              'S${episode.seasonNumber}E${episode.episodeNumber}',
                            ),
                            if (episode.rating != null)
                              _pillText(
                                context,
                                '★ ${episode.rating!.toStringAsFixed(1)}',
                              ),
                            if (runtime != null && runtime.isNotEmpty)
                              _pillText(context, runtime),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (progressFraction != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progressFraction,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (episode.plot != null && episode.plot!.trim().isNotEmpty)
                      Flexible(
                        child: Text(
                          episode.plot!.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (dateLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    body = GradientBorderEffect(borderRadius: radius).build(
      context,
      DpadFocusState(focused: focused, pressed: false),
      body,
    );
    return SizedBox(width: width, child: body);
  }

  Widget _buildVertical(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    String? runtime,
  ) {
    const thumbWidth = 132.0;
    const thumbHeight = thumbWidth * 9 / 16;
    final metaParts = <String>[
      'S${episode.seasonNumber}E${episode.episodeNumber}',
      if (episode.rating != null) '★ ${episode.rating!.toStringAsFixed(1)}',
      if (runtime != null && runtime.isNotEmpty) runtime,
    ];

    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      onLongTap: onLongTap,
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: thumbWidth,
                height: thumbHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ResilientMediaImage(
                      imageUrl: episode.thumbnailUrl,
                      fallbackIcon: Icons.tv,
                      width: thumbWidth,
                      height: thumbHeight,
                      fallbackTitle: episode.title,
                      borderRadius: 0,
                    ),
                    if (completed)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _pill(
                          context,
                          const Icon(
                            Icons.check,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (progressFraction != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progressFraction,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metaParts.join('  ·  '),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (episode.plot != null &&
                      episode.plot!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      episode.plot!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (dateLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dateLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A locked-focus row that lives inside a [RowScrollRegion]: the whole row is
/// one focus stop, left/right move an internal index, and up/down are routed
/// to the region (which focuses the adjacent row or hands off above).
// ignore: one_member_abstracts
abstract class LockedRow {
  /// Take focus, park the internal cursor, and scroll self into view.
  void focusRow();
}

/// The wide series-detail vertical scroll region (episode strip + cast strip).
///
/// This is modelled on Plezy's TV detail: every row is a plain `Focus` widget
/// whose `onKeyEvent` handles left/right/up/down/select itself and *always*
/// consumes them, so no key ever reaches a traversal policy. dpad's directional
/// traversal + "scroll for more" retry were what left focus stuck a row behind
/// (needing 2-3 presses) and the strip clipped on tvOS.
///
///  * **Row hop** - a row's up/down calls `navigateVertical`, which focuses the
///    adjacent registered row directly (or `onExitTop` at the top, wired to the
///    Play button).
///  * **Reveal** - `reveal` scrolls a row fully into view, computed against
///    this region's own box + controller and run over two frames so a slower
///    tvOS layout pass cannot strand it.
class RowScrollRegion extends StatefulWidget {
  const RowScrollRegion({
    super.key,
    required this.child,
    this.onExitTop,
    this.controller,
  });

  final Widget child;

  /// Called when up is pressed on the top row - focus the Play button.
  final VoidCallback? onExitTop;

  /// External controller (e.g. so an ancestor can drive a parallax backdrop
  /// off the same offset). The caller owns disposal in that case; when null,
  /// the region creates and disposes its own.
  final ScrollController? controller;

  /// Never returns null spuriously the way an inherited-widget lookup can when
  /// the scope is not wired yet (a tvOS-vs-desktop tree-timing difference that
  /// left `focusRow` and `reveal` no-ops).
  static RowScrollRegionState? of(BuildContext context) =>
      context.findAncestorStateOfType<RowScrollRegionState>();

  @override
  State<RowScrollRegion> createState() => RowScrollRegionState();
}

class RowScrollRegionState extends State<RowScrollRegion> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool get _ownsController => widget.controller == null;

  /// Rows in registration order, which is mount order, which is top-to-bottom
  /// (the episode strip builds before the cast strip).
  final List<LockedRow> _rows = [];

  void registerRow(LockedRow row) {
    if (!_rows.contains(row)) _rows.add(row);
  }

  void unregisterRow(LockedRow row) => _rows.remove(row);

  /// Route an up/down press from [from]. Always "handled" from the caller's
  /// point of view - focus either lands on the adjacent row, hands off above
  /// the region, or (nothing below) stays put.
  void navigateVertical(LockedRow from, {required bool up}) {
    final index = _rows.indexOf(from);
    if (index < 0) return;
    final targetIndex = index + (up ? -1 : 1);
    if (targetIndex < 0) {
      widget.onExitTop?.call();
      return;
    }
    if (targetIndex >= _rows.length) return;
    _rows[targetIndex].focusRow();
  }

  /// Scroll so [target]'s render box sits fully inside the viewport with [pad]
  /// px clear of whichever edge clipped it. No-op when it already is.
  ///
  /// Runs the correction next frame and again the frame after, so a relayout
  /// from the same focus change (or a slower tvOS pipeline) cannot strand the
  /// first pass. Geometry comes from this region's own render box and
  /// [_controller] - never an ambiguous ancestor-viewport lookup.
  void reveal(BuildContext target, {double pad = 16}) {
    void pass() {
      if (!mounted || !_controller.hasClients) return;
      final box = target.findRenderObject();
      final regionBox = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      if (regionBox is! RenderBox || !regionBox.hasSize) return;
      final position = _controller.position;
      final viewportHeight = position.viewportDimension;
      final topInRegion = box
          .localToGlobal(Offset.zero, ancestor: regionBox)
          .dy;
      final bottomInRegion = topInRegion + box.size.height;

      double delta;
      if (topInRegion < pad) {
        delta = topInRegion - pad; // clipped at top -> scroll up
      } else if (bottomInRegion > viewportHeight - pad) {
        delta = bottomInRegion - (viewportHeight - pad); // clipped at bottom
        final maxDelta = topInRegion - pad; // don't push our own top off
        if (delta > maxDelta) delta = maxDelta;
      } else {
        return; // already fully visible
      }
      if (delta.abs() < 0.5) return;
      final to = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((to - position.pixels).abs() < 0.5) return;
      unawaited(
        position.animateTo(
          to,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      pass();
      WidgetsBinding.instance.addPostFrameCallback((_) => pass());
    });
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gesture/momentum scrolling is disabled on TV/D-pad navigation so the
    // vertical offset can only move via our own reveal()/navigateVertical()
    // calls - nothing ambient left to fight the rails' own horizontal
    // centering, which is what caused the scroll-drift jank previously.
    // Desktop mouse/trackpad keeps default physics for ambient wheel-scroll.
    final physics = isDesktopPlatform(context)
        ? null
        : const NeverScrollableScrollPhysics();
    return SingleChildScrollView(
      controller: _controller,
      physics: physics,
      child: widget.child,
    );
  }
}

/// Tracks the D-pad SELECT key for a locked-focus row: a short press fires
/// `onTap` on key up, a hold past `_holdDuration` fires `onLongPress`.
/// Every select event is consumed so it never reaches a platform handler.
class SelectHold {
  static const _holdDuration = Duration(milliseconds: 500);

  Timer? _timer;
  bool _down = false;
  bool _longFired = false;

  static final Set<LogicalKeyboardKey> _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  static bool isSelectKey(LogicalKeyboardKey key) => _selectKeys.contains(key);

  KeyEventResult handle(
    KeyEvent event, {
    required bool Function() isActive,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    if (onLongPress == null) {
      if (event is KeyDownEvent) onTap();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (!_down) {
        _down = true;
        _longFired = false;
        _timer?.cancel();
        _timer = Timer(_holdDuration, () {
          if (!isActive() || !_down) return;
          _longFired = true;
          onLongPress();
        });
      }
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    // KeyUpEvent: short press if the hold timer had not fired yet.
    _timer?.cancel();
    if (_down && !_longFired) onTap();
    _down = false;
    return KeyEventResult.handled;
  }

  void dispose() => _timer?.cancel();
}

/// Bridges the shared [CastStrip] to a [RowScrollRegion]: registers as a
/// [LockedRow] so the episode strip can hop down into it (and it can hop back
/// up), and routes the strip's reveal through the region.
class CastRow extends StatefulWidget {
  const CastRow({super.key, required this.members});

  final List<CastMember> members;

  @override
  State<CastRow> createState() => _CastRowState();
}

class _CastRowState extends State<CastRow> implements LockedRow {
  final GlobalKey<CastStripState> _stripKey = GlobalKey<CastStripState>();
  RowScrollRegionState? _region;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final region = RowScrollRegion.of(context);
    if (region != _region) {
      _region?.unregisterRow(this);
      _region = region;
      _region?.registerRow(this);
    }
  }

  @override
  void dispose() {
    _region?.unregisterRow(this);
    super.dispose();
  }

  @override
  void focusRow() => _stripKey.currentState?.focusRow();

  @override
  Widget build(BuildContext context) {
    return CastStrip(
      key: _stripKey,
      members: widget.members,
      onNavigateUp: () => _region?.navigateVertical(this, up: true),
      // Consume down so focus never escapes below the cast row.
      onNavigateDown: () => _region?.navigateVertical(this, up: false),
      onReveal: (ctx) => _region?.reveal(ctx),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? _firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// Card-shuffle transition for the season poster. The incoming poster slides
/// up into place from the top-right with a slight counter-rotation and scale
/// settle; run in reverse (the outgoing poster) it deals the old card back
/// off toward the same corner. Mirrors the fade + slide the episode strip
/// plays on a season change so the two move together. Shared by the Series
/// detail screen and the AIOStreams series detail body so the poster flip
/// stays identical between them.
Widget posterShuffleTransition(Widget child, Animation<double> animation) {
  final eased = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: eased,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.22, -0.16),
        end: Offset.zero,
      ).animate(eased),
      child: RotationTransition(
        turns: Tween<double>(begin: 0.025, end: 0).animate(eased),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(eased),
          child: child,
        ),
      ),
    ),
  );
}

/// Shared layout scaffold for a series-style detail page - poster + meta +
/// season picker over a colour-matched [BackdropDetailHero], with the episode
/// strip (and, on TV/desktop, the cast row) stacked in a [RowScrollRegion]
/// below. Used by both the Xtream Series detail and the AIOStreams series body
/// so the two cannot drift on poster sizing, the poster card-flip, breakpoint,
/// scrim, or the season / episode / cast composition. Per-source behaviour
/// (hero-button targeting, mark-watched plumbing, progress matching, the
/// season-0 relabel, the stream-picker sheet) stays with the caller: the
/// primary-action buttons arrive as [primaryActions] and the meta block as a
/// pre-built [meta] widget.
class SeriesDetailBody extends StatelessWidget {
  const SeriesDetailBody({
    super.key,
    required this.seriesName,
    required this.posterChain,
    required this.backdropUrl,
    required this.seasons,
    required this.selectedSeason,
    required this.resolvedSeason,
    required this.episodes,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.meta,
    required this.primaryActions,
    required this.richCast,
    required this.castSemanticLabel,
    required this.progressList,
    required this.canMarkWatched,
    required this.emptyEpisodesLabel,
    required this.colorMatchReady,
    required this.onSeasonSelected,
    required this.onEpisodeSelected,
    required this.onMarkEpisode,
    required this.onMarkSeason,
    required this.onExitTop,
    this.progressResolver,
    this.onSeasonResolved,
    this.seasonPickerFocusNode,
    this.autofocusFirstEpisode = true,
    this.dominantColor,
    this.compactBreakpoint = 700,
    this.scrollController,
  });

  final String seriesName;

  /// Season cover -> series cover -> backdrop. Passed as a chain so a season
  /// cover that 404s falls through at load time rather than sticking.
  final List<String> posterChain;
  final String? backdropUrl;

  final List<Season> seasons;
  final int? selectedSeason;

  /// Season currently shown (user pick or the caller's auto-resolved default);
  /// keys the poster and drives which [episodes] were passed.
  final int? resolvedSeason;

  /// Episodes for [resolvedSeason], already sorted / adapted by the caller.
  final List<Episode> episodes;
  final int Function(int seasonNumber) episodeCountFor;
  final String? fallbackPosterUrl;

  /// The caller's `ItemMetaInfo` (Xtream: Play label + resume bar; AIOStreams:
  /// `hidePrimaryAction: true`).
  final Widget meta;

  /// Play / Start-over buttons on the same line as the season picker. Empty
  /// for AIOStreams (no hero play button).
  final List<Widget> primaryActions;

  final List<CastMember>? richCast;
  final String castSemanticLabel;

  final List<Progress> progressList;
  final Progress? Function(Episode episode)? progressResolver;

  final bool canMarkWatched;
  final bool autofocusFirstEpisode;
  final String emptyEpisodesLabel;
  final double compactBreakpoint;

  final Color? dominantColor;
  final bool colorMatchReady;

  final FocusNode? seasonPickerFocusNode;

  /// Page-level scroll controller for the wide/TV layout (owned by the
  /// caller so it can also snap the page back to top when the AppBar's back
  /// button takes focus - see `ItemDetailScaffold.onBackButtonFocused`).
  /// Null lets [_SeriesScrollHost] create and own its own; ignored on
  /// compact.
  final ScrollController? scrollController;

  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<int?>? onSeasonResolved;
  final void Function(Episode episode, {double? startPosition})
  onEpisodeSelected;
  final void Function(Episode episode, {required bool watched}) onMarkEpisode;
  final void Function(List<Episode> episodes, {required bool watched})
  onMarkSeason;

  /// Where focus goes on "up" out of the top row (Xtream: the play button;
  /// AIOStreams: the season picker).
  final VoidCallback onExitTop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < compactBreakpoint;
    final bg = dominantColor != null
        ? deepBackdropTone(dominantColor!, vivid: compact)
        : theme.colorScheme.surface;
    final scale = FontSizeScope.scaleOf(context);
    final posterWidth = (compact ? 120.0 : 200.0) * scale;
    final cardWidth =
        (compact ? kEpisodeCardWidthCompact : kEpisodeCardWidthWide) * scale;
    // The episode title/subtitle text below the thumbnail grows with the
    // user's font-size setting (global TextScaler in main.dart) on top of
    // the `cardWidth` multiplication above, so it needs its own (larger)
    // budget or a larger setting clips/overflows the card's text block.
    final stripHeight = cardWidth * 9 / 16 + kEpisodeCardTextHeight * scale;
    final firstPoster = posterChain.isEmpty ? '' : posterChain.first;

    final poster = SizedBox(
      width: posterWidth,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: posterShuffleTransition,
          // Keep the outgoing poster painted on top so it reads as the old
          // card being dealt off the deck to reveal the new one underneath.
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: <Widget>[?currentChild, ...previousChildren],
          ),
          child: ResilientMediaImage(
            key: ValueKey<String>('season-$resolvedSeason-$firstPoster'),
            imageUrl: posterChain.isEmpty ? null : posterChain.first,
            fallbackImageUrls: posterChain.skip(1).toList(),
            fallbackIcon: Icons.tv,
            borderRadius: MediaBrowsingMetrics.cardRadius,
            fallbackTitle: seriesName,
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSeasonResolved?.call(resolvedSeason);
    });

    final header = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [poster, const SizedBox(height: 16), meta],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              poster,
              const SizedBox(width: MediaBrowsingMetrics.pagePadding),
              Expanded(child: meta),
            ],
          );

    final upper = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 20),
        Wrap(
          spacing: MediaBrowsingMetrics.itemGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...primaryActions,
            SeasonPicker(
              seasons: seasons,
              selectedSeason: resolvedSeason,
              canMarkWatched: canMarkWatched && episodes.isNotEmpty,
              compact: compact,
              focusNode: seasonPickerFocusNode,
              episodeCountFor: episodeCountFor,
              fallbackPosterUrl: fallbackPosterUrl,
              onSeasonSelected: onSeasonSelected,
              onMarkSeason: (watched) =>
                  onMarkSeason(episodes, watched: watched),
            ),
            if (compact && richCast != null && richCast!.isNotEmpty)
              CastMemberRow(
                members: richCast,
                semanticLabel: l.seriesCast,
                compact: true,
                onShowAll: () => showAllCast(context, richCast!),
                allCastSemanticLabel: l.castShowAll,
              ),
          ],
        ),
      ],
    );

    final Widget episodeSection;
    if (episodes.isEmpty) {
      episodeSection = Align(
        alignment: Alignment.centerLeft,
        child: Text(emptyEpisodesLabel),
      );
    } else {
      final strip = EpisodeStrip(
        episodes: episodes,
        progressList: progressList,
        progressResolver: progressResolver,
        autofocusFirst: autofocusFirstEpisode,
        canMarkWatched: canMarkWatched,
        cardWidth: cardWidth,
        horizontal: !compact,
        onEpisodeSelected: onEpisodeSelected,
        onMarkEpisode: onMarkEpisode,
      );
      episodeSection = compact
          ? strip
          : SizedBox(height: stripHeight, child: strip);
    }

    if (compact) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MediaBrowsingMetrics.pagePadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [upper, const SizedBox(height: 12), episodeSection],
        ),
      );
      final bandHeight = MediaQuery.sizeOf(context).height * 0.5;
      return BackdropDetailHero(
        backdropUrl: backdropUrl,
        backdropHeight: bandHeight,
        contentAlignment: Alignment.topLeft,
        alwaysShowScrim: true,
        showBackgroundColorLayer: true,
        backgroundColor: bg,
        scrimColors: [bg.withValues(alpha: 0.2), bg.withValues(alpha: 0.8), bg],
        colorMatchReady: colorMatchReady,
        contentPadding: EdgeInsets.only(
          top: bandHeight * 0.44 + detailAppBarHeight(context),
          bottom: 24,
        ),
        content: content,
      );
    }

    final richCastList = richCast;
    final castSection = (richCastList != null && richCastList.isNotEmpty)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.seriesCast,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              CastRow(members: richCastList),
            ],
          )
        : null;

    return _SeriesScrollHost(
      backdropUrl: backdropUrl,
      bg: bg,
      colorMatchReady: colorMatchReady,
      onExitTop: onExitTop,
      upper: upper,
      episodeSection: episodeSection,
      castSection: castSection,
      scrollController: scrollController,
    );
  }
}

/// Owns the single [ScrollController] shared by the whole wide/TV Series
/// detail page: [RowScrollRegion] drives it (D-pad reveal/hop), and
/// [BackdropDetailHero] reads it for the backdrop parallax. Split out as its
/// own [StatefulWidget] because [SeriesDetailBody] is stateless and the
/// controller must survive rebuilds without a state to live in - and because
/// the hero (which paints the backdrop) is a sibling of the content it reads
/// the offset from, not an ancestor, so it can't discover the controller any
/// other way.
class _SeriesScrollHost extends StatefulWidget {
  const _SeriesScrollHost({
    required this.backdropUrl,
    required this.bg,
    required this.colorMatchReady,
    required this.onExitTop,
    required this.upper,
    required this.episodeSection,
    required this.castSection,
    this.scrollController,
  });

  final String? backdropUrl;
  final Color bg;
  final bool colorMatchReady;
  final VoidCallback onExitTop;
  final Widget upper;
  final Widget episodeSection;
  final Widget? castSection;

  /// External controller (see [SeriesDetailBody.scrollController]) so the
  /// caller can also snap to top from outside, e.g. the AppBar back button
  /// taking focus. Null creates and owns one internally.
  final ScrollController? scrollController;

  @override
  State<_SeriesScrollHost> createState() => _SeriesScrollHostState();
}

class _SeriesScrollHostState extends State<_SeriesScrollHost> {
  late final ScrollController _controller =
      widget.scrollController ?? ScrollController();
  bool get _ownsController => widget.scrollController == null;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// The upper block (poster/title/meta/buttons) is always the very top of
  /// the page, so any focus landing anywhere inside it means "show the top
  /// of the page," not just whichever widget happens to hold focus - a
  /// partial reveal would otherwise leave the poster/title still clipped
  /// above the viewport even once the play button is visible.
  void _scrollToTop() {
    if (!_controller.hasClients) return;
    unawaited(
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.bg;
    return BackdropDetailHero(
      backdropUrl: widget.backdropUrl,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      colorMatchReady: widget.colorMatchReady,
      scrollController: _controller,
      // No contentPadding here (unlike every other BackdropDetailHero call
      // site) - the top/bottom insets below live *inside* RowScrollRegion's
      // scrolled column instead, so they scroll away with everything else
      // and the hero/poster can run all the way up behind the transparent
      // AppBar rather than stopping at a fixed, never-scrolling gap.
      content: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MediaBrowsingMetrics.pagePadding,
        ),
        child: RowScrollRegion(
          controller: _controller,
          onExitTop: widget.onExitTop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: detailAppBarHeight(context) + 32),
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (hasFocus) {
                  if (hasFocus) _scrollToTop();
                },
                child: widget.upper,
              ),
              const SizedBox(height: 12),
              widget.episodeSection,
              if (widget.castSection != null) ...[
                const SizedBox(height: 24),
                widget.castSection!,
              ],
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
            ],
          ),
        ),
      ),
    );
  }
}
