import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every character in a string the app shows must be in the bundled font.
/// One that is not makes the browser fetch a fallback font from the
/// internet, or draw an empty box where the network or the browser will
/// not -- in-app browsers, phones on a poor connection.
///
/// The font's coverage is read from its cmap table directly, so this needs
/// nothing beyond the font files themselves.
void main() {
  Set<int> cmapOf(String path) {
    final data = File(path).readAsBytesSync();
    int u16(int o) => (data[o] << 8) | data[o + 1];
    int u32(int o) => (u16(o) << 16) | u16(o + 2);
    final tables = u16(4);
    var cmap = -1;
    for (var i = 0; i < tables; i++) {
      final rec = 12 + 16 * i;
      if (String.fromCharCodes(data.sublist(rec, rec + 4)) == 'cmap') {
        cmap = u32(rec + 8);
      }
    }
    final codes = <int>{};
    final subtables = u16(cmap + 2);
    for (var i = 0; i < subtables; i++) {
      final offset = cmap + u32(cmap + 4 + 8 * i + 4);
      final format = u16(offset);
      if (format == 4) {
        final segs = u16(offset + 6) ~/ 2;
        for (var s = 0; s < segs; s++) {
          final end = u16(offset + 14 + 2 * s);
          final start = u16(offset + 16 + 2 * segs + 2 * s);
          for (var c = start; c <= end && c != 0xFFFF; c++) {
            codes.add(c);
          }
        }
      } else if (format == 12) {
        final groups = u32(offset + 12);
        for (var g = 0; g < groups; g++) {
          final rec = offset + 16 + 12 * g;
          for (var c = u32(rec); c <= u32(rec + 4); c++) {
            codes.add(c);
          }
        }
      }
    }
    return codes;
  }

  test('every character the app shows is in the bundled font', () {
    final font = cmapOf('fonts/Onest-Regular.ttf');
    // The reader itself: the tenge sign is there, the two-way arrow that
    // used to slip through is not.
    expect(font.contains(0x20B8), isTrue);
    expect(font.contains(0x21C4), isFalse);
    final shown = <int>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final m in RegExp(r"'((?:[^'\\]|\\.)*)'").allMatches(source)) {
        shown.addAll(m.group(1)!.runes.where((r) => r > 127));
      }
    }
    final missing = shown.where((r) => !font.contains(r)).toList()..sort();
    expect(
      missing.map((r) => '${String.fromCharCode(r)} U+${r.toRadixString(16)}'),
      isEmpty,
    );
  });
}
