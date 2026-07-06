/// Native placeholder — real download happens through [WebActionPage]
/// on native (webview_flutter) once a real implementation is wired up.
/// For now we just no-op; the caller falls back to opening a PDF viewer.
Future<void> downloadPdf(String url, {String? filename}) async {}
