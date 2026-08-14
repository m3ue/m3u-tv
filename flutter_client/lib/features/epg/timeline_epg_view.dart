import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/features/epg/program_recording_indicator.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/catchup_badge.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/epg_icon_pill.dart';
import 'package:m3u_tv/shared/recording_dot.dart';

typedef CatchupProgramSelect =
    void Function(Channel channel, EpgProgram program);
typedef EnsureEpg =
    void Function(
      List<Channel> channels, {
      DateTime? startDate,
      DateTime? endDate,
    });

const double _kChannelColW = 128;
const double _kTimeHeaderH = 28;
const double _kRowH = 60;
const double _kPxPerMin = 5; // 300 px per hour

/// Horizontal TV-guide style EPG with channels on Y and time on X.
///
/// Programs appear as proportionally-sized blocks that can be scrolled left/right
/// to move through the time window. The channel name column and time header stay
/// fixed while both axes scroll independently and remain synchronised.
class TimelineEpgView extends StatefulWidget {
  const TimelineEpgView({
    super.key,
    required this.channels,
    required this.epgService,
    required this.onChannelSelect,
    required this.channelColumnFocusNode,
    required this.onChannelColumnEdge,
    required this.dayControlsFocusNode,
    required this.onDayControlsEdge,
    this.onCatchupProgramSelect,
    this.onEnsureEpg,
    this.onChannelLongPress,
    this.onChannelColumnLongPress,
    this.recordingChannelIds = const <int>{},
    this.recordingStateFor = _noRecordingState,
    this.windowHours = 24,
    this.futureDays = 7,
    this.clock = DateTime.now,
    this.epgStartView = EpgStartView.currentTime,
  });

  final List<Channel> channels;
  final EpgService epgService;
  final void Function(Channel) onChannelSelect;
  final CatchupProgramSelect? onCatchupProgramSelect;

  /// The channel column's own focus scope, so the caller (`LiveTvScreen`)
  /// can move focus there directly (e.g. from the Back key) instead of only
  /// via spatial traversal from the program grid.
  final FocusScopeNode channelColumnFocusNode;

  /// Fired when d-pad navigation hits the channel column's own edge —
  /// mirrors the program grid's `onEdge` (left activates the nav
  /// strip/sidebar, right returns focus to the program grid, up moves to
  /// the day-nav header).
  final ValueChanged<TraversalDirection> onChannelColumnEdge;

  /// The day-nav header's (previous/date/now/next) own focus scope, so the
  /// caller can move focus there directly from the Channels column (up) the
  /// same way [channelColumnFocusNode] is targeted from the Back key —
  /// plain spatial traversal can't cross into a sibling [FocusScopeNode]
  /// automatically, so this needs to be reachable programmatically.
  final FocusScopeNode dayControlsFocusNode;

  /// Fired when d-pad navigation hits the day-nav header's own edge — left
  /// activates the nav strip/sidebar, right returns focus to the program
  /// grid, down moves to the Channels column.
  final ValueChanged<TraversalDirection> onDayControlsEdge;

  /// Requests EPG data for a channel be fetched (lazily, debounced) if not
  /// already fresh. Called per-row as the visible timeline builds.
  final EnsureEpg? onEnsureEpg;

  /// Opens the channel's context menu (favorite/record) for the pressed
  /// block — same long-press action available in the list/grid views, for
  /// parity. The program passed is whichever block was pressed (past,
  /// current, or future); the caller decides whether it's still schedulable.
  final CatchupProgramSelect? onChannelLongPress;

  /// Same context menu as [onChannelLongPress], but for long-pressing the
  /// channel column itself, which has no associated program block.
  final ValueChanged<Channel>? onChannelColumnLongPress;

  final Set<int> recordingChannelIds;

  /// Resolves which per-programme recording indicator (if any) should be
  /// drawn on a given EPG block. Defaults to [EpgRecordingState.none] for
  /// every block, so the widget renders identically to the pre-#185
  /// version when no resolver is supplied. The caller (typically the
  /// EPG screen with the matching-logic index in scope) is responsible
  /// for mapping a recording to each programme.
  ///
  /// Takes the [Channel] as well as the [EpgProgram] because the two carry
  /// different notions of "channel id": [EpgProgram.channelId] is the EPG
  /// (tvg) identifier, whereas a recording references the channel's database
  /// id. Only the row's [Channel] has the latter, so the resolver needs both
  /// to line a recording up with a block.
  final EpgRecordingState Function(Channel channel, EpgProgram program)
  recordingStateFor;

