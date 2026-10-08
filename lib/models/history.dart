import 'expense.dart';
import 'shared_split.dart';

/// One settled period: everything the flat bought and paid back between two
/// moments when nobody owed anybody.
class HistoryPeriod {
  final DateTime closedAt;

  /// Newest first, like the main list.
  final List<Expense> records;

  const HistoryPeriod({required this.closedAt, required this.records});

  DateTime get from =>
      records.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime get to =>
      records.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);

  double get sharedTotal => sharedPool(records).sharedTotal;
}

/// Groups archived records into their periods, the latest period first.
/// Records still in the open period are ignored.
List<HistoryPeriod> historyPeriods(List<Expense> expenses) {
  final byClose = <DateTime, List<Expense>>{};
  for (final expense in expenses) {
    final closedAt = expense.archivedAt;
    if (closedAt == null) continue;
    (byClose[closedAt] ??= []).add(expense);
  }
  final periods = [
    for (final entry in byClose.entries)
      HistoryPeriod(
        closedAt: entry.key,
        records: entry.value..sort((a, b) => b.date.compareTo(a.date)),
      ),
  ]..sort((a, b) => b.closedAt.compareTo(a.closedAt));
  return periods;
}
