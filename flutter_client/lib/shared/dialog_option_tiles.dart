import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// Below this dialog-available width (phones in portrait) the option dialogs
/// trade the roomy TV padding for the tighter mobile gutter, so the nested
/// card/tile padding doesn't squeeze the text column.
const double _compactDialogWidth = 600;

bool _isCompactDialog(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _compactDialogWidth;

/// Shared frame for the option-card dialogs (resume, clear cache): a
/// [Dialog] capped at [maxWidth], a stop-at-edge [DpadRegion] and a
/// scrollable column. On compact widths the inset and padding shrink to the
/// 16px mobile gutter; TV and tablet layouts are unchanged.
class OptionsDialog extends StatelessWidget {
  const OptionsDialog({
    super.key,
    required this.maxWidth,
    required this.children,
    this.memoryKey,
  });

  final double maxWidth;
  final List<Widget> children;
  final String? memoryKey;

  @override
  Widget build(BuildContext context) {
    final compact = _isCompactDialog(context);
    return Dialog(
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DpadRegion(
          memoryKey: memoryKey,
          verticalEdge: DpadEdgeBehavior.stop,
          horizontalEdge: DpadEdgeBehavior.stop,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 20 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Cancel / confirm row at the bottom of an [OptionsDialog]. An
/// [OverflowBar] (not a Row) so long localized labels stack instead of
/// overflowing on a phone.
class OptionsDialogActions extends StatelessWidget {
  const OptionsDialogActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return OverflowBar(
      alignment: MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 8,
      overflowSpacing: 8,
      children: children,
    );
  }
}

/// The highlighted default choice at the top of an options dialog (e.g. the
/// resume modal's "Continue" card): a filled card with a primary-colored icon.
class DialogPrimaryOption extends StatelessWidget {
  const DialogPrimaryOption({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final compact = _isCompactDialog(context);
    return DpadInkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primary,
                child: Icon(icon, color: colorScheme.onPrimary),
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A secondary choice stacked under a [DialogPrimaryOption].
class DialogActionTile extends StatelessWidget {
  const DialogActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = _isCompactDialog(context);
    return DpadFocusable(
      onSelect: onTap,
      effects: const [
        GradientBorderEffect(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.surfaceContainerHighest,
          child: Icon(icon, color: colorScheme.onSurface),
        ),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle!),
        // Inset matches DialogPrimaryOption's card padding so icons line up.
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12)
            : null,
        horizontalTitleGap: compact ? 12 : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onTap: onTap,
      ),
    );
  }
}
