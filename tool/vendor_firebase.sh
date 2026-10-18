#!/usr/bin/env bash
# Copies the Firebase JS SDK into web/firebase/<version>/, so the app loads
# it from its own site instead of gstatic.com: one host fewer to look up
# and connect to on every open, cached alongside the app, and started
# before the app runs (see web/index.html).
#
# The version must be the one firebase_core_web asks for;
# test/web_preload_test.dart fails when they differ. To update, run with
# the new version and delete the old folder:
#
#   tool/vendor_firebase.sh 11.9.1
set -euo pipefail
version="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/web/firebase/$version"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

(cd "$work" && npm pack "firebase@$version" --silent >/dev/null && tar xzf firebase-*.tgz)
mkdir -p "$out"
for name in app auth firestore; do
  # The CDN builds import firebase-app.js by its gstatic address; point
  # them at the copy beside them instead.
  # The source map is not shipped, so its pointer goes too.
  sed -e "s#https://www.gstatic.com/firebasejs/$version/firebase-app.js#./firebase-app.js#g" \
    -e '/^\/\/# sourceMappingURL=/d' \
    "$work/package/firebase-$name.js" > "$out/firebase-$name.js"
done
if grep -q gstatic "$out"/*.js; then
  echo "a gstatic address is left in $out" >&2
  exit 1
fi
echo "wrote $out"
