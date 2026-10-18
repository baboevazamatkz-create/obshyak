import 'dart:async';

/// Whether Firebase is started and this phone signed in.
///
/// The app no longer waits for that before showing anything: the screens
/// open at once on the figures this phone saw last (see [BudgetCache]),
/// and everything that reads or writes the budget waits here instead.
class Connection {
  Connection._();

  static final Completer<void> _ready = Completer<void>();

  /// Completes on the first successful connection, and stays complete.
  static Future<void> get ready => _ready.future;

  static bool get isReady => _ready.isCompleted;

  static void markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }
}
