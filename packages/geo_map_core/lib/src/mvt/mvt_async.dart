/// Off-thread MVT decoding.
///
/// A z0 world tile is ~34k vertices and decoding it on the UI isolate is a
/// visible hitch. MapLibre runs the parse on a worker; the Dart equivalent is
/// `Isolate.run`, which copies the pbf bytes out and the decoded tile back.
///
/// The decoded graph (`MvtTile` / `MvtLayer` / `MvtFeature` / `Vec2` / maps) is
/// plain Dart, so it is sendable without conversion. For a burst of tiles a
/// persistent worker would save the per-task spawn cost; this helper keeps the
/// call site simple until that shows up in a profile.
///
/// **The browser has no isolates.** `Isolate.run` exists in the web SDK but
/// throws `UnsupportedError` at runtime, which looks exactly like a failed tile
/// fetch (HTTP 200, tile never drawn). So on web the decode runs inline: the
/// browser is single-threaded anyway, and a z0 tile parses in a few
/// milliseconds, which is cheaper than the round trip would be.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'mvt.dart';

/// True when compiled for the browser (`dart:js_interop` is web-only).
///
/// Same test Flutter uses for `kIsWeb`; a const, so the io branch disappears
/// from the web bundle.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Decodes [bytes] on a worker isolate, or inline on web.
Future<MvtTile> decodeMvtTileAsync(Uint8List bytes) => _isWeb
    ? Future<MvtTile>.value(decodeMvtTile(bytes))
    : Isolate.run(() => decodeMvtTile(bytes));
