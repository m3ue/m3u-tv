import 'package:flutter/material.dart';

import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/epg_icon_pill.dart';

/// Per-programme recording badge drawn on an EPG timeline grid block (see
/// #185). Returns a zero-sized widget for [EpgRecordingState.none] so it can
/// be slotted into a parent [Stack] without layout cost when no indicator
/// is wanted.
///
/// Visually mirrors the existing catchup-replay badge (see
/// `timeline_epg_view.dart::_ProgramsRow`): small framed
/// pill, corner-anchored. Distinguishes the two recording states with both
/// icon and colour so they cannot be confused at TV viewing distance:
///   * [EpgRecordingState.scheduled] — clock icon, tertiary colour family
///   * [EpgRecordingState.recording] — filled record icon, error colour
///     family (matches the channel-level RecordingDot and the
///     `Icons.fiber_manual_record` usage in live_tv / playback_controls /
///     dvr_recordings).
///
/// Screen-reader semantics are localised via the matching ARB keys.
class ProgramRecordingIndicator extends StatelessWidget {
  const ProgramRecordingIndicator({required this.state, super.key});

  final EpgRecordingState state;

  @override
  Widget build(BuildContext context) {
    if (state == EpgRecordingState.none) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final Color iconColor;
    final Color containerColor;
    final Color borderColor;
    final IconData icon;
    final String semanticLabel;
    switch (state) {
      case EpgRecordingState.scheduled:
        iconColor = colorScheme.onTertiaryContainer;
        containerColor = colorScheme.tertiaryContainer;
        borderColor = colorScheme.tertiary.withValues(alpha: 0.55);
        icon = Icons.schedule;
        semanticLabel = l10n.epgProgramScheduledToRecord;
      case EpgRecordingState.recording:
        iconColor = colorScheme.onErrorContainer;
        containerColor = colorScheme.errorContainer;
        borderColor = colorScheme.error.withValues(alpha: 0.55);
        icon = Icons.fiber_manual_record;
        semanticLabel = l10n.epgProgramCurrentlyRecording;
      case EpgRecordingState.none:
        return const SizedBox.shrink();
    }

    return Semantics(
      label: semanticLabel,
      child: EpgIconPill(
        color: containerColor,
        borderColor: borderColor,
        child: Icon(icon, size: 10, color: iconColor),
      ),
    );
  }
}
