/// Display formatters shared by every feature screen, so a runtime, rating or
/// file size reads the same wherever it shows up.
library;

/// Trims [value] and returns it, or null when it is null or blank. Optional
/// strings from Xtream/TMDB payloads often arrive as "" rather than null.
String? nullIfBlank(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

/// Renders a runtime as "2h 15m", "2h" or "45m" (seconds are dropped).
String formatRuntime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  return '${minutes}m';
}

/// Parses the runtime text the Xtream payloads carry ("01:40:09", "2h 50m",
/// "50m", "95 min", or bare minutes) into a [Duration]. Null when it can't
/// tell.
Duration? parseRuntimeText(String? text) {
  final value = text?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  if (value.contains(':')) {
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.any((part) => part == null)) return null;
    final numbers = parts.cast<int>();
    final duration = switch (numbers.length) {
      3 => Duration(
        hours: numbers[0],
        minutes: numbers[1],
        seconds: numbers[2],
      ),
      2 => Duration(hours: numbers[0], minutes: numbers[1]),
      _ => null,
    };
    return duration == null || duration <= Duration.zero ? null : duration;
  }
  final minutesOnly = int.tryParse(value);
  if (minutesOnly != null) {
    return minutesOnly > 0 ? Duration(minutes: minutesOnly) : null;
  }
  final hours = RegExp(r'(\d+)\s*h').firstMatch(value);
  final minutes = RegExp(r'(\d+)\s*m').firstMatch(value);
  if (hours == null && minutes == null) return null;
  final duration = Duration(
    hours: hours == null ? 0 : int.parse(hours.group(1)!),
    minutes: minutes == null ? 0 : int.parse(minutes.group(1)!),
  );
  return duration > Duration.zero ? duration : null;
}

/// Normalises free-form runtime text (see [parseRuntimeText]) to the
/// [formatRuntime] style, keeping the trimmed original when it can't be
/// parsed. Null when [text] is blank.
String? formatRuntimeText(String? text) {
  final value = nullIfBlank(text);
  if (value == null) return null;
  final duration = parseRuntimeText(value);
  return duration == null ? value : formatRuntime(duration);
}

/// Renders a byte count as "1.5 GB" (at or above 1 GiB) or "342 MB".
String formatBytes(int bytes) {
  final gib = bytes / (1024 * 1024 * 1024);
  if (gib >= 1) return '${gib.toStringAsFixed(1)} GB';
  final mib = bytes / (1024 * 1024);
  return '${mib.toStringAsFixed(0)} MB';
}

/// Renders a score as "★ 7.5", optionally suffixed with its [source]
/// ("★ 7.5 TMDB").
String formatRating(num rating, {String? source}) {
  final label = '★ ${rating.toStringAsFixed(1)}';
  final suffix = nullIfBlank(source);
  return suffix == null ? label : '$label ${suffix.toUpperCase()}';
}

/// [formatRating] for ratings that arrive as text ("7.5"). Non-numeric text
/// is shown as-is after the star; null when [rating] is blank.
String? formatRatingText(String? rating) {
  final value = nullIfBlank(rating);
  if (value == null) return null;
  final parsed = num.tryParse(value);
  return parsed == null ? '★ $value' : formatRating(parsed);
}
