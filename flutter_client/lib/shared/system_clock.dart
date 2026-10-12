import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats a wall-clock time in the OS's 12/24-hour preference.
String formatClockTime(BuildContext context, DateTime time) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final format = MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat.Hm(locale)
      : DateFormat.jm(locale);
  return format.format(time);
}

/// Live wall-clock label. Ported from Plezy's `SystemClock`: a one-shot timer
/// re-armed onto each minute boundary rather than a per-second poll, so it
/// rebuilds once a minute and never flips late; resyncs on resume, since a
/// suspended process runs no timers.
class SystemClock extends StatefulWidget {
  const SystemClock({super.key, this.style, this.now = DateTime.now});

  final TextStyle? style;

  /// Wall-clock source, overridden by tests.
  final DateTime Function() now;

  @override
  State<SystemClock> createState() => _SystemClockState();
}

class _SystemClockState extends State<SystemClock> with WidgetsBindingObserver {
  Timer? _tick;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = widget.now();
    _scheduleTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tickNow();
  }

  void _scheduleTick() {
    final now = _now;
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _tick?.cancel();
    _tick = Timer(nextMinute.difference(now), _tickNow);
  }

  void _tickNow() {
    if (!mounted) return;
    setState(() => _now = widget.now());
    _scheduleTick();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatClockTime(context, _now),
      style: widget.style,
      maxLines: 1,
      softWrap: false,
    );
  }
}
