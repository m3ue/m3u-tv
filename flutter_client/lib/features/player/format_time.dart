/// Formats a Duration as a human-readable time string.
///
/// - Durations under 1 hour: `M:SS` (e.g. `5:30`, `0:05`)
/// - Durations 1 hour or more: `H:MM:SS` (e.g. `1:30:00`)
String formatTime(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final minutesPadded = minutes.toString().padLeft(2, '0');
  final secondsPadded = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minutesPadded:$secondsPadded';
  }
  return '$minutes:$secondsPadded';
}
