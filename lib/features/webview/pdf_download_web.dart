// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:web/web.dart' as web;

/// Open [url] in a new browser tab / trigger the download. Uses an
/// anchor element with `target=_blank` and an explicit `download`
/// attribute so PDFs land as a file when the browser is configured
/// that way, or open in the built-in PDF viewer otherwise.
void downloadPdf(String url, {String? filename}) {
  final a = web.HTMLAnchorElement()
    ..href = url
    ..target = '_blank'
    ..rel = 'noopener'
    ..download = filename ?? '';
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
}
