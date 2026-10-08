import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_budget.dart';

/// Remembers which flatmate this phone belongs to.
class NameStore {
  NameStore._();

  static const _key = 'my_name';

  /// Null until a name has been picked, or if the stored value is no longer
  /// one of [kRoommates].
  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    return kRoommates.contains(name) ? name : null;
  }

  static Future<void> save(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name);
  }
}
