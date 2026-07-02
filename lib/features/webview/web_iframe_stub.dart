import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Native/mobile placeholder. Real embedding happens through
/// `webview_flutter` in `WebActionPage._NativeWebView` — this stub only
/// exists so the shared import in `WebActionPage` resolves on native.
class WebIframe extends StatelessWidget {
  const WebIframe({super.key, required this.url, this.pointerEnabled});
  final String url;
  final ValueListenable<bool>? pointerEnabled;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
