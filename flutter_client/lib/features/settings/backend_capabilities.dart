/// Backend capabilities and transcode server status for the diagnostics screen.
class BackendCapabilities {
  const BackendCapabilities({
    required this.m3uEditorVersion,
    required this.features,
    required this.transcodeAvailable,
  });

  final String m3uEditorVersion;
  final List<String> features;
  final bool transcodeAvailable;
}
