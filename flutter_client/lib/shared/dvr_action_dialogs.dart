import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';

enum StopRecordingChoice { keep, delete, back }

/// Offers a choice instead of a plain confirm: the server's cancel action
/// only stops the recording and keeps it (status → Cancelled), while
/// deleting is a distinct, explicit follow-up action (see
/// AppShell._cancelAndDeleteRecording). Shared between the Recordings screen
/// and the in-player record button so both surfaces behave identically.
Future<StopRecordingChoice?> showStopRecordingDialog(
  BuildContext context, {
  required String title,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<StopRecordingChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dvrStopTitle(title)),
      content: Text(l10n.dvrStopMessage),
      actions: [
        DpadRegion(
          memoryKey: 'dvr/stop-dialog-actions',
          // OverflowBar (not Row) so three buttons on a narrow TV/mobile
          // dialog stack vertically instead of overflowing horizontally.
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              AppButton(
                label: l10n.dvrStopBack,
                onPressed: () =>
                    Navigator.of(dialogContext).pop(StopRecordingChoice.back),
              ),
              AppButton(
                label: l10n.dvrStopDelete,
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(StopRecordingChoice.delete),
              ),
              AppButton(
                label: l10n.dvrStopKeep,
                variant: AppButtonVariant.primary,
                autofocus: true,
                onPressed: () =>
                    Navigator.of(dialogContext).pop(StopRecordingChoice.keep),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<bool?> showDeleteRecordingDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dvrDeleteTitle),
      content: Text(l10n.dvrDeleteMessage),
      actions: [
        DpadRegion(
          memoryKey: 'dvr/delete-dialog-actions',
          // OverflowBar (not Row) so buttons on a narrow dialog stack
          // vertically instead of overflowing horizontally.
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              AppButton(
                label: l10n.dvrDeleteDismiss,
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppButton(
                label: l10n.dvrDeleteConfirm,
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Confirmation dialog for deleting a DVR series rule. Mirrors the
/// recording-delete dialog structurally, but anchors the title to the
/// series rule's title so the user knows which rule they're about to lose.
Future<bool?> showDeleteSeriesRuleDialog(
  BuildContext context, {
  required DvrSeriesRule rule,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.dvrDeleteSeriesRuleConfirm),
      content: Text(l10n.showDeleteRuleConfirm(rule.seriesTitle)),
      actions: [
        DpadRegion(
          memoryKey: 'dvr/delete-series-rule-dialog-actions',
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              AppButton(
                label: l10n.dvrDeleteDismiss,
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppButton(
                label: l10n.showDeleteRule,
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> runDvrActionWithFeedback(
  BuildContext context,
  Future<void> Function() action, {
  required String successMessage,
  required String failureMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } on Object catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}

/// Full "manage an in-progress recording" flow: shows [showStopRecordingDialog],
/// then runs the chosen action with snackbar feedback. Shared by every surface
/// that can act on a currently-recording channel (Recordings screen, the
/// in-player record button, the Live TV long-press menu) so they behave
/// identically. [onCancelAndDelete] is nullable only so callers degrade
/// gracefully in isolation (e.g. tests) — when absent, cancels immediately
/// with no dialog, since there is nothing to choose between.
Future<void> confirmStopOrDeleteRecording(
  BuildContext context, {
  required DvrRecording recording,
  required Future<void> Function(String uuid) onCancel,
  Future<void> Function(String uuid)? onCancelAndDelete,
}) async {
  final l10n = AppLocalizations.of(context);
  if (onCancelAndDelete == null) {
    await runDvrActionWithFeedback(
      context,
      () => onCancel(recording.uuid),
      successMessage: l10n.dvrCancelSuccess,
      failureMessage: l10n.dvrCancelFailed,
    );
    return;
  }

  final choice = await showStopRecordingDialog(context, title: recording.title);
  if (choice == null || choice == StopRecordingChoice.back) return;
  if (!context.mounted) return;

  if (choice == StopRecordingChoice.keep) {
    await runDvrActionWithFeedback(
      context,
      () => onCancel(recording.uuid),
      successMessage: l10n.dvrCancelSuccess,
      failureMessage: l10n.dvrCancelFailed,
    );
  } else {
    await runDvrActionWithFeedback(
      context,
      () => onCancelAndDelete(recording.uuid),
      successMessage: l10n.dvrDeleteSuccess,
      failureMessage: l10n.dvrDeleteFailed,
    );
  }
}
