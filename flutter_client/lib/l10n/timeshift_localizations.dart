import 'package:m3u_tv/l10n/app_localizations.dart';

/// Timeshift / DVR strings that are newer than the generated localizations.
///
/// Kept as an extension so the generated ARB output stays untouched; add the
/// translations here (or promote to the ARBs) as they are localised.
extension TimeshiftLocalizations on AppLocalizations {
  String get settingsTimeshiftMode => 'Live TV timeshift';

  String get settingsTimeshiftModeHint =>
      'Keep a rolling buffer of recent live TV so you can pause, rewind, '
      "and seek within the window. Off keeps today's behaviour (no rewind).";

  String get settingsLivePrebuffer => 'Live prebuffer';

  String settingsLivePrebufferValue(int count) => '$count s';

  String get dvrRecordingInProgress => 'Recording in progress';

  String get playerWatchLiveEdge => 'Watch live edge';

  String get playerGoLive => 'Go live';
}
