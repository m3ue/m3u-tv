import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

const double _kChannelColW = 128;
const double _kTimeHeaderH = 28;
const double _kRowH = 60;
const double _kPxPerMin = 5; // 300 px per hour

/// Horizontal TV-guide style EPG — channels on the Y-axis, time on the X-axis.
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
    this.windowHours = 6,
  });

  final List<Channel> channels;
  final EpgService epgService;
  final void Function(Channel) onChannelSelect;

  /// How many hours the visible window spans (default 6).
  final int windowHours;

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
  late DateTime _windowStart;
  late DateTime _windowEnd;
  late double _totalW;

  @override
  void initState() {
    super.initState();
    _initWindow();
    _leftVCtrl = ScrollController();
    _rightVCtrl = ScrollController();
    _headerHCtrl = ScrollController();
    _rowHCtrls = _makeRowCtrls(widget.channels.length);
    _leftVCtrl.addListener(_onLeftV);
    _rightVCtrl.addListener(_onRightV);
    WidgetsBinding.instance.addPostFrameCallback(_scrollToNow);
  }

  void _initWindow() {
    final now = DateTime.now();
    _windowStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).subtract(const Duration(hours: 1));
    _windowEnd = _windowStart.add(Duration(hours: widget.windowHours + 2));
    _totalW = _windowEnd.difference(_windowStart).inMinutes * _kPxPerMin;
  }

  List<ScrollController> _makeRowCtrls(int count) =>
      List.generate(count, (_) => ScrollController());

  void _scrollToNow(_) {
    if (!mounted) return;
    final nowOffset =
        DateTime.now().difference(_windowStart).inMinutes * _kPxPerMin;
    final target = math.max(0, nowOffset - 80.0);
    for (final c in [_headerHCtrl, ..._rowHCtrls]) {
      if (c.hasClients) {
        c.jumpTo(target.clamp(0.0, c.position.maxScrollExtent).toDouble());
      }
    }
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

    return Row(
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
                  'CHANNELS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              // Channel name/logo list (synced vertically with program rows)
              Expanded(
                child: ListView.builder(
                  controller: _leftVCtrl,
                  itemCount: widget.channels.length,
                  itemExtent: _kRowH,
                  itemBuilder: (_, i) =>
                      _ChannelCell(channel: widget.channels[i]),
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
                        DateTime.now().difference(_windowStart).inMinutes *
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
                        if (nowX >= 0)
                          Positioned(
                            left: nowX,
                            top: 4,
                            bottom: 0,
                            width: 2,
                            child: Container(
                              color: colorScheme.primary.withValues(alpha: 0.8),
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
                        final programs = widget.epgService.programsForChannel(
                          channel,
                        );
                        return NotificationListener<ScrollUpdateNotification>(
                          onNotification: (n) {
                            _syncH(n.metrics.pixels);
                            return false;
                          },
                          child: SingleChildScrollView(
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
                              onTap: () => widget.onChannelSelect(channel),
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
                            DateTime.now().difference(_windowStart).inMinutes *
                                _kPxPerMin -
                            _headerHCtrl.offset;
                        if (nowX < 0) return const SizedBox.shrink();
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
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
          Expanded(
            child: Text(
              channel.name,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
  });

  final List<EpgProgram> programs;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double pixelsPerMinute;
  final double totalWidth;
  final double rowHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final visible = programs
        .where((p) => p.end.isAfter(windowStart) && p.start.isBefore(windowEnd))
        .toList();

    final now = DateTime.now();
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
      blocks.add(
        Positioned(
          left: left + 1,
          top: isCurrent ? 2 : 4,
          height: rowHeight - (isCurrent ? 4 : 8),
          width: width - 2,
          child: DpadInkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                p.title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fgColor,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
              'No EPG data',
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
