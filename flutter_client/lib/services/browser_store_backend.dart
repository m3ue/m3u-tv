// The web build's StoreBackend; a stub everywhere else.
export 'browser_store_backend_stub.dart'
    if (dart.library.js_interop) 'browser_store_backend_web.dart';
