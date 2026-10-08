import 'expense.dart';
import 'shared_budget.dart';

/// One flatmate's side of the pool: what they put in and what they spent.
class PoolPerson {
  final String name;
  final double contributed;
  final double spent;

  const PoolPerson({
    required this.name,
    required this.contributed,
    required this.spent,
  });
}

/// The shared pool for the current period.
///
/// A period opens at the most recent income shared with everyone: that is
/// the moment the flat pools money again. Income kept for one person, and
/// every expense, count from there on; anything before it is history.
class SharedPool {
  /// One entry per flatmate in [kRoommates] order, even those who have
  /// put nothing in.
  final List<PoolPerson> people;

  /// Date of the shared income that opened this period, or null when no
  /// shared income exists yet and the whole history counts.
  final DateTime? since;

  /// Every expense in the period, including ones whose author is unknown.
  final double spentTotal;

  const SharedPool({
    required this.people,
    required this.since,
    required this.spentTotal,
  });

  double get contributedTotal =>
      people.fold(0, (sum, person) => sum + person.contributed);

  /// What is left in the pool. Negative when the flat has spent more than
  /// it put in.
  double get remaining => contributedTotal - spentTotal;

  /// Each person's fair share of what was spent.
  double get perPerson => spentTotal / kRoommateCount;

  /// The people to mark as having put in the most. Empty when nobody has
  /// put anything in, or when everyone who did put in the same amount --
  /// there is no bigger contribution to point at then.
  List<String> get biggestContributors {
    final payers = people.where((p) => p.contributed > 0).toList();
    if (payers.isEmpty) return const [];
    final top =
        payers.map((p) => p.contributed).reduce((a, b) => a > b ? a : b);
    final leaders = payers.where((p) => p.contributed == top).toList();
    if (leaders.length == payers.length && payers.length > 1) return const [];
    return leaders.map((p) => p.name).toList();
  }
}

/// Pure, so the rule can be tested without a Firestore stream behind it.
SharedPool sharedPool(List<Expense> expenses) {
  Expense? anchor;
  for (final expense in expenses) {
    if (!expense.isIncome || !expense.shared) continue;
    if (anchor == null || expense.date.isAfter(anchor.date)) anchor = expense;
  }

  final opening = anchor;
  bool inPeriod(Expense expense) =>
      opening == null ||
      expense.id == opening.id ||
      expense.date.isAfter(opening.date);

  final contributed = {for (final name in kRoommates) name: 0.0};
  final spent = {for (final name in kRoommates) name: 0.0};
  var spentTotal = 0.0;

  for (final expense in expenses) {
    if (!inPeriod(expense)) continue;
    if (expense.isIncome) {
      if (expense.shared) {
        for (final name in kRoommates) {
          contributed[name] =
              contributed[name]! + expense.amount / kRoommateCount;
        }
      } else if (contributed.containsKey(expense.author)) {
        contributed[expense.author] =
            contributed[expense.author]! + expense.amount;
      }
    } else {
      spentTotal += expense.amount;
      if (spent.containsKey(expense.author)) {
        spent[expense.author] = spent[expense.author]! + expense.amount;
      }
    }
  }

  return SharedPool(
    people: [
      for (final name in kRoommates)
        PoolPerson(
          name: name,
          contributed: contributed[name]!,
          spent: spent[name]!,
        ),
    ],
    since: anchor?.date,
    spentTotal: spentTotal,
  );
}
