/// `dart:io` transport: one shared keep-alive `HttpClient`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:geo_map_core/geo_map_core.dart' show GeoEngineTuning;

import 'http_get_result.dart';

export 'http_get_result.dart';

HttpClient? _client;

HttpClient get _sharedClient => _client ??= HttpClient()
  ..connectionTimeout =
      const Duration(milliseconds: GeoEngineTuning.requestTimeoutMs)
  ..idleTimeout = const Duration(seconds: 30)
  ..maxConnectionsPerHost = GeoEngineTuning.maxParallelRequests;

/// GET [uri].
///
/// A fresh `HttpClient` per tile would pay a TCP connection *and* a TLS
/// handshake each time — at z12 that is hundreds of handshakes and a visible
/// stall, so the client is shared and kept alive.
Future<HttpGetResult> httpGetBytes(
  Uri uri, {
  Map<String, String> headers = const {},
  String? userAgent,
}) async {
  try {
    final request = await _sharedClient.getUrl(uri);
    if (userAgent != null) {
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(
          const Duration(milliseconds: GeoEngineTuning.bodyTimeoutMs),
        );
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    final bytes = chunks.isEmpty
        ? Uint8List(0)
        : Uint8List.fromList(chunks.expand((c) => c).toList(growable: false));
    return HttpGetResult(bytes: bytes, statusCode: response.statusCode);
  } catch (e) {
    return HttpGetResult.failed('$e');
  }
}
