import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// web/index.html loads the Firebase SDK from the site's own copy before
/// the app runs. If firebase_core_web moves to another SDK version and the
/// copy does not, the app would run against an SDK it was not built for.
/// This keeps the two in step: run tool/vendor_firebase.sh on an update.
void main() {
  test('the page loads the Firebase SDK version the app expects', () {
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final package = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'firebase_core_web');
    final root = Uri.parse(package['rootUri'] as String);
    final dir = root.isAbsolute
        ? Directory.fromUri(root)
        : Directory.fromUri(
            File('.dart_tool/package_config.json')
                .absolute
                .uri
                .resolveUri(root),
          );
    final source = File('${dir.path}/lib/src/firebase_sdk_version.dart')
        .readAsStringSync();
    final version = RegExp(r"supportedFirebaseJsSdkVersion = '([^']+)'")
        .firstMatch(source)!
        .group(1)!;

    final page = File('web/index.html').readAsStringSync();
    final loaded = RegExp(r'\./firebase/([0-9.]+)/')
        .allMatches(page)
        .map((m) => m.group(1))
        .toSet();
    expect(loaded, {version});
    for (final name in ['app', 'auth', 'firestore']) {
      final file = File('web/firebase/$version/firebase-$name.js');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(file.readAsStringSync(), isNot(contains('gstatic.com')),
          reason: '${file.path} must import its neighbours, not the CDN');
    }
    expect(page, isNot(contains('gstatic.com/firebasejs')));
  });
}
