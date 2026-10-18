{{flutter_js}}
{{flutter_build_config}}

// Loaded without Flutter's service worker. That worker served the copy of
// the app it had cached first and fetched the new one only in the
// background, so after every deploy phones kept showing the previous
// version until a second reload. Flutter has deprecated it as well.
//
// The app starts once the Firebase SDK that index.html loads is in place,
// so firebase_core_web finds it rather than fetching its own copy from
// gstatic.com. If it has not arrived in a few seconds -- a failed request,
// say -- the app starts anyway and firebase_core_web fetches it as before.
(function () {
  var started = false;
  function start() {
    if (started) return;
    started = true;
    _flutter.loader.load();
  }
  if (window.firebase_core) {
    start();
  } else {
    window.addEventListener('firebase-ready', start, { once: true });
    setTimeout(start, 8000);
  }
})();
