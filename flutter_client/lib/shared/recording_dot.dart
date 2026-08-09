import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';

/// Small themed dot marking a channel as currently recording. Deliberately
/// compact (no text label) so it holds up on narrow mobile widths; the
/// full description is exposed to screen readers via [Semantics].
class RecordingDot extends StatelessWidget {
  const RecordingDot({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).liveTvRecording,
      child: Container(
        key: const Key('recording-dot'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
