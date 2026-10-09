{{flutter_js}}
{{flutter_build_config}}

// Loaded without Flutter's service worker. That worker served the copy of
// the app it had cached first and fetched the new one only in the
// background, so after every deploy phones kept showing the previous
// version until a second reload. Flutter has deprecated it as well.
_flutter.loader.load();
