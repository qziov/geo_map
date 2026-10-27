/// Result of one HTTP GET, shared by the io and web transports.
///
/// [statusCode] is `null` only when the request never completed. An HTTP error
/// status is a **successful** transport result — the caller decides whether 404
/// means "no data" or "retry".
library;

import 'dart:typed_data';

class HttpGetResult {
  const HttpGetResult({this.bytes, this.statusCode, this.error});

  const HttpGetResult.failed(String this.error)
      : bytes = null,
        statusCode = null;

  /// Response body. Empty when the request failed.
  final Uint8List? bytes;

  final int? statusCode;

  /// Transport-level failure (DNS, timeout, CORS rejection…), not an HTTP error.
  final String? error;

  bool get isOk => error == null && statusCode == 200 && bytes != null;

  @override
  String toString() =>
      'HttpGetResult(status: $statusCode, ${bytes?.length ?? 0} bytes, '
      'error: $error)';
}
