import 'package:m3u_tv/services/xtream_service.dart';

XtreamTransport createDefaultXtreamTransport() {
  return (XtreamRequest request) {
    throw UnsupportedError(
      'XtreamService default HTTP transport is unavailable on this platform.',
    );
  };
}
