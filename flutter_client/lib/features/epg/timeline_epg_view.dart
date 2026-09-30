import 'dart:async';
import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:m3u_tv/features/epg/epg_guide_navigation.dart';
import 'package:m3u_tv/features/epg/epg_program_details.dart';
import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/features/epg/program_recording_indicator.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart'
    show ChannelColumnLayout, EpgStartView, OptimizeFor;
import 'package:m3u_tv/shared/cached_media_thumbnail.dart';
import 'package:m3u_tv/shared/catchup_badge.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/epg_icon_pill.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/recording_dot.dart';

typedef CatchupProgramSelect =
    void Function(Channel channel, EpgProgram program);
typedef EnsureEpg =
    void Function(
      List<Channel> channels, {
      DateTime? startDate,
      DateTime? endDate,
    });

// When a row builds, also request EPG for this many channels past it so a
// downward scroll lands on already-loaded data instead of waiting on a lazy
// fetch. [onEnsureEpg] is debounced and de-duped, so the widened slice just
// coalesces into one batched request. Reduced in speed mode to cut bandwidth.
const int _kEpgPrefetchAheadQuality = 12;
const int _kEpgPrefetchAheadSpeed = 6;

// Rows only build the programmes within this many minutes of the visible
// time range; scrolling past that margin rebuilds them around the new view.
const double _kBuildSpanMarginMinutes = 180;

// Lead-in before the start anchor ("now" or prime time) on first show.
const int _kStartLeadInMinutes = 16;

// The preview panel only shows when the guide has at least this much room,
// so a small desktop window keeps a usable number of rows.
const double _kMinHeightForPreview = 560;
const double _kMinWidthForPreview = 720;

const Duration _kClockTick = Duration(seconds: 30);

/// TV-guide style EPG: channels down the side, time across the top, the
/// programme under the cursor previewed above (TV/desktop).
///
/// Built D-pad first. The whole programme grid is a single focus node that
/// moves a logical cursor: left/right step through a row's programmes (left
/// of the first one lands on the channel, right of the last one moves to
/// the next day), up/down keep the same time column, CH+/CH- and PgUp/PgDn
/// page through channels. OK activates (play live, replay catchup, or open
/// options for an upcoming programme) and a long OK opens the channel's
/// options. Touch/mouse still scroll and tap; on touch devices
/// ([tapOpensDetails]) a tap opens a details sheet instead, since there is
/// no focus preview to read.
///
/// Layout: one horizontal scroll view holds the time ruler and a single
/// vertical list of rows; each row's channel cell is pinned against the
/// horizontal offset, so both axes scroll natively with nothing to sync.
class TimelineEpgView extends StatefulWidget {
  const TimelineEpgView({
    super.key,
    required this.channels,
    required this.epgService,
    required this.onChannelSelect,
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
    this.channelColumnLayout = ChannelColumnLayout.logoOnly,
    this.showPreview = false,
    this.tapOpensDetails = false,
    this.autofocus = true,
    this.onCursorMove,
  });

  final List<Channel> channels;
  final EpgService epgService;
  final void Function(Channel) onChannelSelect;
  final CatchupProgramSelect? onCatchupProgramSelect;

  /// Requests EPG data for a channel be fetched (lazily, debounced) if not
  /// already fresh. Called per-row as the visible timeline builds.
  final EnsureEpg? onEnsureEpg;

  /// Opens the channel's context menu (favorite/record) for a programme -
  /// long OK / long-press on a programme, and plain OK on an upcoming one.
  /// The caller decides whether the programme is still schedulable.
  final CatchupProgramSelect? onChannelLongPress;

  /// Same context menu as [onChannelLongPress], for the channel itself (no
  /// programme): long OK / long-press on the channel cell.
  final ValueChanged<Channel>? onChannelColumnLongPress;

  final Set<int> recordingChannelIds;

  /// Resolves which per-programme recording indicator (if any) to draw.
  /// Takes the [Channel] as well as the [EpgProgram] because a recording
  /// references the channel's database id, which only the row's [Channel]
  /// carries ([EpgProgram.channelId] is the tvg id).
  final EpgRecordingState Function(Channel channel, EpgProgram program)
  recordingStateFor;

  static EpgRecordingState _noRecordingState(Channel _, EpgProgram _) =>
      EpgRecordingState.none;

  /// How many hours the selected-day window spans (default 24).
  final int windowHours;
  final int futureDays;
  final Clock clock;
  final EpgStartView epgStartView;

  /// What each row of the pinned channel column shows for a channel.
  final ChannelColumnLayout channelColumnLayout;

  /// Shows the focused programme's artwork/details panel above the grid
  /// (TV/desktop), when there's enough height for it.
  final bool showPreview;

  /// Tapping a programme opens its details sheet instead of activating it
  /// (touch devices, which have no focus preview).
  final bool tapOpensDetails;

  /// Whether the programme grid takes focus when the view first builds.
  final bool autofocus;

  /// Called when a D-pad press moves the guide cursor. The grid is a single
  /// focus node, so cursor moves don't change focus and the app-wide
  /// focus-change navigation sound would otherwise stay silent here.
  final VoidCallback? onCursorMove;

  @override
  State<TimelineEpgView> createState() => TimelineEpgViewState();
}

@immutable
class _GuideMetrics {
  const _GuideMetrics({
    required this.compact,
    required this.rowHeight,
    required this.rulerHeight,
    required this.channelColumnWidth,
    required this.pxPerMinute,
    required this.viewportWidth,
  });

  final bool compact;
  final double rowHeight;
  final double rulerHeight;
  final double channelColumnWidth;
  final double pxPerMinute;
  final double viewportWidth;

  double get programViewportWidth =>
      math.max(0, viewportWidth - channelColumnWidth);
}

@immutable
class _GuideCursor {
  const _GuideCursor({
    required this.row,
    this.program,
    this.onChannel = true,
    this.focused = false,
  });

  final int row;

  /// Null on the channel cell, or on a row with no programme data.
  final EpgProgram? program;
  final bool onChannel;
  final bool focused;

  bool isOn(EpgProgram candidate) {
    final current = program;
    return !onChannel &&
        current != null &&
        current.start == candidate.start &&
        current.channelId == candidate.channelId;
  }

  _GuideCursor copyWith({
    int? row,
    EpgProgram? program,
    bool clearProgram = false,
    bool? onChannel,
    bool? focused,
  }) => _GuideCursor(
    row: row ?? this.row,
    program: clearProgram ? null : program ?? this.program,
    onChannel: onChannel ?? this.onChannel,
    focused: focused ?? this.focused,
  );

