import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';

/// A single "Label: value" credit row (e.g. Director, Cast).
class MetaCreditLine {
  const MetaCreditLine({required this.label, required this.value});

  final String label;
  final String value;
}

/// Metadata column shared by movie-style detail bodies (VOD, AIOStreams
/// movies): title, chips, play/resume button + progress, synopsis, and
/// credit lines. Centralizing this is what lets a field like rating or cast
/// be added once and show up on every item detail screen.
class ItemMetaInfo extends StatelessWidget {
  const ItemMetaInfo({
    super.key,
    required this.name,
    this.clearLogoUrl,
    required this.buttonLabel,
    required this.onPlay,
    this.chips = const [],
    this.fullWidthButton = false,
    this.hidePrimaryAction = false,
    this.primaryActionFocusNode,
    this.progressValue,
    this.onStartOver,
    this.isLoading = false,
    this.plot,
    this.plotMaxWidth,
    this.plotMaxLines,
    this.credits = const [],
  });

  final String name;

  /// Transparent title logo (clearlogo). When set, it replaces the plain
  /// [name] headline at the top of the column; a load failure falls back to
  /// the text. Null keeps the text-only heading.
  final String? clearLogoUrl;
  final List<String> chips;

  /// Primary button's label. When [progressValue] is set, this is the
  /// trailing text next to the inline progress bar (e.g. "33 min left")
  /// rather than a verb like "Play" - the icon and bar already say "resume".
  final String buttonLabel;
  final VoidCallback? onPlay;
  final bool fullWidthButton;

  /// Suppresses the built-in play/resume + start-over button row. The caller
  /// renders those actions itself elsewhere (the series detail lays them on
  /// the same line as its season picker).
  final bool hidePrimaryAction;

  /// Optional external focus node for the primary play/resume button, so a
  /// sibling widget can return focus to it (the VOD wide cast row's "up").
  final FocusNode? primaryActionFocusNode;

  /// Watched fraction (0-1). When set, renders inside the primary button as
  /// an inline progress track next to [buttonLabel] instead of a plain
  /// label-only button.
  final double? progressValue;

  /// Shows a secondary "start from beginning" button next to the primary
  /// one. Only meaningful alongside [progressValue] - there's nothing to
  /// restart from when nothing has been watched yet.
  final VoidCallback? onStartOver;

  final bool isLoading;
  final String? plot;

  /// Caps the synopsis line length. Null lets it run the full column width
  /// (today's behavior); detail screens on wide layouts pass a value to keep
  /// the text to a readable measure.
  final double? plotMaxWidth;

  /// Caps the synopsis height. Null shows the full text (today's behavior);
  /// a value clamps it with a trailing ellipsis.
  final int? plotMaxLines;
  final List<MetaCreditLine> credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = AppButton(
      autofocus: true,
      focusNode: primaryActionFocusNode,
      variant: AppButtonVariant.primaryInverted,
      icon: Icons.play_arrow,
      label: buttonLabel,
      onPressed: isLoading ? null : onPlay,
      inlineProgressValue: progressValue,
    );
    final startOverCallback = onStartOver;
    final startOverButton = startOverCallback == null
        ? null
        : AppButton(
            icon: Icons.replay,
            label: AppLocalizations.of(context).playerStartFromBeginning,
            onPressed: isLoading ? null : startOverCallback,
          );
    final sizedButton = fullWidthButton
        ? SizedBox(width: double.infinity, child: button)
        : button;
    // Wrap (not Row) so the secondary button drops to its own line instead
    // of overflowing when the info column is too narrow to fit both -
    // narrow layouts, and a full-width primary button always claims the
    // whole line on its own run.
    final buttonRow = startOverButton == null
        ? sizedButton
        : Wrap(
            spacing: MediaBrowsingMetrics.itemGap,
            runSpacing: MediaBrowsingMetrics.itemGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [sizedButton, startOverButton],
          );
    final hasPlot = plot != null && plot!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleHeading(name: name, clearLogoUrl: clearLogoUrl),
        const SizedBox(height: MediaBrowsingMetrics.itemGap),
        if (chips.isNotEmpty)
          Wrap(
            spacing: MediaBrowsingMetrics.itemGap,
            runSpacing: MediaBrowsingMetrics.chipGap,
            children: chips.map((label) => MetadataChip(label: label)).toList(),
          ),
        if (!hidePrimaryAction) ...[
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
          buttonRow,
          const SizedBox(height: MediaBrowsingMetrics.pagePadding),
        ] else
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        if (isLoading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        ],
        if (hasPlot)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: plotMaxWidth ?? double.infinity,
            ),
            child: Text(
              plot!,
              maxLines: plotMaxLines,
              overflow: plotMaxLines == null ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (credits.isNotEmpty) ...[
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
          for (final credit in credits)
            MetaCreditLineText(label: credit.label, value: credit.value),
        ],
      ],
    );
  }
}

/// The heading at the top of an [ItemMetaInfo] column: a transparent title
/// logo when the server supplied one (`clearlogo`), otherwise the plain text
/// name. A logo that fails to load falls back to the same text, so the title
/// is never missing.
class _TitleHeading extends StatelessWidget {
  const _TitleHeading({required this.name, this.clearLogoUrl});

  final String name;
  final String? clearLogoUrl;

  // Caps for the transparent logo. Provider logos have wildly inconsistent
  // aspect ratios (long wordmarks vs. tall stacked marks), so both dimensions
  // are bounded and the image is only ever scaled down to fit within them.
  static const double _logoMaxHeight = 120;
  static const double _logoMaxWidth = 350;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(name, style: theme.textTheme.headlineMedium);
    final logo = clearLogoUrl?.trim();
    if (logo == null || logo.isEmpty) return text;

    final scale = FontSizeScope.scaleOf(context);
    final logoMaxHeight = _logoMaxHeight * scale;
    final logoMaxWidth = _logoMaxWidth * scale;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: logoMaxHeight,
          maxWidth: logoMaxWidth,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Image(
            image: ResizeImage(
              CachedNetworkImageProvider(
                logo,
                cacheManager: MediaImageCacheManager(),
              ),
              // Bound the decode to the display cap: a wordmark clearlogo can
              // ship at 1500px+ wide and would otherwise decode at full source
              // resolution just to be scaled down into a 350x120 (times the
              // display-size scale) box.
              width: (logoMaxWidth * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              height: (logoMaxHeight * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              policy: ResizeImagePolicy.fit,
            ),
            semanticLabel: name,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : text,
            errorBuilder: (_, _, _) => text,
          ),
        ),
      ),
    );
  }
}

/// Renders a single [MetaCreditLine] as "Label: value" rich text.
class MetaCreditLineText extends StatelessWidget {
  const MetaCreditLineText({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MediaBrowsingMetrics.chipGap),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

/// Metadata chip used across item detail screens (year, genre, rating, …).
class MetadataChip extends StatelessWidget {
  const MetadataChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}
