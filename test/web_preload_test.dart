import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// web/index.html starts fetching the Firebase SDK before the app runs.
/// If firebase_core_web moves to another SDK version and the page does
/// not, the app would load both: the head start turns into a second
/// download. This keeps the two in step.
void main() {
  test('the page preloads the Firebase SDK version the app loads', () {
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
    final preloaded = RegExp(r'firebasejs/([0-9.]+)/')
        .allMatches(page)
        .map((m) => m.group(1))
        .toSet();
    expect(preloaded, {version});
  });
}
