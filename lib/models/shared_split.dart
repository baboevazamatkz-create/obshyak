import 'expense.dart';

/// What the flat has spent since its last income, and each person's share
/// of it.
///
/// Income is the reset, not a figure: when money comes in everyone pools
/// again, so the count starts over from the most recent income. Income
/// records are never summed into the total.
class SharedSplit {
  final double total;
  final double perPerson;

  /// Date of the most recent income, or null if there has never been one.
  final DateTime? since;

  const SharedSplit({
    required this.total,
    required this.perPerson,
    required this.since,
  });
}

/// Pure, so the rule can be tested without a Firestore stream behind it.
SharedSplit sharedSplit(List<Expense> expenses, {required int people}) {
  DateTime? since;
  for (final expense in expenses) {
    if (!expense.isIncome) continue;
    if (since == null || expense.date.isAfter(since)) since = expense.date;
  }

  var total = 0.0;
  for (final expense in expenses) {
    if (expense.isIncome) continue;
    if (since != null && !expense.date.isAfter(since)) continue;
    total += expense.amount;
  }
  return SharedSplit(
    total: total,
    perPerson: total / people,
    since: since,
  );
}
