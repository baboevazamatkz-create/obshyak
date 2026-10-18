import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/away.dart';
import '../models/expense.dart';

/// The open period as this phone last saw it from the server, kept so the
/// app can open on real figures straight away and catch up once it has
/// connected, instead of showing a spinner for the length of the
/// connection. Only ever shown, never acted on.
class BudgetCache {
  BudgetCache._();

  static const _key = 'budget_cache_v1';

  static Future<({List<Expense> expenses, AwayBook away})?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final json = _revive(jsonDecode(raw)) as Map<String, dynamic>;
      return (
        expenses: [
          for (final e in json['expenses'] as List)
            Expense.fromJson(e as Map<String, dynamic>),
        ],
        away: AwayBook.fromJson(json['away'] as Map<String, dynamic>?),
      );
    } catch (_) {
      // A cache that cannot be read is no cache: the app simply waits for
      // the server as it used to.
      return null;
    }
  }

  static Future<void> save(List<Expense> open, AwayBook away) async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'expenses': [for (final e in open) e.toJson()],
      'away': {
        for (final entry in away.requests.entries)
          entry.key: entry.value.toJson(),
      },
    };
    await prefs.setString(_key, jsonEncode(_flatten(json)));
  }

  /// Firestore timestamps written as `{"$ts": millis}`, which JSON can hold.
  static Object? _flatten(Object? value) => switch (value) {
        Timestamp t => {r'$ts': t.millisecondsSinceEpoch},
        Map m => {
            for (final e in m.entries) e.key as String: _flatten(e.value)
          },
        List l => [for (final v in l) _flatten(v)],
        _ => value,
      };

  static Object? _revive(Object? value) => switch (value) {
        Map m when m.length == 1 && m[r'$ts'] is int =>
          Timestamp.fromMillisecondsSinceEpoch(m[r'$ts'] as int),
        Map m => <String, dynamic>{
            for (final e in m.entries) e.key as String: _revive(e.value),
          },
        List l => [for (final v in l) _revive(v)],
        _ => value,
      };
}
