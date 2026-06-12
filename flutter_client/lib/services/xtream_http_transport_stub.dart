import 'xtream_service.dart';

XtreamTransport createDefaultXtreamTransport() {
  return (XtreamRequest request) {
    throw UnsupportedError(
      'XtreamService default HTTP transport is unavailable on this platform.',
    );
  };
}
