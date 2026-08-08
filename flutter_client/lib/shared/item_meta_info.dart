import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

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
    required this.buttonLabel,
    required this.onPlay,
    this.chips = const [],
    this.fullWidthButton = false,
    this.progressValue,
    this.isLoading = false,
    this.plot,
    this.credits = const [],
  });

  final String name;
  final List<String> chips;
  final String buttonLabel;
  final VoidCallback? onPlay;
  final bool fullWidthButton;
  final double? progressValue;
  final bool isLoading;
  final String? plot;
  final List<MetaCreditLine> credits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = AppButton(
      autofocus: true,
      variant: AppButtonVariant.primaryInverted,
      icon: Icons.play_arrow,
      label: buttonLabel,
      onPressed: isLoading ? null : onPlay,
    );
    final hasPlot = plot != null && plot!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.headlineMedium),
        const SizedBox(height: MediaBrowsingMetrics.itemGap),
        if (chips.isNotEmpty)
          Wrap(
            spacing: MediaBrowsingMetrics.itemGap,
            runSpacing: MediaBrowsingMetrics.chipGap,
            children: chips.map((label) => MetadataChip(label: label)).toList(),
          ),
        const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        if (fullWidthButton)
          SizedBox(width: double.infinity, child: button)
        else
          button,
        if (progressValue != null) ...[
          const SizedBox(height: MediaBrowsingMetrics.chipGap),
          LinearProgressIndicator(value: progressValue, minHeight: 4),
        ],
        const SizedBox(height: MediaBrowsingMetrics.pagePadding),
        if (isLoading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        ],
        if (hasPlot)
          Text(
            plot!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
