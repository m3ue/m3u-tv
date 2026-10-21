// The SQLite executor behind CatalogDatabase: native sqlite3 via FFI, or
// drift's WebAssembly build in a browser, where dart:ffi doesn't exist.
export 'catalog_connection_native.dart'
    if (dart.library.js_interop) 'catalog_connection_web.dart';