  static EpgRecordingState _noRecordingState(Channel _, EpgProgram _) =>
      EpgRecordingState.none;

  /// How many hours the selected-day window spans (default 24).
  final int windowHours;
  final int futureDays;
  final Clock clock;
  final EpgStartView epgStartView;

  @override
  State<TimelineEpgView> createState() => _TimelineEpgViewState();
}

class _TimelineEpgViewState extends State<TimelineEpgView> {
  late final ScrollController _leftVCtrl;
  late final ScrollController _rightVCtrl;
  late final ScrollController _headerHCtrl;
  late List<ScrollController> _rowHCtrls;
  bool _vSyncing = false;
  bool _hSyncing = false;
  late DateTime _selectedDate;
  late DateTime _windowStart;
  late DateTime _windowEnd;
  late double _totalW;
  late double _nowOffset;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.clock());
    _initWindow();
    _leftVCtrl = ScrollController();
    _rightVCtrl = ScrollController();
    _headerHCtrl = ScrollController(initialScrollOffset: _nowOffset);
    _rowHCtrls = _makeRowCtrls(widget.channels.length);
    _leftVCtrl.addListener(_onLeftV);
    _rightVCtrl.addListener(_onRightV);
    WidgetsBinding.instance.addPostFrameCallback(_scrollToStart);
  }

  void _initWindow() {
    _windowStart = _selectedDate;
    _windowEnd = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      widget.windowHours,
    );
    _totalW = _windowEnd.difference(_windowStart).inMinutes * _kPxPerMin;
    _nowOffset = _computeStartOffset();
  }

  double _computeStartOffset() {
    final now = widget.clock();
    final anchor = switch (widget.epgStartView) {
      EpgStartView.primeTime => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        20,
      ),
      EpgStartView.currentTime => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        now.hour,
        now.minute,
      ),
    };
    final offset = anchor.difference(_windowStart).inMinutes * _kPxPerMin;
    return math.max(0, offset - 80.0).toDouble();
  }

  // Rows are built lazily by ListView.builder as they scroll into view, so a
  // row's ScrollController may attach long after the scroll-to-start jump
  // below has already run. Baking the target into initialScrollOffset means
  // a late-attaching row still lands on the right offset instead of 12am.
  List<ScrollController> _makeRowCtrls(int count) => List.generate(
    count,
    (_) => ScrollController(initialScrollOffset: _nowOffset),
  );

  void _scrollToStart(_) {
    if (!mounted) return;
    for (final c in [_headerHCtrl, ..._rowHCtrls]) {
      if (c.hasClients) {
        c.jumpTo(_nowOffset.clamp(0.0, c.position.maxScrollExtent));
      }
    }
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _offsetDate(DateTime value, int days) =>
      DateTime(value.year, value.month, value.day + days);

  int get _maxCatchupDays => widget.channels
      .map(
        (channel) => EpgService.effectiveCatchupRetentionDays(
          channel.catchupSupported,
          channel.catchupDays,
        ),
      )
      .fold(0, math.max);

  void _selectDate(DateTime date) {
    final today = _dateOnly(widget.clock());
    final earliest = _offsetDate(today, -_maxCatchupDays);
    final latest = _offsetDate(today, widget.futureDays);
    final requested = _dateOnly(date);
    final selected = requested.isBefore(earliest)
        ? earliest
        : requested.isAfter(latest)
        ? latest
        : requested;
    if (selected != _selectedDate) {
      setState(() {
        _selectedDate = selected;
        _initWindow();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback(_scrollToStart);
  }

  void _onLeftV() {
    if (_vSyncing || !_rightVCtrl.hasClients) return;
    _vSyncing = true;
    _rightVCtrl.jumpTo(_leftVCtrl.offset);
    _vSyncing = false;
  }

  void _onRightV() {
    if (_vSyncing || !_leftVCtrl.hasClients) return;
    _vSyncing = true;
    _leftVCtrl.jumpTo(_rightVCtrl.offset);
    _vSyncing = false;
  }

  void _syncH(double offset) {
    if (_hSyncing) return;
    _hSyncing = true;
    _jump(_headerHCtrl, offset);
    for (final c in _rowHCtrls) {
      _jump(c, offset);
    }
    _hSyncing = false;
  }

  void _jump(ScrollController ctrl, double offset) {
    if (!ctrl.hasClients) return;
    final clamped = offset.clamp(0.0, ctrl.position.maxScrollExtent);
    if ((ctrl.offset - clamped).abs() > 0.5) ctrl.jumpTo(clamped);
  }

  @override
  void didUpdateWidget(TimelineEpgView old) {
    super.didUpdateWidget(old);
    if (widget.channels.length != old.channels.length) {
      for (final c in _rowHCtrls) {
        c.dispose();
      }
      _rowHCtrls = _makeRowCtrls(widget.channels.length);
    }
    if (widget.epgStartView != old.epgStartView) {
      _initWindow();
      WidgetsBinding.instance.addPostFrameCallback(_scrollToStart);
    }
    final today = _dateOnly(widget.clock());
    final earliest = _offsetDate(today, -_maxCatchupDays);
    final latest = _offsetDate(today, widget.futureDays);
    if (_selectedDate.isBefore(earliest) || _selectedDate.isAfter(latest)) {
      _selectedDate = _selectedDate.isBefore(earliest) ? earliest : latest;
      _initWindow();
    }
  }

  @override
  void dispose() {
    _leftVCtrl.removeListener(_onLeftV);
    _rightVCtrl.removeListener(_onRightV);
    _leftVCtrl.dispose();
    _rightVCtrl.dispose();
    _headerHCtrl.dispose();
    for (final c in _rowHCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = widget.clock();

    return Column(
      children: [
        // Its own FocusScope (like the Channels column) so LiveTvScreen can
        // jump straight here from the Channels column's up-edge — a plain
        // FocusScopeNode boundary blocks Flutter's normal directional
        // search from crossing into a sibling scope on its own, so both
        // hops (here and the Channels column) need to be explicit.
        FocusScope(
          node: widget.dayControlsFocusNode,
          child: DpadRegion(
            memoryKey: 'live-tv/epg-daycontrols',
            horizontalEdge: DpadEdgeBehavior.stop,
            verticalEdge: DpadEdgeBehavior.stop,
            onEdge: widget.onDayControlsEdge,
            child: _DayControls(
              selectedDate: _selectedDate,
              canGoPrevious: _selectedDate.isAfter(
                _offsetDate(now, -_maxCatchupDays),
              ),
              canGoNext: _selectedDate.isBefore(
                _offsetDate(now, widget.futureDays),
              ),
              onPrevious: () => _selectDate(_offsetDate(_selectedDate, -1)),
              onNow: () => _selectDate(_dateOnly(widget.clock())),
              onNext: () => _selectDate(_offsetDate(_selectedDate, 1)),
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              // ── Fixed left channel column ──────────────────────────────────────
              SizedBox(
                width: _kChannelColW,
                child: Column(
                  children: [
                    // Corner cell
                    Container(
                      height: _kTimeHeaderH,
                      color: colorScheme.surfaceContainerHighest,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppLocalizations.of(context).epgChannels,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    // Channel name/logo list (synced vertically with program rows)
                    Expanded(
                      // DpadRegion must be the OUTER widget here, not the
                      // FocusScope: `DpadRegion.ofNode` resolves a node's
                      // region from that node's own BuildContext, walking
                      // upward. With FocusScope outside, its FocusScopeNode
                      // (which defaults to canRequestFocus: true, unlike the
                      // package's own region markers) would resolve to
                      // whatever DpadRegion encloses this whole EPG view
                      // (live-tv/epg) rather than this nested one — making
                      // it a spurious spatial-navigation candidate that can
                      // steal focus from unrelated controls elsewhere in
                      // that outer region (e.g. the day-navigation header).
                      // Nesting FocusScope inside DpadRegion instead makes
                      // the scope node belong to *this* region, where it's
                      // correctly excluded from being its own candidate.
                      child: DpadRegion(
                        memoryKey: 'live-tv/epg-channels',
                        horizontalEdge: DpadEdgeBehavior.stop,
                        verticalEdge: DpadEdgeBehavior.stop,
                        onEdge: widget.onChannelColumnEdge,
                        child: FocusScope(
                          node: widget.channelColumnFocusNode,
                          child: ListView.builder(
                            controller: _leftVCtrl,
                            itemCount: widget.channels.length,
                            itemExtent: _kRowH,
                            itemBuilder: (_, i) => _ChannelCell(
                              channel: widget.channels[i],
                              isRecording: widget.recordingChannelIds.contains(
                                widget.channels[i].id,
                              ),
                              // The Channels column is the default landing
                              // spot for the EPG view (not the day-nav
                              // header or a program block), so it's the
                              // only autofocus target in this widget.
                              autofocus: i == 0,
                              onTap: () =>
                                  widget.onChannelSelect(widget.channels[i]),
                              onLongTap: widget.onChannelColumnLongPress == null
                                  ? null
                                  : () => widget.onChannelColumnLongPress!(
                                      widget.channels[i],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Thin vertical divider
              Container(width: 1, color: colorScheme.outlineVariant),

              // ── Right: time header + scrollable program grid ───────────────────
              Expanded(
                child: Column(
                  children: [
                    // Time axis header
                    SizedBox(
                      height: _kTimeHeaderH,
                      child: AnimatedBuilder(
                        animation: _headerHCtrl,
                        builder: (context, _) {
                          final hOffset = _headerHCtrl.hasClients
                              ? _headerHCtrl.offset
                              : 0.0;
                          final nowX =
                              now.difference(_windowStart).inMinutes *
                                  _kPxPerMin -
                              hOffset;

                          return Stack(
                            children: [
                              SingleChildScrollView(
                                controller: _headerHCtrl,
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: _TimeHeader(
                                  windowStart: _windowStart,
                                  windowEnd: _windowEnd,
                                  pixelsPerMinute: _kPxPerMin,
                                  height: _kTimeHeaderH,
                                ),
                              ),
                              if (nowX >= 0 && nowX <= _totalW)
                                Positioned(
                                  left: nowX,
                                  top: 4,
                                  bottom: 0,
                                  width: 2,
                                  child: Container(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Program rows
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _rightVCtrl,
                            itemCount: widget.channels.length,
                            itemExtent: _kRowH,
                            itemBuilder: (_, i) {
                              final channel = widget.channels[i];
                              final catchupRetentionDays =
                                  EpgService.effectiveCatchupRetentionDays(
                                    channel.catchupSupported,
                                    channel.catchupDays,
                                  );
                              widget.onEnsureEpg?.call(
                                [channel],
                                startDate: _selectedDate,
                                endDate: _selectedDate,
                              );
                              final programs = widget.epgService
                                  .programsForChannel(
                                    channel,
                                  );
                              return NotificationListener<
                                ScrollUpdateNotification
                              >(
                                onNotification: (n) {
                                  _syncH(n.metrics.pixels);
                                  return false;
                                },
                                child: SingleChildScrollView(
                                  key: ValueKey(
                                    'timeline-row-scroll-${channel.id}',
                                  ),
                                  controller: i < _rowHCtrls.length
                                      ? _rowHCtrls[i]
                                      : null,
                                  scrollDirection: Axis.horizontal,
                                  child: _ProgramsRow(
                                    programs: programs,
                                    windowStart: _windowStart,
                                    windowEnd: _windowEnd,
                                    pixelsPerMinute: _kPxPerMin,
                                    totalWidth: _totalW,
                                    rowHeight: _kRowH,
                                    catchupRetentionDays: catchupRetentionDays,
                                    now: now,
                                    // Curry the row's channel in: _ProgramsRow
                                    // only sees programmes, but resolving a
                                    // recording needs the channel's database
                                    // id, which lives on the Channel.
                                    recordingStateFor: (program) => widget
                                        .recordingStateFor(channel, program),
                                    onTap: (program) {
                                      final canReplay = EpgService.canReplay(
                                        catchupRetentionDays,
                                        program,
                                        widget.clock(),
                                      );
                                      if (canReplay &&
                                          widget.onCatchupProgramSelect !=
                                              null) {
                                        widget.onCatchupProgramSelect!(
                                          channel,
                                          program,
                                        );
                                        return;
                                      }
                                      widget.onChannelSelect(channel);
                                    },
                                    onLongPress:
                                        widget.onChannelLongPress == null
                                        ? null
                                        : (program) =>
                                              widget.onChannelLongPress!(
                                                channel,
                                                program,
                                              ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // "Now" vertical line over the program grid
                          AnimatedBuilder(
                            animation: _headerHCtrl,
                            builder: (context, _) {
                              if (!_headerHCtrl.hasClients) {
                                return const SizedBox.shrink();
                              }
                              final nowX =
                                  now.difference(_windowStart).inMinutes *
                                      _kPxPerMin -
                                  _headerHCtrl.offset;
                              if (nowX < 0 || nowX > _totalW) {
                                return const SizedBox.shrink();
                              }
                              return Positioned(
                                left: nowX,
                                top: 0,
                                bottom: 0,
                                width: 2,
                                child: IgnorePointer(
                                  child: Container(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DayControls extends StatelessWidget {
  const _DayControls({
    required this.selectedDate,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNow,
    required this.onNext,
  });

  final DateTime selectedDate;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNow;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // Left-aligned (Row's default) so this cluster sits directly above
      // the Channels column (matching its horizontal position) instead of
      // floating centered across the whole EPG width.
      //
      // crossAxisAlignment.stretch gives every child (icon buttons, the
      // "now" pill, the date text) the exact same focus-node rect height.
      // Without it, the "now" pill's naturally-shorter text-driven height
      // sits entirely inside the taller icon buttons' rect on the vertical
      // axis, which the dpad package's edge-based "is this candidate below
      // me" check (see DpadTraversalPolicy._isCandidate) reads as still
      // being a same-row neighbor even after Down should have left the
      // row — so pressing Down from "now" would land on "previous"/"next"
      // instead of dropping to the Channels column.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DpadInkWell(
            key: const ValueKey('timeline-previous-day'),
            onTap: canGoPrevious ? onPrevious : null,
            // Not the visible landing focus (the Channels column autofocus,
            // built after this, wins that) — this just seeds the
            // day-controls/program-grid region's own focus history, so
            // returning here from the Channels column (see
            // LiveTvScreen._handleChannelColumnEdge) has a real fallback
            // target instead of parking on an empty scope.
            autofocus: canGoPrevious,
            enabled: canGoPrevious,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Center(
                child: Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: canGoPrevious
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(alpha: 0.35),
                  semanticLabel: l10n.epgPreviousDay,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 116,
            child: Center(
              child: Text(
                DateFormat.yMMMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(selectedDate),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          const SizedBox(width: 6),
          DpadInkWell(
            key: const ValueKey('timeline-now'),
            onTap: onNow,
            autofocus: !canGoPrevious,
            borderRadius: BorderRadius.circular(50),
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  l10n.epgNow,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          DpadInkWell(
            key: const ValueKey('timeline-next-day'),
            onTap: canGoNext ? onNext : null,
            enabled: canGoNext,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Center(
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: canGoNext
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(alpha: 0.35),
                  semanticLabel: l10n.epgNextDay,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    this.isRecording = false,
    this.onTap,
    this.onLongTap,
    this.autofocus = false,
  });
  final Channel channel;
  final bool isRecording;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      onTap: onTap,
      onLongTap: onLongTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.zero,
      child: Container(
        height: _kRowH,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
              Image.network(
                channel.logoUrl!,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.tv, size: 28),
              )
            else
              const Icon(Icons.tv, size: 28),
            const SizedBox(width: 6),
            if (isRecording) ...[
              RecordingDot(color: colorScheme.error),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                channel.name,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (channel.catchupSupported) ...[
              const SizedBox(width: 4),
              CatchupBadge(days: channel.catchupDays),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.windowStart,
    required this.windowEnd,
    required this.pixelsPerMinute,
    required this.height,
  });

  final DateTime windowStart;
  final DateTime windowEnd;
  final double pixelsPerMinute;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalW =
        windowEnd.difference(windowStart).inMinutes * pixelsPerMinute;

    // Snap to the last 30-min boundary at or before windowStart
    var slot = DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day,
      windowStart.hour,
      (windowStart.minute ~/ 30) * 30,
    );

    final slots = <Widget>[];
    while (slot.isBefore(windowEnd)) {
      final x = slot.difference(windowStart).inMinutes * pixelsPerMinute;
      if (x >= -80 && x < totalW + 80) {
        slots.add(
          Positioned(
            left: x,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1,
                  height: height * 0.55,
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  _label(slot),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      slot = slot.add(const Duration(minutes: 30));
    }

    return Container(
      width: totalW,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      child: Stack(children: slots),
    );
  }

  String _label(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final suffix = t.hour < 12 ? 'AM' : 'PM';
    return t.minute == 0
        ? '$h $suffix'
        : '$h:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _ProgramsRow extends StatelessWidget {
  const _ProgramsRow({
    required this.programs,
    required this.windowStart,
    required this.windowEnd,
    required this.pixelsPerMinute,
    required this.totalWidth,
    required this.rowHeight,
    required this.onTap,
    required this.catchupRetentionDays,
    required this.now,
    this.onLongPress,
    this.recordingStateFor = _noRecordingState,
  });

  final List<EpgProgram> programs;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double pixelsPerMinute;
  final double totalWidth;
  final double rowHeight;
  final void Function(EpgProgram program) onTap;
  final int catchupRetentionDays;
  final DateTime now;

  /// Opens the favorite/record context menu for the pressed block.
  final void Function(EpgProgram program)? onLongPress;

  /// Resolves the per-programme recording indicator for a block. Defaults
  /// to [EpgRecordingState.none], which renders no badge and is visually
  /// identical to the pre-#185 layout.
  final EpgRecordingState Function(EpgProgram program) recordingStateFor;

  static EpgRecordingState _noRecordingState(EpgProgram _) =>
      EpgRecordingState.none;

  bool showCatchupIcon(EpgProgram program) =>
      EpgService.canReplay(catchupRetentionDays, program, now);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final visible = programs
        .where((p) => p.end.isAfter(windowStart) && p.start.isBefore(windowEnd))
        .toList();

    final blocks = <Widget>[];
    for (final p in visible) {
      final isCurrent = !now.isBefore(p.start) && now.isBefore(p.end);
      final clampedStart = p.start.isBefore(windowStart)
          ? windowStart
          : p.start;
      final clampedEnd = p.end.isAfter(windowEnd) ? windowEnd : p.end;
      final left =
          clampedStart.difference(windowStart).inMinutes * pixelsPerMinute;
      final width =
          clampedEnd.difference(clampedStart).inMinutes * pixelsPerMinute;

      if (width < 4) continue;

      final bgColor = isCurrent
          ? colorScheme.primaryContainer
          : colorScheme.secondaryContainer;
      final fgColor = isCurrent
          ? colorScheme.onPrimaryContainer
          : colorScheme.onSecondaryContainer;
      final borderColor = isCurrent
          ? colorScheme.primary.withValues(alpha: 0.6)
          : colorScheme.outline.withValues(alpha: 0.25);
      final recordingState = recordingStateFor(p);
      final hasCatchup = showCatchupIcon(p);
      final hasRecording = recordingState != EpgRecordingState.none;
      blocks.add(
        Positioned(
          left: left + 1,
          top: isCurrent ? 2 : 4,
          height: rowHeight - (isCurrent ? 4 : 8),
          width: width - 2,
          child: DpadInkWell(
            key: ValueKey(
              'timeline-program-${p.channelId}-${p.start.toIso8601String()}',
            ),
            onTap: () => onTap(p),
            onLongTap: onLongPress == null ? null : () => onLongPress!(p),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: hasRecording ? 18 : 0,
                      right: hasCatchup ? 22 : 0,
                    ),
                    child: Text(
                      p.displayTitle,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fgColor,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasRecording)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: ProgramRecordingIndicator(state: recordingState),
                    ),
                  if (hasCatchup)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: EpgIconPill(
                        color: colorScheme.tertiaryContainer,
                        borderColor: colorScheme.tertiary.withValues(
                          alpha: 0.55,
                        ),
                        child: Icon(
                          Icons.replay_rounded,
                          size: 10,
                          color: colorScheme.onTertiaryContainer,
                          semanticLabel: l10n.catchupProgramReplayable,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (blocks.isEmpty) {
      return SizedBox(
        width: totalWidth,
        height: rowHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              l10n.epgNoData,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: totalWidth,
      height: rowHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
          ...blocks,
        ],
      ),
    );
  }
}
