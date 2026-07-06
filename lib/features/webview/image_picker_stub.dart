/// Native placeholder — the real picker lives in
/// `image_picker_web.dart` behind a `dart.library.js_interop` guard.
/// Returns null so callers gracefully skip on mobile until an
/// image_picker plugin path is wired up.
Future<String?> pickImageAsBase64() async => null;
