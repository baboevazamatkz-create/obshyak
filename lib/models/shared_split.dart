import 'expense.dart';
import 'fines.dart';
import 'shared_budget.dart';

/// One flatmate's standing in the flat's shared spending.
class PoolPerson {
  final String name;

  /// What they paid for the flat: their receipts minus the personal parts.
  final double paid;

  /// Money they paid back to others, and money others paid back to them.
  final double sent;
  final double received;

  /// Positive: the others owe them this much. Negative: they owe it.
  final double balance;

  /// What they have actually spent on the flat: their purchases, plus debts
  /// they paid back, minus what was paid back to them.
  double get spent => paid + sent - received;

  const PoolPerson({
    required this.name,
    required this.paid,
    required this.sent,
    required this.received,
    required this.balance,
  });
}

/// One transfer that settles the flat: [from] pays [to] [amount].
class Settlement {
  final String from;
  final String to;
  final double amount;

  const Settlement(
      {required this.from, required this.to, required this.amount});
}

/// Where the flat stands: who paid what for everyone, each person's fair
/// share, and the transfers that would even it out.
///
/// There is no pooled cash. Paying for the flat's shopping is the
/// contribution, and a debt is closed by recording a transfer. Nothing is
/// ever reset: what is unsettled simply carries on.
class SharedPool {
  /// One entry per flatmate in [kRoommates] order.
  final List<PoolPerson> people;

  /// Everything bought for the flat, personal parts left out.
  final double sharedTotal;

  /// The fewest transfers, as a list, that bring every balance to zero.
  final List<Settlement> settlements;

  const SharedPool({
    required this.people,
    required this.sharedTotal,
    required this.settlements,
  });

  /// Each person's fair share of what was bought for the flat.
  double get perPerson => sharedTotal / kRoommateCount;

  bool get isSettled => settlements.isEmpty;
}

/// Balances closer to zero than this are treated as settled: a split into
/// four leaves fractions of a tenge nobody is going to transfer.
const double kSettledThreshold = 1;

/// Pure, so the rule can be tested without a Firestore stream behind it.
SharedPool sharedPool(List<Expense> expenses) {
  final paid = {for (final name in kRoommates) name: 0.0};
  final sent = {for (final name in kRoommates) name: 0.0};
  final fined = {for (final name in kRoommates) name: 0.0};
  final received = {for (final name in kRoommates) name: 0.0};
  var sharedTotal = 0.0;

  for (final expense in expenses) {
    if (expense.isFine) {
      // A fine in force is a debt from the offender to the other three,
      // shared equally between them. It is not spending.
      final offender = expense.offender;
      if (fineStatus(expense) != FineStatus.active ||
          !fined.containsKey(offender)) {
        continue;
      }
      final judges = fineJudges(expense);
      fined[offender!] = fined[offender]! - expense.amount;
      for (final judge in judges) {
        fined[judge] = fined[judge]! + expense.amount / judges.length;
      }
    } else if (expense.isTransfer) {
      // Not money until the recipient says it arrived.
      if (!expense.confirmed) continue;
      final to = expense.recipient;
      if (sent.containsKey(expense.author) && received.containsKey(to)) {
        sent[expense.author] = sent[expense.author]! + expense.amount;
        received[to!] = received[to]! + expense.amount;
      }
    } else if (!expense.isIncome) {
      // A purchase only counts once we know who paid for it; an anonymous
      // one could not be balanced against anybody.
      if (!paid.containsKey(expense.author)) continue;
      paid[expense.author] = paid[expense.author]! + expense.sharedAmount;
      sharedTotal += expense.sharedAmount;
    }
  }

  final fair = sharedTotal / kRoommateCount;
  final people = [
    for (final name in kRoommates)
      PoolPerson(
        name: name,
        paid: paid[name]!,
        sent: sent[name]!,
        received: received[name]!,
        balance:
            paid[name]! - fair + sent[name]! - received[name]! + fined[name]!,
      ),
  ];

  return SharedPool(
    people: people,
    sharedTotal: sharedTotal,
    settlements: _settle(people),
  );
}

/// Pairs the biggest debtor with the biggest creditor until everyone is
/// within [kSettledThreshold] of zero. Greedy, which for four people is
/// never more than three transfers.
List<Settlement> _settle(List<PoolPerson> people) {
  final creditors = [
    for (final p in people)
      if (p.balance >= kSettledThreshold) _Open(p.name, p.balance),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  final debtors = [
    for (final p in people)
      if (p.balance <= -kSettledThreshold) _Open(p.name, -p.balance),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  final result = <Settlement>[];
  var c = 0;
  var d = 0;
  while (c < creditors.length && d < debtors.length) {
    final amount = creditors[c].amount < debtors[d].amount
        ? creditors[c].amount
        : debtors[d].amount;
    final rounded = amount.roundToDouble();
    if (rounded >= kSettledThreshold) {
      result.add(Settlement(
        from: debtors[d].name,
        to: creditors[c].name,
        amount: rounded,
      ));
    }
    creditors[c].amount -= amount;
    debtors[d].amount -= amount;
    if (creditors[c].amount < kSettledThreshold) c++;
    if (debtors[d].amount < kSettledThreshold) d++;
  }
  return result;
}

class _Open {
  final String name;
  double amount;
  _Open(this.name, this.amount);
}

/// Whether the open period has been settled in full and should move to
/// history: something was bought or fined, nobody owes anybody, and no
/// fine is still being voted on.
bool periodIsClosed(List<Expense> open) {
  final fines = open.where((e) => e.isFine);
  if (fines.any((f) => fineStatus(f) == FineStatus.voting)) return false;
  final pool = sharedPool(open);
  final anythingHappened = pool.sharedTotal > 0 ||
      fines.any((f) => fineStatus(f) == FineStatus.active);
  return anythingHappened && pool.isSettled;
}
