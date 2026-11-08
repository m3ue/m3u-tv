import 'package:dpad/dpad.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

enum SyncOffsetKind { audio, subtitle }

/// The farthest an offset can go either way.
const Duration maxSyncOffset = Duration(seconds: 60);

/// The slider's reach; the step buttons go on to [maxSyncOffset].
const Duration _sliderReach = Duration(seconds: 10);

extension SyncOffsetSteps on SyncOffsetKind {
  /// Audio is corrected in lip-sync sized steps, subtitles in larger ones.
  Duration get fineStep => this == SyncOffsetKind.audio
      ? const Duration(milliseconds: 10)
      : const Duration(milliseconds: 50);

  Duration get coarseStep => this == SyncOffsetKind.audio
      ? const Duration(milliseconds: 100)
      : const Duration(seconds: 1);
}

/// "+120 ms", "-1.5 s", "0 ms".
String formatSyncOffset(AppLocalizations l, Duration offset) {
  final ms = offset.inMilliseconds;
  final sign = ms > 0
      ? '+'
      : ms < 0
      ? '-'
      : '';
  final magnitude = ms.abs();
  if (magnitude < 1000) return l.playerSyncMilliseconds('$sign$magnitude');
  var seconds = (magnitude / 1000).toStringAsFixed(2);
  seconds = seconds.replaceFirst(RegExp(r'\.?0+$'), '');
  return l.playerSyncSeconds('$sign$seconds');
}

/// Opens the compact sync bar across the top of the player, over the video
/// so the change can be seen and heard as it's made (same idea as Plezy's).
/// [onChanged] gets every new offset; the bar closes with Back or Done.
Future<void> showSyncOffsetBar(
  BuildContext context, {
  required SyncOffsetKind kind,
  required Duration initial,
  required ValueChanged<Duration> onChanged,
}) => showAppDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (_) =>
      SyncOffsetBar(kind: kind, initial: initial, onChanged: onChanged),
);

class SyncOffsetBar extends StatefulWidget {
  const SyncOffsetBar({
    super.key,
    required this.kind,
    required this.initial,
    required this.onChanged,
  });

  final SyncOffsetKind kind;
  final Duration initial;
  final ValueChanged<Duration> onChanged;

  @override
  State<SyncOffsetBar> createState() => _SyncOffsetBarState();
}

class _SyncOffsetBarState extends State<SyncOffsetBar> {
  late Duration _offset = widget.initial;

  // The slider is for touch and mouse. On a remote it would take Left/Right
  // away from moving between the buttons, so D-pad focus skips it.
  final FocusNode _sliderFocus = FocusNode(
    debugLabel: 'player/sync-slider',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void dispose() {
    _sliderFocus.dispose();
    super.dispose();
  }

  void _set(Duration offset) {
    final clamped = Duration(
      milliseconds: offset.inMilliseconds.clamp(
        -maxSyncOffset.inMilliseconds,
        maxSyncOffset.inMilliseconds,
      ),
    );
    if (clamped == _offset) return;
    setState(() => _offset = clamped);
    widget.onChanged(clamped);
  }

  void _step(Duration step) => _set(_offset + step);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final kind = widget.kind;
    final isAudio = kind == SyncOffsetKind.audio;
    final reachMs = _sliderReach.inMilliseconds.toDouble();
    final fineMs = kind.fineStep.inMilliseconds;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(16 * scale),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 820 * scale),
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh.withValues(
                alpha: 0.94,
              ),
              borderRadius: BorderRadius.circular(16),
              elevation: 6,
              child: Padding(
                padding: EdgeInsets.all(16 * scale),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isAudio ? Icons.graphic_eq : Icons.subtitles,
                          size: 22 * scale,
                        ),
                        SizedBox(width: 10 * scale),
                        Expanded(
                          child: Text(
                            isAudio ? l.playerAudioSync : l.playerSubtitleSync,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          formatSyncOffset(l, _offset),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      focusNode: _sliderFocus,
                      value: _offset.inMilliseconds.toDouble().clamp(
                        -reachMs,
                        reachMs,
                      ),
                      min: -reachMs,
                      max: reachMs,
                      divisions: (2 * reachMs / fineMs).round(),
                      onChanged: (value) =>
                          _set(Duration(milliseconds: value.round())),
                    ),
                    DpadRegion(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8 * scale,
                        runSpacing: 8 * scale,
                        children: [
                          AppButton(
                            label: formatSyncOffset(l, -kind.coarseStep),
                            onPressed: () => _step(-kind.coarseStep),
                          ),
                          AppButton(
                            label: formatSyncOffset(l, -kind.fineStep),
                            onPressed: () => _step(-kind.fineStep),
                          ),
                          AppButton(
                            label: formatSyncOffset(l, kind.fineStep),
                            autofocus: true,
                            onPressed: () => _step(kind.fineStep),
                          ),
                          AppButton(
                            label: formatSyncOffset(l, kind.coarseStep),
                            onPressed: () => _step(kind.coarseStep),
                          ),
                          AppButton(
                            icon: Icons.restart_alt,
                            label: l.playerSyncReset,
                            onPressed: _offset == Duration.zero
                                ? null
                                : () => _set(Duration.zero),
                          ),
                          AppButton(
                            icon: Icons.check,
                            label: l.playerSyncDone,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      isAudio
                          ? l.playerAudioSyncHint
                          : l.playerSubtitleSyncHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
