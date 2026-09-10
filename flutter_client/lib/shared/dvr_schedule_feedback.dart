import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Extract a user-facing message from an error, stripping technical prefixes
/// like "Xtream HTTP 503 for POST ...".
String _userFacingMessage(Object error) {
  if (error is XtreamHttpException) {
    return error.serverMessage ?? 'Server error ${error.statusCode}';
  }
  if (error is XtreamDvrScheduleException) {
    return error.message;
  }
  final text = error.toString();
  // Strip "Xtream HTTP ..." prefix if present
  final match = RegExp(
    r'Xtream HTTP \d+\w* for \w+ \S+:\s*(.+)',
  ).firstMatch(text);
  if (match != null) return match.group(1)!;
  return text;
}

/// Runs [schedule] and shows the shared success/failure SnackBar for a
/// single DVR airing. Shared between the live-tv context menu
/// (`AppShell._scheduleDvr`) and the Shows-search episode row
/// (`ShowDetailScreen._scheduleEpisode`) so both surfaces report the same
/// way. Returns the scheduled result, or null if scheduling failed or the
/// context was unmounted by the time the call completed.
///
/// [title] drives the default single-item success message
/// (`l10n.appRecordingScheduled(title)`). Pass [successMessage] instead when
/// the caller needs a different success message shape (e.g. a batch
/// summary) — it receives the captured [AppLocalizations] so it can be
/// built after the same mounted-check this helper already does.
Future<T?> scheduleDvrWithFeedback<T>(
  BuildContext context, {
  required Future<T> Function() schedule,
  String? title,
  String Function(T result, AppLocalizations l10n)? successMessage,
}) async {
  assert(
    title != null || successMessage != null,
    'scheduleDvrWithFeedback requires either title or successMessage',
  );
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    final result = await schedule();
    if (!context.mounted) return null;
    final message = successMessage != null
        ? successMessage(result, l10n)
        : l10n.appRecordingScheduled(title!);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return result;
  } on Object catch (error) {
    if (!context.mounted) return null;
    // Extract the actual server error message instead of showing the
    // raw "Xtream HTTP ..." toString() which is not user-friendly.
    final message = _userFacingMessage(error);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.appRecordingFailed(message))),
    );
    return null;
  }
}
