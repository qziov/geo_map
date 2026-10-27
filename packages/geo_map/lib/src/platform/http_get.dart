/// Platform-neutral HTTP GET for tile and GeoJSON transport.
///
/// `dart:io` does not exist in a browser, and a single `import 'dart:io'`
/// anywhere in the export graph makes the whole package uncompilable for web.
/// So every transport use goes through this one function, with a conditional
/// implementation:
///
/// * `http_get_io.dart` — one shared `HttpClient` (keep-alive, timeouts, a
///   per-host connection cap);
/// * `http_get_web.dart` — `HttpRequest` over XHR.
///
/// The contract is deliberately smaller than either: bytes, status code, error.
/// Anything else (404-vs-network split, empty-body handling) stays in the
/// caller, where it is testable without a socket.
library;

export 'http_get_io.dart'
    if (dart.library.js_interop) 'http_get_web.dart';
