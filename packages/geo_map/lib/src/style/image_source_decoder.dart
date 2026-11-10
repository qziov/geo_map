/// Bridge between Flutter [ImageProvider]s and style-layer [ImageSource]s.
///
/// Business image layers (radar / satellite / WAFS) hold an [ImageProvider]
/// (FileImage / MemoryImage / AssetImage), but a `raster` style layer renders
/// from a concrete [ui.Image] registered in [GeoStyleController.imageSources].
/// [decodeImageProvider] resolves the provider to that bitmap so it can be
/// registered via `addImageSource` / `updateImageSource`. The provider's own
/// decode cache is reused when the same frame is requested again.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Resolve any [ImageProvider] to a decoded [ui.Image].
///
/// The returned image is owned by the provider's cache for the common provider
/// types; callers should not dispose it. When a time-animated layer swaps its
/// frame, re-calling this with the next provider returns the (cached) decode
/// for that frame.
Future<ui.Image> decodeImageProvider(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool synchronousCall) {
      completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stackTrace) {
      completer.completeError(error, stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
