import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/app_button.dart';

/// Brief, non-interactive indicator shown when a commercial segment was
/// auto-skipped. Self-dismisses via `PlayerScreen`'s `_flashComskipSkippedBadge`.
class ComskipSkippedBadge extends StatelessWidget {
  const ComskipSkippedBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fast_forward, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirm-to-skip control shown while playback is inside a commercial,
/// intro, or credits window — comskip's and TheIntroDB's prompts share this
/// one look. Renders as the app's `primaryInverted` [AppButton] (the same
/// hero-action pill used for the resume/play button on detail screens) so it
/// reads as a real UI control instead of a floating overlay chip, and always
/// autofocuses so a D-pad user can hit Select the instant it appears.
///
/// When [countdownShownAt]/[countdownDuration] are both provided (TheIntroDB
/// only — comskip's prompt has no auto-hide), a slim bar under the button
/// counts down to when the prompt will fade. Comskip passes neither and the
/// bar is simply omitted.
class SkipSegmentPrompt extends StatelessWidget {
  const SkipSegmentPrompt({
    super.key,
    required this.label,
    required this.onSkip,
    this.countdownShownAt,
    this.countdownDuration,
  });

  final String label;
  final VoidCallback onSkip;
  final DateTime? countdownShownAt;
  final Duration? countdownDuration;

  @override
  Widget build(BuildContext context) {
    final shownAt = countdownShownAt;
    final total = countdownDuration;
    Widget? footer;
    if (shownAt != null && total != null) {
      final remaining = total - DateTime.now().difference(shownAt);
      final startFraction = remaining.isNegative
          ? 0.0
          : remaining.inMilliseconds / total.inMilliseconds;
      footer = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 3,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: startFraction, end: 0),
            duration: remaining.isNegative ? Duration.zero : remaining,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Colors.black87),
            ),
          ),
        ),
      );
    }

    return AppButton(
      label: label,
      icon: Icons.fast_forward,
      variant: AppButtonVariant.primaryInverted,
      autofocus: true,
      onPressed: onSkip,
      footer: footer,
    );
  }
}
