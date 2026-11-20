import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/apk_update_service.dart';
import 'package:m3u_tv/shared/app_alert_dialog.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:material_ui/material_ui.dart';

/// Downloads [release]'s APK and hands it to Android's installer, asking for
/// the "Install unknown apps" permission first when needed.
Future<void> showApkUpdateDialog(
  BuildContext context,
  ApkRelease release, {
  ApkUpdateService? service,
}) => showAppDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ApkUpdateDialog(release: release, service: service),
);

enum _Stage { permission, downloading, installing, failed }

enum _Failure { download, checksum, cancelled, conflict, storage, install }

class ApkUpdateDialog extends StatefulWidget {
  const ApkUpdateDialog({super.key, required this.release, this.service});

  final ApkRelease release;
  final ApkUpdateService? service;

  @override
  State<ApkUpdateDialog> createState() => _ApkUpdateDialogState();
}

class _ApkUpdateDialogState extends State<ApkUpdateDialog>
    with WidgetsBindingObserver {
  late final ApkUpdateService _service = widget.service ?? ApkUpdateService();
  final _progress = ValueNotifier<(int, int?)>((0, null));
  StreamSubscription<ApkInstallEvent>? _installEvents;
  _Stage _stage = _Stage.downloading;
  _Failure? _failure;
  String? _failureDetail;
  File? _apk;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _installEvents = _service.installEvents.listen(_onInstallEvent);
    unawaited(_start());
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_installEvents?.cancel());
    _progress.dispose();
    super.dispose();
  }

  // Back from the "Install unknown apps" screen: carry on if it was granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.permission) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    if (!await _service.canRequestInstalls()) {
      _setStage(_Stage.permission);
      return;
    }
    final apk = _apk;
    if (apk != null && apk.existsSync()) return _install(apk);

    _progress.value = (0, widget.release.sizeBytes);
    _setStage(_Stage.downloading);
    final File downloaded;
    try {
      downloaded = await _service.download(
        widget.release,
        onProgress: (received, total) {
          if (!_closed) _progress.value = (received, total);
        },
        isCancelled: () => _closed,
      );
    } on ApkDownloadCancelled {
      return;
    } on ApkChecksumMismatch {
      _fail(_Failure.checksum);
      return;
    } on Object {
      _fail(_Failure.download);
      return;
    }
    if (_closed) return;
    _apk = downloaded;
    await _install(downloaded);
  }

  Future<void> _install(File apk) async {
    _setStage(_Stage.installing);
    try {
      await _service.install(apk);
    } on PlatformException catch (e) {
      _fail(_Failure.install, e.message ?? e.code);
    }
  }

  void _onInstallEvent(ApkInstallEvent event) {
    switch (event.kind) {
      case ApkInstallEventKind.pendingUserAction:
        break;
      case ApkInstallEventKind.success:
        // Android usually restarts the app before this arrives.
        _close();
      case ApkInstallEventKind.failure:
        if (event.isCancelled) {
          _fail(_Failure.cancelled);
        } else if (event.isSignatureConflict) {
          _fail(_Failure.conflict);
        } else if (event.isStorageFailure) {
          _fail(_Failure.storage);
        } else {
          _fail(_Failure.install, event.message ?? '${event.code}');
        }
    }
  }

  void _setStage(_Stage stage) {
    if (_closed || !mounted) return;
    setState(() => _stage = stage);
  }

  void _fail(_Failure failure, [String? detail]) {
    if (_closed || !mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _failure = failure;
      _failureDetail = detail;
    });
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  void _retry() {
    // A conflict or bad download won't install, so start from a fresh copy.
    if (_failure != _Failure.cancelled) _apk = null;
    unawaited(_start());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final close = AppDialogAction(label: l.close, onPressed: _close);
    return switch (_stage) {
      _Stage.permission => AppAlertDialog(
        key: const ValueKey(_Stage.permission),
        title: l.appUpdateTitle,
        message: l.appUpdatePermissionMessage,
        actions: [
          AppDialogAction(label: l.cancel, onPressed: _close),
          AppDialogAction(
            label: l.appUpdateOpenSettings,
            variant: AppButtonVariant.primary,
            autofocus: true,
            onPressed: () => unawaited(_openSettings()),
          ),
        ],
      ),
      _Stage.downloading => AppAlertDialog(
        key: const ValueKey(_Stage.downloading),
        title: l.appUpdateTitle,
        message: l.appUpdateDownloading(widget.release.version),
        content: ValueListenableBuilder<(int, int?)>(
          valueListenable: _progress,
          builder: (context, progress, _) =>
              _DownloadProgress(received: progress.$1, total: progress.$2),
        ),
        actions: [
          AppDialogAction(label: l.cancel, autofocus: true, onPressed: _close),
        ],
      ),
      _Stage.installing => AppAlertDialog(
        key: const ValueKey(_Stage.installing),
        title: l.appUpdateTitle,
        message: l.appUpdateConfirm,
        actions: [close],
      ),
      _Stage.failed => AppAlertDialog(
        key: ValueKey((_Stage.failed, _failure)),
        title: l.appUpdateTitle,
        message: _failureMessage(l),
        actions: [
          if (_failure == _Failure.conflict)
            AppDialogAction(label: l.close, autofocus: true, onPressed: _close)
          else ...[
            close,
            AppDialogAction(
              label: l.appUpdateRetry,
              variant: AppButtonVariant.primary,
              autofocus: true,
              onPressed: _retry,
            ),
          ],
        ],
      ),
    };
  }

  Future<void> _openSettings() async {
    try {
      await _service.openInstallPermissionSettings();
    } on Object {
      _fail(_Failure.install, 'settings');
    }
  }

  String _failureMessage(AppLocalizations l) => switch (_failure) {
    _Failure.download || null => l.appUpdateDownloadFailed,
    _Failure.checksum => l.appUpdateChecksumFailed,
    _Failure.cancelled => l.appUpdateCancelled,
    _Failure.conflict => l.appUpdateConflict,
    _Failure.storage => l.appUpdateStorage,
    _Failure.install => l.appUpdateInstallFailed(_failureDetail ?? ''),
  };
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.received, required this.total});

  final int received;
  final int? total;

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final total = this.total;
    final hasTotal = total != null && total > 0;
    // A progress bar has no intrinsic width, so without this the dialog
    // shrinks to its minimum while the other stages' longer text fills it.
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: hasTotal ? (received / total).clamp(0.0, 1.0) : null,
          ),
          const SizedBox(height: 8),
          Text(
            hasTotal
                ? l.appUpdateProgress(_mb(received), _mb(total))
                : l.appUpdateProgressUnknown(_mb(received)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
