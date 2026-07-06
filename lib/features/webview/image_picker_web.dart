// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Pop a native browser "choose file" dialog for images and return the
/// selected file as a raw base64 string (no `data:` prefix).
///
/// Returns null if the user cancelled.
Future<String?> pickImageAsBase64() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    // Explicit MIME types + extensions so every mobile / desktop
    // browser recognises what we accept — some Android browsers ignore
    // the generic `image/*` filter and won't show images in the picker
    // until they see the extensions too.
    ..accept =
        'image/jpeg,image/png,image/webp,image/gif,image/bmp,image/heic,image/heif,'
        '.jpg,.jpeg,.png,.webp,.gif,.bmp,.heic,.heif';
  final completer = Completer<String?>();
  input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    // Read as ArrayBuffer → typed bytes → base64.
    final buffer = await file.arrayBuffer().toDart;
    final bytes = Uint8List.view(buffer.toDart);
    completer.complete(base64Encode(bytes));
  });
  // Some browsers require the input to be in the DOM to click.
  input.style.display = 'none';
  web.document.body?.appendChild(input);
  input.click();
  final result = await completer.future;
  input.remove();
  return result;
}
