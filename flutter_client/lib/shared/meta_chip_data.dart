import 'package:flutter/foundation.dart';
import 'package:m3u_tv/shared/formatters.dart';

/// What a metadata chip carries, so `MetadataChip` can style each kind
/// (a star for ratings, a clock for runtime, a boxed certification) instead
/// of rendering every value as the same neutral pill.
enum MetaChipKind {
  plain,
  year,
  certification,
  rating,
  runtime,
  genre,
  seasons,
  format,
  highlight,
  recording,
  schedule,
  channel,
}

/// A single metadata chip's value. Kept free of widget imports so models
/// like `HomeSpotlight` can build chip lists without pulling in Material.
@immutable
class MetaChipData {
  const MetaChipData(this.label, {this.kind = MetaChipKind.plain, this.detail});

  const MetaChipData.year(this.label) : kind = MetaChipKind.year, detail = null;
  const MetaChipData.certification(this.label)
    : kind = MetaChipKind.certification,
      detail = null;
  const MetaChipData.runtime(this.label)
    : kind = MetaChipKind.runtime,
      detail = null;
  const MetaChipData.genre(this.label)
    : kind = MetaChipKind.genre,
      detail = null;
  const MetaChipData.seasons(this.label)
    : kind = MetaChipKind.seasons,
      detail = null;
  const MetaChipData.format(this.label)
    : kind = MetaChipKind.format,
      detail = null;
  const MetaChipData.highlight(this.label)
    : kind = MetaChipKind.highlight,
      detail = null;
  const MetaChipData.recording(this.label)
    : kind = MetaChipKind.recording,
      detail = null;
  const MetaChipData.schedule(this.label)
    : kind = MetaChipKind.schedule,
      detail = null;
  const MetaChipData.channel(this.label)
    : kind = MetaChipKind.channel,
      detail = null;

  /// A score as "7.5" (the chip draws the star), with an optional [source]
  /// ("TMDB") shown as muted trailing text.
  MetaChipData.rating(num value, {String? source})
    : label = value.toStringAsFixed(1),
      kind = MetaChipKind.rating,
      detail = nullIfBlank(source)?.toUpperCase();

  /// [MetaChipData.rating] for scores that arrive as text ("7.5").
  /// Non-numeric text is shown as-is; null when [rating] is blank.
  static MetaChipData? ratingText(String? rating) {
    final value = nullIfBlank(rating);
    if (value == null) return null;
    final parsed = num.tryParse(value);
    return parsed == null
        ? MetaChipData(value, kind: MetaChipKind.rating)
        : MetaChipData.rating(parsed);
  }

  /// [formatRuntimeText] as a runtime chip; null when there's no runtime.
  static MetaChipData? runtimeText(String? text) {
    final value = formatRuntimeText(text);
    return value == null ? null : MetaChipData.runtime(value);
  }

  final String label;
  final MetaChipKind kind;

  /// Muted trailing text after [label] (a rating's source).
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is MetaChipData &&
      other.label == label &&
      other.kind == kind &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(label, kind, detail);

  @override
  String toString() => detail == null ? label : '$label $detail';
}
