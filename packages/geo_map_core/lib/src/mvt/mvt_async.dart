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
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'mvt.dart';

/// Decodes [bytes] on a worker isolate.
Future<MvtTile> decodeMvtTileAsync(Uint8List bytes) =>
    Isolate.run(() => decodeMvtTile(bytes));