  @override
  bool operator ==(Object other) =>
      other is _GuideCursor &&
      other.row == row &&
      other.onChannel == onChannel &&
      other.focused == focused &&
      other.program?.start == program?.start &&
      other.program?.channelId == program?.channelId;

  @override
  int get hashCode =>
      Object.hash(row, onChannel, focused, program?.start, program?.channelId);
}

/// Minutes from the window start that rows currently build programmes for.
@immutable
class _MinuteSpan {
  const _MinuteSpan(this.start, this.end);

  final double start;
  final double end;

  bool overlaps(double from, double to) => to > start && from < end;

  @override
  bool operator ==(Object other) =>
      other is _MinuteSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class TimelineEpgViewState extends State<TimelineEpgView> {
  final FocusNode _gridFocusNode = FocusNode(debugLabel: 'epg-guide');
  final ScrollController _vCtrl = ScrollController();
  // Created on the first layout, once the start offset (which depends on
  // the measured width) is known, so the first frame already shows "now"
  // instead of flashing midnight.
  ScrollController? _hCtrlOrNull;
  ScrollController get _hCtrl => _hCtrlOrNull!;

  final ValueNotifier<_GuideCursor> _cursor = ValueNotifier(
    const _GuideCursor(row: 0),
  );
  final ValueNotifier<_MinuteSpan> _buildSpan = ValueNotifier(
    const _MinuteSpan(0, 0),
  );

  late DateTime _selectedDate;
  late DateTime _windowStart;
  late DateTime _windowEnd;
  _GuideMetrics? _metrics;
  late DateTime _now;

  /// The time up/down moves stay aligned with (see
  /// [EpgGuideNavigation.anchorFor]); null until the first horizontal move.
  DateTime? _anchor;

  Timer? _clockTimer;
  bool _revalidateScheduled = false;

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    _selectedDate = _dateOnly(_now);
    _initWindow();
    _clockTimer = Timer.periodic(_kClockTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TimelineEpgView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final today = _dateOnly(widget.clock());
    final earliest = _offsetDate(today, -_maxCatchupDays);
    final latest = _offsetDate(today, widget.futureDays);
    if (_selectedDate.isBefore(earliest) || _selectedDate.isAfter(latest)) {
      _selectedDate = _selectedDate.isBefore(earliest) ? earliest : latest;
      _initWindow();
    }
    if (widget.epgStartView != oldWidget.epgStartView) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
    }
    if (!identical(widget.channels, oldWidget.channels)) {
      // Clamp now (not just in the post-frame revalidate) so an OK press
      // before the next frame can't index past a shrunken channel list.
      final cursor = _cursor.value;
      final lastRow = math.max(0, widget.channels.length - 1);
      if (cursor.row > lastRow) _setCursor(cursor.copyWith(row: lastRow));
      _scheduleRevalidate();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _hCtrlOrNull?.removeListener(_onHorizontalScroll);
    _hCtrlOrNull?.dispose();
    _vCtrl.dispose();
    _gridFocusNode.dispose();
    _cursor.dispose();
    _buildSpan.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Public API (LiveTvScreen)
  // ---------------------------------------------------------------------------

  /// Focuses the guide with the cursor on the current row's channel cell -
  /// the landing spot when entering from the category strip.
  void focusChannelColumn() {
    _setCursor(_cursor.value.copyWith(onChannel: true));
    _gridFocusNode.requestFocus();
  }

  /// Back while on a programme returns the cursor to its channel cell and
  /// consumes the press; otherwise lets the shell handle it.
  bool handleBack() {
    final cursor = _cursor.value;
    if (!_gridFocusNode.hasFocus || cursor.onChannel) return false;
    _setCursor(cursor.copyWith(onChannel: true));
    return true;
  }

  /// Back to the first channel. Called by LiveTvScreen when the selected
  /// group changes, since the list otherwise keeps the previous group's
  /// scroll offset and cursor row.
  void resetVerticalScroll() {
    if (_vCtrl.hasClients) _vCtrl.jumpTo(0);
    _setCursor(_cursor.value.copyWith(row: 0));
    _scheduleRevalidate();
  }

  // ---------------------------------------------------------------------------
  // Window / dates
  // ---------------------------------------------------------------------------

  void _initWindow() {
    _windowStart = _selectedDate;
    _windowEnd = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      widget.windowHours,
    );
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

  bool get _canGoPrevious => _selectedDate.isAfter(
    _offsetDate(_dateOnly(widget.clock()), -_maxCatchupDays),
  );

  bool get _canGoNext => _selectedDate.isBefore(
    _offsetDate(_dateOnly(widget.clock()), widget.futureDays),
  );

  void _selectDate(DateTime date, {bool scrollToDayStart = false}) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollToDayStart) {
        _jumpHorizontal(0);
      } else {
        _scrollToStart();
      }
      _revalidateCursor();
    });
  }

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  _GuideMetrics _computeMetrics(BuildContext context, double width) {
    final scale = FontSizeScope.scaleOf(context);
    final compact = width < 600;
    final channelColumnWidth =
        switch (widget.channelColumnLayout) {
          ChannelColumnLayout.logoOnly => compact ? 72.0 : 132.0,
          ChannelColumnLayout.logoAndTitle => compact ? 96.0 : 248.0,
          ChannelColumnLayout.titleOnly => compact ? 104.0 : 208.0,
        } *
        scale;
    // Aim for roughly 3 hours across on wide screens and 90 minutes on a
    // phone, so a half-hour programme stays wide enough to read.
    final programWidth = math.max<double>(1, width - channelColumnWidth);
    final pxPerMinute = (programWidth / (compact ? 90 : 180)).clamp(4.0, 8.0);
    return _GuideMetrics(
      compact: compact,
      rowHeight: (compact ? 64.0 : 76.0) * scale,
      rulerHeight: (compact ? 32.0 : 40.0) * scale,
      channelColumnWidth: channelColumnWidth,
      pxPerMinute: pxPerMinute.roundToDouble(),
      viewportWidth: width,
    );
  }

  double _minutesFromStart(DateTime time) =>
      time.difference(_windowStart).inSeconds / 60;

  double _totalWidth(_GuideMetrics m) =>
      _windowEnd.difference(_windowStart).inMinutes * m.pxPerMinute;

  double _startOffsetFor(_GuideMetrics m) {
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
    final minutes = _minutesFromStart(anchor) - _kStartLeadInMinutes;
    return math.max(0, minutes * m.pxPerMinute);
  }

  double get _hOffset {
    final ctrl = _hCtrlOrNull;
    if (ctrl == null) return 0;
    return ctrl.hasClients ? ctrl.offset : ctrl.initialScrollOffset;
  }

  (DateTime, DateTime)? _visibleTimeRange([double? offset]) {
    final m = _metrics;
    if (m == null) return null;
    final startMinutes = (offset ?? _hOffset) / m.pxPerMinute;
    final endMinutes = startMinutes + m.programViewportWidth / m.pxPerMinute;
    return (
      _windowStart.add(Duration(seconds: (startMinutes * 60).round())),
      _windowStart.add(Duration(seconds: (endMinutes * 60).round())),
    );
  }

  _MinuteSpan _spanAround(double offset, _GuideMetrics m) {
    final start = offset / m.pxPerMinute;
    final end = start + m.programViewportWidth / m.pxPerMinute;
    return _MinuteSpan(
      start - _kBuildSpanMarginMinutes,
      end + _kBuildSpanMarginMinutes,
    );
  }

  void _applyMetrics(_GuideMetrics m) {
    final previous = _metrics;
    _metrics = m;
    if (_hCtrlOrNull == null) {
      final offset = _startOffsetFor(m);
      _hCtrlOrNull = ScrollController(initialScrollOffset: offset)
        ..addListener(_onHorizontalScroll);
      _buildSpan.value = _spanAround(offset, m);
      return;
    }
    if (previous != null && previous.pxPerMinute != m.pxPerMinute) {
      // Keep the same time at the left edge when the scale changes (window
      // resize, rotation).
      final minutes = _hOffset / previous.pxPerMinute;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpHorizontal(minutes * m.pxPerMinute);
        _buildSpan.value = _spanAround(_hOffset, m);
      });
    }
  }

  void _onHorizontalScroll() {
    final m = _metrics;
    if (m == null || !_hCtrl.hasClients) return;
    final start = _hCtrl.offset / m.pxPerMinute;
    final end = start + m.programViewportWidth / m.pxPerMinute;
    final span = _buildSpan.value;
    // Rebuild the rows around the view once it drifts to within an hour
    // of the built span's edge.
    if (start - 60 < span.start || end + 60 > span.end) {
      _buildSpan.value = _spanAround(_hCtrl.offset, m);
    }
  }

  void _scrollToStart() {
    final m = _metrics;
    if (!mounted || m == null) return;
    _jumpHorizontal(_startOffsetFor(m));
  }

  void _jumpHorizontal(double offset) {
    final ctrl = _hCtrlOrNull;
    if (ctrl == null || !ctrl.hasClients) return;
    final clamped = offset.clamp(0.0, ctrl.position.maxScrollExtent);
    if ((ctrl.offset - clamped).abs() > 0.5) ctrl.jumpTo(clamped);
  }

  /// Scrolls horizontally so enough of [program] is on screen: nothing if
  /// at least half the view (or all of it) already shows, otherwise the
  /// whole programme when it fits, else its start. Returns the offset.
  double _revealProgram(EpgProgram program) {
    final m = _metrics;
    final ctrl = _hCtrlOrNull;
    if (m == null || ctrl == null || !ctrl.hasClients) return _hOffset;
    final start = math.max<double>(0, _minutesFromStart(program.start));
    final end = math.min(
      _windowEnd.difference(_windowStart).inMinutes.toDouble(),
      _minutesFromStart(program.end),
    );
    final left = start * m.pxPerMinute;
    final right = end * m.pxPerMinute;
    final viewWidth = m.programViewportWidth;
    final offset = ctrl.offset;
    final visible =
        math.min(right, offset + viewWidth) - math.max(left, offset);
    final width = right - left;
    if (visible >= math.min(width, viewWidth * 0.5) - 1) return offset;
    final pad = m.pxPerMinute * 10;
    final target = width + pad * 2 <= viewWidth && left > offset
        ? right + pad - viewWidth
        : left - pad;
    _jumpHorizontal(target);
    return ctrl.offset;
  }

  void _revealRow(int row) {
    final m = _metrics;
    if (m == null || !_vCtrl.hasClients) return;
    final position = _vCtrl.position;
    final top = row * m.rowHeight;
    final bottom = top + m.rowHeight;
    final viewport = position.viewportDimension;
    // Keep one row of context above/below the cursor when there's room.
    final pad = viewport >= m.rowHeight * 3 ? m.rowHeight : 0.0;
    double? target;
    if (top - pad < position.pixels) {
      target = top - pad;
    } else if (bottom + pad > position.pixels + viewport) {
      target = bottom + pad - viewport;
    }
    if (target == null) return;
    _vCtrl.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  // ---------------------------------------------------------------------------
  // Cursor
  // ---------------------------------------------------------------------------

  List<EpgProgram> _rowPrograms(int row) {
    if (row < 0 || row >= widget.channels.length) return const [];
    return EpgGuideNavigation.inWindow(
      widget.epgService.programsForChannel(widget.channels[row]),
      _windowStart,
      _windowEnd,
    );
  }

  void _setCursor(_GuideCursor cursor) => _cursor.value = cursor;

  /// Where entering a row's programmes (from the channel cell, or a fresh
  /// landing) should aim: "now" when it's on screen, else the view's start.
  DateTime _entryTime() {
    final now = widget.clock();
    final visible = _visibleTimeRange();
    if (visible == null) {
      return now.isBefore(_windowStart) || !now.isBefore(_windowEnd)
          ? _windowStart
          : now;
    }
    if (!now.isBefore(visible.$1) && now.isBefore(visible.$2)) return now;
    return visible.$1.add(const Duration(minutes: 1));
  }

  DateTime _anchorInWindow() {
    final anchor = _anchor;
    if (anchor != null &&
        !anchor.isBefore(_windowStart) &&
        anchor.isBefore(_windowEnd)) {
      return anchor;
    }
    return _entryTime();
  }

  void _moveToProgram(EpgProgram program) {
    final offset = _revealProgram(program);
    _anchor = EpgGuideNavigation.anchorFor(
      program,
      now: widget.clock(),
      visibleStart: _visibleTimeRange(offset)?.$1 ?? _windowStart,
    );
    _setCursor(_cursor.value.copyWith(program: program, onChannel: false));
  }

  void _moveToRow(int row) {
    final cursor = _cursor.value;
    EpgProgram? program;
    if (!cursor.onChannel) {
      program = EpgGuideNavigation.at(_rowPrograms(row), _anchorInWindow());
    }
    _revealRow(row);
    _setCursor(
      cursor.copyWith(
        row: row,
        program: program,
        clearProgram: program == null,
      ),
    );
    if (program != null) _revealProgram(program);
  }

  void _pageRows(int direction) {
    final m = _metrics;
    if (m == null || widget.channels.isEmpty) return;
    final viewport = _vCtrl.hasClients
        ? _vCtrl.position.viewportDimension
        : m.rowHeight * 5;
    final perPage = math.max(1, (viewport / m.rowHeight).floor() - 1);
    final row = (_cursor.value.row + direction * perPage).clamp(
      0,
      widget.channels.length - 1,
    );
    if (row == _cursor.value.row) return;
    _moveToRow(row);
    widget.onCursorMove?.call();
  }

  void _advanceToNextDay() {
    if (!_canGoNext) return;
    _selectDate(_offsetDate(_selectedDate, 1), scrollToDayStart: true);
    _anchor = _windowStart;
    final programs = _rowPrograms(_cursor.value.row);
    // The day's first programme is usually the one running over midnight,
    // which the cursor is already on; step to the first that starts here.
    final target =
        programs.where((p) => !p.start.isBefore(_windowStart)).firstOrNull ??
        programs.firstOrNull;
    _setCursor(
      _cursor.value.copyWith(
        onChannel: false,
        program: target,
        clearProgram: target == null,
      ),
    );
  }

  /// Re-resolves the cursor's programme after anything that can invalidate
  /// it without a key press: a day change, a new channel list, or EPG data
  /// arriving for a row the cursor landed on while it was still empty.
  void _revalidateCursor() {
    if (!mounted || widget.channels.isEmpty) return;
    final cursor = _cursor.value;
    final row = cursor.row.clamp(0, widget.channels.length - 1);
    if (cursor.onChannel) {
      if (row != cursor.row) _setCursor(cursor.copyWith(row: row));
      return;
    }
    final programs = _rowPrograms(row);
    final current = cursor.program;
    if (row == cursor.row && current != null && programs.any(cursor.isOn)) {
      return;
    }
    final target = EpgGuideNavigation.at(programs, _anchorInWindow());
    _setCursor(
      cursor.copyWith(row: row, program: target, clearProgram: target == null),
    );
  }

  void _scheduleRevalidate() {
    if (_revalidateScheduled) return;
    _revalidateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revalidateScheduled = false;
      _revalidateCursor();
    });
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  bool _onDirection(TraversalDirection direction) {
    final before = _cursor.value;
    final handled = _moveCursor(direction);
    if (handled && _cursor.value != before) widget.onCursorMove?.call();
    return handled;
  }

  bool _moveCursor(TraversalDirection direction) {
    if (widget.channels.isEmpty) return false;
    final cursor = _cursor.value;
    switch (direction) {
      case TraversalDirection.left:
        // Off the channel cell: let D-pad traversal leave the guide (the
        // enclosing region hands it to the sidebar/category strip).
        if (cursor.onChannel) return false;
        final current = cursor.program;
        final previous = current == null
            ? null
            : EpgGuideNavigation.previous(_rowPrograms(cursor.row), current);
        if (previous == null) {
          _setCursor(cursor.copyWith(onChannel: true));
        } else {
          _moveToProgram(previous);
        }
        return true;
      case TraversalDirection.right:
        final programs = _rowPrograms(cursor.row);
        if (cursor.onChannel) {
          final entry = _entryTime();
          final target = EpgGuideNavigation.at(programs, entry);
          if (target == null) {
            _anchor = entry;
            _setCursor(
              cursor.copyWith(onChannel: false, clearProgram: true),
            );
          } else {
            _moveToProgram(target);
          }
          return true;
        }
        final current = cursor.program;
        final next = current == null
            ? null
            : EpgGuideNavigation.next(programs, current);
        if (next == null) {
          if (current != null) _advanceToNextDay();
        } else {
          _moveToProgram(next);
        }
        return true;
      case TraversalDirection.up:
        // Top row: let traversal move up to the day toolbar.
        if (cursor.row == 0) return false;
        _moveToRow(cursor.row - 1);
        return true;
      case TraversalDirection.down:
        if (cursor.row < widget.channels.length - 1) {
          _moveToRow(cursor.row + 1);
        }
        return true;
    }
  }

  KeyEventResult _onGuideKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.pageUp) {
      _pageRows(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.channelDown ||
        key == LogicalKeyboardKey.pageDown) {
      _pageRows(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onGridFocusChange(bool focused) {
    _setCursor(_cursor.value.copyWith(focused: focused));
    if (focused) _revalidateCursor();
  }

  void _activateCursor() {
    if (widget.channels.isEmpty) return;
    final cursor = _cursor.value;
    final channel = widget.channels[cursor.row];
    final program = cursor.program;
    if (cursor.onChannel || program == null) {
      widget.onChannelSelect(channel);
      return;
    }
    _activateProgram(channel, program);
  }

  void _activateProgram(Channel channel, EpgProgram program) {
    final selection = EpgGuideSelection(
      channel: channel,
      program: program,
      now: widget.clock(),
    );
    switch (selection.action) {
      case EpgGuideAction.watchReplay:
        widget.onCatchupProgramSelect?.call(channel, program);
      case EpgGuideAction.options:
        widget.onChannelLongPress?.call(channel, program);
      case EpgGuideAction.none:
        break;
      case EpgGuideAction.watchLive:
        widget.onChannelSelect(channel);
    }
  }

  bool get _hasLongPress =>
      widget.onChannelLongPress != null ||
      widget.onChannelColumnLongPress != null;

  /// Whether hold-OK at [cursor] goes to the channel menu rather than the
  /// programme's: on the channel cell, on an empty row, or on one of the
  /// editor's filler blocks (nothing there to record).
  bool _usesChannelOptions(_GuideCursor cursor) {
    final program = cursor.program;
    return cursor.onChannel || program == null || program.isPlaceholder;
  }

  bool _canOpenOptions(_GuideCursor cursor) => _usesChannelOptions(cursor)
      ? widget.onChannelColumnLongPress != null
      : widget.onChannelLongPress != null;

  /// What OK does at [cursor], mirroring [_activateCursor] so the preview's
  /// hint matches the key.
  EpgGuideAction _okActionFor(
    _GuideCursor cursor,
    EpgGuideSelection selection,
  ) {
    if (cursor.onChannel || cursor.program == null) {
      return EpgGuideAction.watchLive;
    }
    return switch (selection.action) {
      EpgGuideAction.watchReplay when widget.onCatchupProgramSelect == null =>
        EpgGuideAction.none,
      EpgGuideAction.options when widget.onChannelLongPress == null =>
        EpgGuideAction.none,
      final action => action,
    };
  }

  void _openCursorOptions() {
    if (widget.channels.isEmpty) return;
    final cursor = _cursor.value;
    final channel = widget.channels[cursor.row];
    final program = cursor.program;
    if (_usesChannelOptions(cursor) || program == null) {
      widget.onChannelColumnLongPress?.call(channel);
      return;
    }
    widget.onChannelLongPress?.call(channel, program);
  }

  void _onProgramTap(int row, EpgProgram program) {
    final channel = widget.channels[row];
    _anchor = EpgGuideNavigation.anchorFor(
      program,
      now: widget.clock(),
      visibleStart: _visibleTimeRange()?.$1 ?? _windowStart,
    );
    _setCursor(
      _cursor.value.copyWith(row: row, program: program, onChannel: false),
    );
    if (widget.tapOpensDetails) {
      unawaited(_showDetails(channel, program));
      return;
    }
    _gridFocusNode.requestFocus();
    _activateProgram(channel, program);
  }

  void _onProgramHover(int row, EpgProgram program) {
    final cursor = _cursor.value;
    if (cursor.row == row && cursor.isOn(program)) return;
    _setCursor(cursor.copyWith(row: row, program: program, onChannel: false));
  }

  void _onChannelTap(int row) {
    _setCursor(_cursor.value.copyWith(row: row, onChannel: true));
    if (!widget.tapOpensDetails) _gridFocusNode.requestFocus();
    widget.onChannelSelect(widget.channels[row]);
  }

  Future<void> _showDetails(Channel channel, EpgProgram program) {
    final onReplay = widget.onCatchupProgramSelect;
    final onProgramOptions = widget.onChannelLongPress;
    final onChannelOptions = widget.onChannelColumnLongPress;
    final onMoreOptions = program.isPlaceholder
        ? (onChannelOptions == null ? null : () => onChannelOptions(channel))
        : (onProgramOptions == null
              ? null
              : () => onProgramOptions(channel, program));
    return showEpgProgramDetailsSheet(
      context,
      selection: EpgGuideSelection(
        channel: channel,
        program: program,
        now: widget.clock(),
        recordingState: widget.recordingStateFor(channel, program),
      ),
      onWatchLive: () => widget.onChannelSelect(channel),
      onWatchReplay: onReplay == null ? null : () => onReplay(channel, program),
      onMoreOptions: onMoreOptions,
    );
  }

  EpgGuideSelection? _selectionFor(_GuideCursor cursor) {
    if (widget.channels.isEmpty) return null;
    final row = cursor.row.clamp(0, widget.channels.length - 1);
    final channel = widget.channels[row];
    final now = widget.clock();
    final program = cursor.onChannel
        ? EpgGuideNavigation.at(
            widget.epgService
                .programsForChannel(channel)
                .where((p) => p.end.isAfter(now))
                .toList(),
            now,
          )
        : cursor.program;
    return EpgGuideSelection(
      channel: channel,
      program: program,
      now: now,
      recordingState: program == null
          ? EpgRecordingState.none
          : widget.recordingStateFor(channel, program),
    );
  }

  void _ensureEpgAround(BuildContext context, int index) {
    final onEnsureEpg = widget.onEnsureEpg;
    if (onEnsureEpg == null) return;
    // Request this row plus a look-ahead window so a downward scroll hits
    // loaded EPG. The call is debounced and de-duped downstream.
    final isSpeed =
        ImageQualityScope.of(context)?.optimizeFor == OptimizeFor.speed;
    final end = math.min(
      widget.channels.length,
      index +
          1 +
          (isSpeed ? _kEpgPrefetchAheadSpeed : _kEpgPrefetchAheadQuality),
    );
    onEnsureEpg(
      widget.channels.sublist(index, end),
      startDate: _selectedDate,
      endDate: _selectedDate,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _now = widget.clock();
    final cursor = _cursor.value;
    if (!cursor.onChannel &&
        cursor.program == null &&
        _rowPrograms(cursor.row).isNotEmpty) {
      // Data arrived for a row the cursor was waiting on.
      _scheduleRevalidate();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _computeMetrics(context, constraints.maxWidth);
        _applyMetrics(metrics);
        final showPreview =
            widget.showPreview &&
            constraints.maxWidth >= _kMinWidthForPreview &&
            constraints.maxHeight >=
                _kMinHeightForPreview * FontSizeScope.scaleOf(context);
        final previewHeight = (constraints.maxHeight * 0.32).clamp(
          200.0,
          360.0,
        );
        return Column(
          children: [
            if (showPreview)
              SizedBox(
                height: previewHeight,
                child: ValueListenableBuilder<_GuideCursor>(
                  valueListenable: _cursor,
                  builder: (context, cursor, _) {
                    final selection = _selectionFor(cursor);
                    if (selection == null) return const SizedBox.shrink();
                    return EpgProgramPreview(
                      selection: selection,
                      okAction: _okActionFor(cursor, selection),
                      canOpenOptions: _canOpenOptions(cursor),
                    );
                  },
                ),
              ),
            _DayToolbar(
              blockUp: showPreview,
              selectedDate: _selectedDate,
              today: _dateOnly(_now),
              compact: metrics.compact,
              canGoPrevious: _canGoPrevious,
              canGoNext: _canGoNext,
              onPrevious: () => _selectDate(_offsetDate(_selectedDate, -1)),
              onNow: () {
                _anchor = null;
                _selectDate(_dateOnly(widget.clock()));
              },
              onNext: () => _selectDate(_offsetDate(_selectedDate, 1)),
            ),
            Expanded(child: _buildGuide(context, metrics)),
          ],
        );
      },
    );
  }

  Widget _buildGuide(BuildContext context, _GuideMetrics m) {
    final totalWidth = _totalWidth(m);
    final hCtrl = _hCtrl;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onGuideKey,
      child: DpadFocusable(
        focusNode: _gridFocusNode,
        debugLabel: 'epg-guide',
        autofocus: widget.autofocus,
        autoScroll: false,
        tapToSelect: false,
        effects: const <DpadEffect>[],
        onDirection: _onDirection,
        onSelect: _activateCursor,
        onLongSelect: _hasLongPress ? _openCursorOptions : null,
        onFocusChange: _onGridFocusChange,
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: hCtrl,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: m.channelColumnWidth + totalWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: m.rulerHeight,
                        child: Stack(
                          children: [
                            Positioned(
                              left: m.channelColumnWidth,
                              top: 0,
                              bottom: 0,
                              width: totalWidth,
                              child: _TimeRuler(
                                windowStart: _windowStart,
                                windowEnd: _windowEnd,
                                pxPerMinute: m.pxPerMinute,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: m.channelColumnWidth,
                              child: _PinnedToViewport(
                                controller: hCtrl,
                                child: _RulerCorner(now: _now),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _vCtrl,
                          itemCount: widget.channels.length,
                          itemExtent: m.rowHeight,
                          scrollCacheExtent: ScrollCacheExtent.pixels(
                            m.rowHeight * 10,
                          ),
                          itemBuilder: (context, index) =>
                              _buildRow(context, index, m, totalWidth),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _NowLine(
                  controller: hCtrl,
                  metrics: m,
                  nowOffset: _minutesFromStart(_now) * m.pxPerMinute,
                  totalWidth: totalWidth,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    int index,
    _GuideMetrics m,
    double totalWidth,
  ) {
    final channel = widget.channels[index];
    _ensureEpgAround(context, index);
    return _GuideRow(
      key: ValueKey('timeline-row-${channel.id}'),
      index: index,
      channel: channel,
      programs: _rowPrograms(index),
      metrics: m,
      totalWidth: totalWidth,
      windowStart: _windowStart,
      now: _now,
      cursor: _cursor,
      buildSpan: _buildSpan,
      hCtrl: _hCtrl,
      columnLayout: widget.channelColumnLayout,
      isRecording: widget.recordingChannelIds.contains(channel.id),
      recordingStateFor: (program) =>
          widget.recordingStateFor(channel, program),
      onProgramTap: (program) => _onProgramTap(index, program),
      onProgramLongPress: widget.onChannelLongPress == null
          ? null
          : (program) => widget.onChannelLongPress!(channel, program),
      onProgramHover: widget.showPreview
          ? (program) => _onProgramHover(index, program)
          : null,
      onChannelTap: () => _onChannelTap(index),
      onChannelLongPress: widget.onChannelColumnLongPress == null
          ? null
          : () => widget.onChannelColumnLongPress!(channel),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Keeps [child] fixed at the viewport's left edge while its horizontally
/// scrolling parent moves underneath it.
class _PinnedToViewport extends StatelessWidget {
  const _PinnedToViewport({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          controller.hasClients
              ? controller.offset
              : controller.initialScrollOffset,
          0,
        ),
        child: child,
      ),
      child: child,
    );
  }
}

class _DayToolbar extends StatelessWidget {
  const _DayToolbar({
    required this.blockUp,
    required this.selectedDate,
    required this.today,
    required this.compact,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNow,
    required this.onNext,
  });

  /// Swallow D-pad Up here. With the preview panel above there's nothing
  /// focusable directly up, so traversal would otherwise jump sideways into
  /// the middle of the category strip.
  final bool blockUp;
  final DateTime selectedDate;
  final DateTime today;
  final bool compact;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNow;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    Widget chevron({
      required Key key,
      required IconData icon,
      required bool enabled,
      required VoidCallback onTap,
      required String label,
    }) {
      return DpadInkWell(
        key: key,
        onTap: enabled ? onTap : null,
        enabled: enabled,
        autoScroll: false,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * scale),
          child: Center(
            child: Icon(
              icon,
              size: 26 * scale,
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.3),
              semanticLabel: label,
            ),
          ),
        ),
      );
    }

    final toolbar = Container(
      height: (compact ? 50 : 58) * scale,
      padding: EdgeInsets.symmetric(
        horizontal: (compact ? 8 : 12) * scale,
        vertical: 6 * scale,
      ),
      // crossAxisAlignment.stretch gives every focusable the same rect
      // height, so D-pad Down from any of them reads as leaving the row
      // (dpad's edge-based "is this candidate below me" check) instead of
      // hopping to a taller neighbour.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chevron(
            key: const ValueKey('timeline-previous-day'),
            icon: Icons.chevron_left,
            enabled: canGoPrevious,
            onTap: onPrevious,
            label: l10n.epgPreviousDay,
          ),
          SizedBox(
            width: (compact ? 118 : 150) * scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  epgRelativeDayLabel(context, selectedDate, today),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormat.yMMMd(locale).format(selectedDate),
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          chevron(
            key: const ValueKey('timeline-next-day'),
            icon: Icons.chevron_right,
            enabled: canGoNext,
            onTap: onNext,
            label: l10n.epgNextDay,
          ),
          SizedBox(width: 12 * scale),
          DpadInkWell(
            key: const ValueKey('timeline-now'),
            onTap: onNow,
            autoScroll: false,
            borderRadius: BorderRadius.circular(50),
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.today,
                    size: 18 * scale,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  SizedBox(width: 6 * scale),
                  Text(
                    l10n.epgNow,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (!blockUp) return toolbar;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) =>
          event is! KeyUpEvent &&
              Dpad.keySetOf(context).directionOf(event.logicalKey) ==
                  TraversalDirection.up
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: toolbar,
    );
  }
}

/// The corner above the channel column: the current time.
class _RulerCorner extends StatelessWidget {
  const _RulerCorner({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          epgTimeLabel(context, now),
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TimeRuler extends StatelessWidget {
  const _TimeRuler({
    required this.windowStart,
    required this.windowEnd,
    required this.pxPerMinute,
  });

  final DateTime windowStart;
  final DateTime windowEnd;
  final double pxPerMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Hourly labels only when half-hours would crowd each other.
    final step = pxPerMinute * 30 >= 110 ? 30 : 60;
    final labels = <Widget>[];
    var slot = DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day,
      windowStart.hour,
      (windowStart.minute ~/ step) * step,
    );
    while (slot.isBefore(windowEnd)) {
      final x = slot.difference(windowStart).inMinutes * pxPerMinute;
      if (x >= 0) {
        final isHour = slot.minute == 0;
        labels.add(
          Positioned(
            left: x,
            top: 0,
            bottom: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1,
                  margin: const EdgeInsets.only(top: 12),
                  color: colorScheme.outlineVariant,
                ),
                const SizedBox(width: 6),
                Center(
                  child: Text(
                    epgTimeLabel(context, slot),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isHour
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: isHour ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      slot = DateTime(
        slot.year,
        slot.month,
        slot.day,
        slot.hour,
        slot.minute + step,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Stack(children: labels),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({
    required this.controller,
    required this.metrics,
    required this.nowOffset,
    required this.totalWidth,
  });

  final ScrollController controller;
  final _GuideMetrics metrics;
  final double nowOffset;
  final double totalWidth;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (nowOffset < 0 || nowOffset > totalWidth) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final offset = controller.hasClients
            ? controller.offset
            : controller.initialScrollOffset;
        final x = metrics.channelColumnWidth + nowOffset - offset;
        if (x < metrics.channelColumnWidth || x > metrics.viewportWidth) {
          return const SizedBox.shrink();
        }
        final top = metrics.rulerHeight * 0.3;
        return Stack(
          children: [
            Positioned(
              left: x - 1,
              top: top,
              bottom: 0,
              width: 2,
              child: ColoredBox(color: color.withValues(alpha: 0.85)),
            ),
            Positioned(
              left: x - 5,
              top: top - 5,
              width: 10,
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One channel row: its pinned channel cell plus its programmes. Listens
/// to the shared cursor itself and only rebuilds when the cursor enters,
/// moves within, or leaves this row, so a key press repaints one or two
/// rows rather than the whole visible guide.
class _GuideRow extends StatefulWidget {
  const _GuideRow({
    super.key,
    required this.index,
    required this.channel,
    required this.programs,
    required this.metrics,
    required this.totalWidth,
    required this.windowStart,
    required this.now,
    required this.cursor,
    required this.buildSpan,
    required this.hCtrl,
    required this.columnLayout,
    required this.isRecording,
    required this.recordingStateFor,
    required this.onProgramTap,
    required this.onChannelTap,
    this.onProgramLongPress,
    this.onProgramHover,
    this.onChannelLongPress,
  });

  final int index;
  final Channel channel;
  final List<EpgProgram> programs;
  final _GuideMetrics metrics;
  final double totalWidth;
  final DateTime windowStart;
  final DateTime now;
  final ValueNotifier<_GuideCursor> cursor;
  final ValueNotifier<_MinuteSpan> buildSpan;
  final ScrollController hCtrl;
  final ChannelColumnLayout columnLayout;
  final bool isRecording;
  final EpgRecordingState Function(EpgProgram program) recordingStateFor;
  final ValueChanged<EpgProgram> onProgramTap;
  final ValueChanged<EpgProgram>? onProgramLongPress;
  final ValueChanged<EpgProgram>? onProgramHover;
  final VoidCallback onChannelTap;
  final VoidCallback? onChannelLongPress;

  @override
  State<_GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends State<_GuideRow> {
  late _GuideCursor _lastCursor;

  @override
  void initState() {
    super.initState();
    _lastCursor = widget.cursor.value;
    widget.cursor.addListener(_onCursorChanged);
    widget.buildSpan.addListener(_onSpanChanged);
  }

  @override
  void dispose() {
    widget.cursor.removeListener(_onCursorChanged);
    widget.buildSpan.removeListener(_onSpanChanged);
    super.dispose();
  }

  void _onCursorChanged() {
    final next = widget.cursor.value;
    final affected =
        _lastCursor.row == widget.index || next.row == widget.index;
    _lastCursor = next;
    if (affected) setState(() {});
  }

  void _onSpanChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final colorScheme = Theme.of(context).colorScheme;
    final cursor = widget.cursor.value;
    _lastCursor = cursor;
    final isCursorRow = cursor.row == widget.index;
    final showCursor = isCursorRow && cursor.focused;
    final catchupDays = EpgService.effectiveCatchupRetentionDays(
      widget.channel.catchupSupported,
      widget.channel.catchupDays,
    );
    final span = widget.buildSpan.value;

    final cells = <Widget>[];
    for (final program in widget.programs) {
      final startMinutes = math.max<double>(
        0,
        program.start.difference(widget.windowStart).inSeconds / 60,
      );
      final endMinutes = math.min(
        widget.totalWidth / m.pxPerMinute,
        program.end.difference(widget.windowStart).inSeconds / 60,
      );
      if (!span.overlaps(startMinutes, endMinutes)) continue;
      final left = startMinutes * m.pxPerMinute;
      final width = (endMinutes - startMinutes) * m.pxPerMinute;
      cells.add(
        Positioned(
          left: left + 2,
          top: 3,
          bottom: 3,
          width: math.max(2, width - 4),
          child: _ProgramCell(
            key: ValueKey(
              'timeline-program-${program.channelId}-'
              '${program.start.toIso8601String()}',
            ),
            program: program,
            width: width - 4,
            now: widget.now,
            compact: m.compact,
            canReplay: EpgService.canReplay(catchupDays, program, widget.now),
            recordingState: widget.recordingStateFor(program),
            focused: showCursor && cursor.isOn(program),
            onTap: () => widget.onProgramTap(program),
            onLongPress: widget.onProgramLongPress == null
                ? null
                : () => widget.onProgramLongPress!(program),
            onHover: widget.onProgramHover == null
                ? null
                : () => widget.onProgramHover!(program),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: m.channelColumnWidth,
            top: 0,
            bottom: 0,
            width: widget.totalWidth,
            child: RepaintBoundary(child: Stack(children: cells)),
          ),
          if (widget.programs.isEmpty)
            Positioned(
              left: m.channelColumnWidth,
              top: 0,
              bottom: 0,
              width: m.programViewportWidth,
              child: _PinnedToViewport(
                controller: widget.hCtrl,
                child: _EmptyRowCell(
                  focused: showCursor && !cursor.onChannel,
                  compact: m.compact,
                ),
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: m.channelColumnWidth,
            child: _PinnedToViewport(
              controller: widget.hCtrl,
              child: RepaintBoundary(
                child: _ChannelCell(
                  channel: widget.channel,
                  layout: widget.columnLayout,
                  compact: m.compact,
                  isRecording: widget.isRecording,
                  rowActive: showCursor,
                  focused: showCursor && cursor.onChannel,
                  onTap: widget.onChannelTap,
                  onLongPress: widget.onChannelLongPress,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The focused-cell outline: the same gradient ring D-pad focus draws
/// everywhere else in the app.
class _CursorRing extends StatelessWidget {
  const _CursorRing({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('timeline-cursor'),
        painter: GradientBorderPainter(
          borderRadius: BorderRadius.circular(radius),
          width: 3,
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [colorScheme.primary, colorScheme.secondary],
          ),
        ),
      ),
    );
  }
}

class _ProgramCell extends StatelessWidget {
  const _ProgramCell({
    super.key,
    required this.program,
    required this.width,
    required this.now,
    required this.compact,
    required this.canReplay,
    required this.recordingState,
    required this.focused,
    required this.onTap,
    this.onLongPress,
    this.onHover,
  });

  final EpgProgram program;
  final double width;
  final DateTime now;
  final bool compact;
  final bool canReplay;
  final EpgRecordingState recordingState;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final isLive = !now.isBefore(program.start) && now.isBefore(program.end);
    final isPast = !program.end.isAfter(now);
    final dimmed = isPast && !canReplay;

    final Color background;
    if (focused) {
      background = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.32),
        colorScheme.surfaceContainerHighest,
      );
    } else if (isLive) {
      background = Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.16),
        colorScheme.surfaceContainerHigh,
      );
    } else if (isPast || program.isPlaceholder) {
      background = colorScheme.surfaceContainerLow;
    } else {
      background = colorScheme.surfaceContainerHigh;
    }
    final foreground = dimmed
        ? colorScheme.onSurface.withValues(alpha: 0.55)
        : colorScheme.onSurface;

    final showText = width >= 28;
    final showSecondLine = width >= 90;
    final showBadges = width >= 64;

    final title = program.isPlaceholder ? l10n.epgNoData : program.displayTitle;
    final titleStyle =
        (compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium)
            ?.copyWith(
              color: program.isPlaceholder
                  ? colorScheme.onSurfaceVariant
                  : foreground,
              fontWeight: isLive || focused ? FontWeight.w600 : FontWeight.w500,
              fontStyle: program.isPlaceholder ? FontStyle.italic : null,
            );
    final episode = program.isPlaceholder
        ? null
        : epgEpisodeLabel(l10n, program);
    final secondLine = [
      epgTimeLabel(context, program.start),
      ?episode,
    ].join('  ·  ');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: onHover == null ? null : (_) => onHover!(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Semantics(
          button: true,
          selected: focused,
          label: title,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                if (showText)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: width < 80 ? 6 : 10,
                        vertical: 4,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (showBadges &&
                                  recordingState != EpgRecordingState.none) ...[
                                ProgramRecordingIndicator(
                                  state: recordingState,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  style: titleStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showBadges && canReplay) ...[
                                const SizedBox(width: 6),
                                EpgIconPill(
                                  color: colorScheme.tertiaryContainer,
                                  borderColor: colorScheme.tertiary.withValues(
                                    alpha: 0.55,
                                  ),
                                  child: Icon(
                                    Icons.replay_rounded,
                                    size: 12,
                                    color: colorScheme.onTertiaryContainer,
                                    semanticLabel:
                                        l10n.catchupProgramReplayable,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (showSecondLine && !program.isPlaceholder) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    secondLine,
                                    style:
                                        (compact
                                                ? theme.textTheme.bodySmall
                                                : theme.textTheme.bodyMedium)
                                            ?.copyWith(
                                              color: dimmed
                                                  ? colorScheme.onSurfaceVariant
                                                        .withValues(alpha: 0.6)
                                                  : colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (program.isNew) ...[
                                  const SizedBox(width: 6),
                                  _NewBadge(label: l10n.epgBadgeNew),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (isLive)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    height: 3,
                    width:
                        width *
                        (now.difference(program.start).inSeconds /
                                math.max(
                                  1,
                                  program.end
                                      .difference(program.start)
                                      .inSeconds,
                                ))
                            .clamp(0.0, 1.0),
                    child: ColoredBox(color: colorScheme.primary),
                  ),
                if (focused)
                  const Positioned.fill(child: _CursorRing(radius: 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// A row with no programme data: a single cell pinned across the visible
/// programme area, so the cursor still has somewhere to sit.
class _EmptyRowCell extends StatelessWidget {
  const _EmptyRowCell({required this.focused, required this.compact});

  final bool focused;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: focused
                    ? Color.alphaBlend(
                        colorScheme.primary.withValues(alpha: 0.2),
                        colorScheme.surfaceContainerHigh,
                      )
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                AppLocalizations.of(context).epgNoData,
                style:
                    (compact
                            ? theme.textTheme.bodySmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          fontStyle: FontStyle.italic,
                        ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (focused) const Positioned.fill(child: _CursorRing(radius: 8)),
        ],
      ),
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.layout,
    required this.compact,
    required this.isRecording,
    required this.rowActive,
    required this.focused,
    required this.onTap,
    this.onLongPress,
  });

  final Channel channel;
  final ChannelColumnLayout layout;
  final bool compact;
  final bool isRecording;

  /// The cursor is somewhere in this row: tint the cell so the channel the
  /// focused programme belongs to is obvious.
  final bool rowActive;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  Widget _logo(double size) {
    final url = channel.logoUrl;
    final fallback = Icon(Icons.tv, size: size * 0.8);
    if (url == null || url.isEmpty) return fallback;
    return CachedMediaThumbnail(
      url: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      oversample: 2,
      fallback: fallback,
    );
  }

  Widget _logoWithRecordingDot(ColorScheme colorScheme, double size) {
    if (!isRecording) return _logo(size);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _logo(size),
          Positioned(
            top: -2,
            right: -2,
            child: RecordingDot(color: colorScheme.error),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final number = channel.channelNumber;
    final numberStyle = theme.textTheme.labelMedium?.copyWith(
      color: focused ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final nameStyle =
        (compact ? theme.textTheme.labelMedium : theme.textTheme.titleSmall)
            ?.copyWith(fontWeight: focused ? FontWeight.w700 : null);

    final Widget content = switch (layout) {
      ChannelColumnLayout.logoOnly => Center(
        child: _logoWithRecordingDot(
          colorScheme,
          (compact ? 36 : 44) * scale,
        ),
      ),
      ChannelColumnLayout.logoAndTitle when compact => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _logoWithRecordingDot(colorScheme, 26 * scale),
          const SizedBox(height: 3),
          Text(
            channel.name,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      ChannelColumnLayout.logoAndTitle => Row(
        children: [
          _logoWithRecordingDot(colorScheme, 40 * scale),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              channel.name,
              style: nameStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      ChannelColumnLayout.titleOnly => Row(
        children: [
          if (isRecording) ...[
            RecordingDot(color: colorScheme.error),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              channel.name,
              style: nameStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Semantics(
        button: true,
        selected: focused,
        label: channel.name,
        child: Container(
          decoration: BoxDecoration(
            color: focused
                ? Color.alphaBlend(
                    colorScheme.primary.withValues(alpha: 0.3),
                    colorScheme.surfaceContainerHighest,
                  )
                : rowActive
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surface,
            border: Border(
              right: BorderSide(color: colorScheme.outlineVariant),
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    number != null && layout != ChannelColumnLayout.logoOnly
                        ? 40 * scale
                        : 8,
                    6,
                    8,
                    6,
                  ),
                  child: content,
                ),
              ),
              if (number != null)
                Positioned(
                  left: 8,
                  top: layout == ChannelColumnLayout.logoOnly ? 4 : 0,
                  bottom: layout == ChannelColumnLayout.logoOnly ? null : 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$number', style: numberStyle),
                  ),
                ),
              if (channel.catchupSupported)
                Positioned(
                  top: 3,
                  right: 4,
                  child: CatchupBadge(days: channel.catchupDays, compact: true),
                ),
              if (focused) const Positioned.fill(child: _CursorRing(radius: 0)),
            ],
          ),
        ),
      ),
    );
  }
}
