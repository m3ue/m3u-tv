import 'package:m3u_tv/shared/host_platform.dart';

/// The editor origin to lock the Server URL field to when this web build is
/// served by the editor itself at /m3u-tv/ (see m3u-editor's routes/web.php).
/// Null when not applicable: every native build, and a web build served from
/// anywhere else (e.g. `flutter run -d chrome` during development), where the
/// server URL should stay freely editable.
String? get embeddedEditorOrigin {
  if (!HostPlatform.isWeb) return null;
  final uri = Uri.base;
  if (uri.path != '/m3u-tv' && !uri.path.startsWith('/m3u-tv/')) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.origin;
}
