/// Browser transport: `HttpRequest` over XHR.
///
/// The browser owns the connection pool, the keep-alive sockets and the
/// timeout policy, so this implementation is thin on purpose. Two differences
/// from the io version matter:
///
/// * the `User-Agent` header is forbidden — the browser sets it, and trying to
///   pass it makes some browsers reject the whole request;
/// * a cross-origin request only succeeds if the server sends CORS headers
///   (`Access-Control-Allow-Origin`). That is why the demos use
///   `demotiles.maplibre.org`, which does.
library;

// `dart:html` is deprecated in favour of `package:web`, but it needs no extra
// dependency and the repo already sets `deprecated_member_use: ignore`.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'http_get_result.dart';

export 'http_get_result.dart';

Future<HttpGetResult> httpGetBytes(
  Uri uri, {
  Map<String, String> headers = const {},
  String? userAgent,
}) async {
  try {
    final request = await html.HttpRequest.request(
      uri.toString(),
      requestHeaders: headers.isEmpty ? null : headers,
      responseType: 'arraybuffer',
    );
    final body = request.response;
    final bytes = switch (body) {
      ByteBuffer buffer => buffer.asUint8List(),
      List<int> list => Uint8List.fromList(list),
      _ => Uint8List(0),
    };
    return HttpGetResult(bytes: bytes, statusCode: request.status);
  } catch (e) {
    // Network failure, CORS rejection or timeout all land here.
    return HttpGetResult.failed('$e');
  }
}
