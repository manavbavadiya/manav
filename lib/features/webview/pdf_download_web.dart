// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Save the PDF at [url] to the device without opening a new tab.
///
/// Mobile browsers largely ignore the plain `download` attribute when
/// `target="_blank"` is present — the new tab opens, the PDF loads
/// inside it, and there's no "save" prompt. Fetching the bytes and
/// handing back a `blob:` URL forces every browser (desktop and
/// mobile) to treat the click as a direct download.
Future<void> downloadPdf(String url, {String? filename}) async {
  try {
    final resp = await web.window.fetch(url.toJS).toDart;
    if (resp.status < 200 || resp.status >= 300) {
      _fallbackClick(url, filename);
      return;
    }
    final buffer = await resp.arrayBuffer().toDart;
    final bytes = Uint8List.view(buffer.toDart);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final blobUrl = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = blobUrl
      ..download = filename ?? 'ID_Card.pdf'
      ..style.display = 'none';
    web.document.body?.appendChild(a);
    a.click();
    a.remove();
    // Give the browser a beat to start the download, then release the
    // blob URL so we don't leak memory.
    Future<void>.delayed(const Duration(seconds: 5), () {
      web.URL.revokeObjectURL(blobUrl);
    });
  } catch (_) {
    _fallbackClick(url, filename);
  }
}

/// Same-origin anchor click without opening a new tab.
void _fallbackClick(String url, String? filename) {
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename ?? 'ID_Card.pdf'
    ..style.display = 'none';
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
}
