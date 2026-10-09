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

/// Two flatmates who owe each other: [amount] of each debt can be cancelled
/// against the other, leaving only the difference.
class Offset {
  final String a;
  final String b;
  final double amount;

  /// What is left once the two debts are offset: who still pays whom, or
  /// null when they cancel out exactly.
  final Settlement? remainder;

  const Offset({
    required this.a,
    required this.b,
    required this.amount,
    this.remainder,
  });

  bool involves(String name) => name == a || name == b;

  /// Whether [settlement] is one of the two debts this offset covers.
  bool covers(Settlement settlement) =>
      involves(settlement.from) && involves(settlement.to);
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

  /// Every debt still open, one per direction between two flatmates: a
  /// debt is never cancelled out by one running the other way.
  final List<Settlement> settlements;

  /// Pairs who owe each other, and how much of it can be cancelled out.
  final List<Offset> offsets;

  const SharedPool({
    required this.people,
    required this.sharedTotal,
    required this.settlements,
    this.offsets = const [],
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
  // owes[a][b]: what a still owes b. Never netted against owes[b][a].
  final owes = {
    for (final a in kRoommates) a: {for (final b in kRoommates) b: 0.0},
  };
  final received = {for (final name in kRoommates) name: 0.0};
  var sharedTotal = 0.0;

  for (final expense in expenses) {
    if (expense.isOffset) {
      // Both debts go down by the same amount; nobody's balance moves.
      final to = expense.recipient;
      if (owes.containsKey(expense.author) && owes.containsKey(to)) {
        owes[expense.author]![to!] =
            owes[expense.author]![to]! - expense.amount;
        owes[to]![expense.author] = owes[to]![expense.author]! - expense.amount;
      }
    } else if (expense.isFine) {
      // A fine in force is a debt from the offender to the other three,
      // shared equally between them. It is not spending.
      final offender = expense.offender;
      if (fineStatus(expense) != FineStatus.active ||
          !fined.containsKey(offender)) {
        continue;
      }
      final judges = fineJudges(expense);
      final share = expense.amount / judges.length;
      fined[offender!] = fined[offender]! - expense.amount;
      for (final judge in judges) {
        fined[judge] = fined[judge]! + share;
        owes[offender]![judge] = owes[offender]![judge]! + share;
      }
    } else if (expense.isTransfer) {
      // Not money until the recipient says it arrived.
      if (!expense.confirmed) continue;
      final to = expense.recipient;
      if (sent.containsKey(expense.author) && received.containsKey(to)) {
        sent[expense.author] = sent[expense.author]! + expense.amount;
        received[to!] = received[to]! + expense.amount;
        owes[expense.author]![to] = owes[expense.author]![to]! - expense.amount;
      }
    } else if (!expense.isIncome) {
      // A purchase only counts once we know who paid for it; an anonymous
      // one could not be balanced against anybody.
      if (!paid.containsKey(expense.author)) continue;
      paid[expense.author] = paid[expense.author]! + expense.sharedAmount;
      sharedTotal += expense.sharedAmount;
      // Everyone else owes the buyer their quarter of it.
      final quarter = expense.sharedAmount / kRoommateCount;
      for (final other in kRoommates) {
        if (other == expense.author) continue;
        owes[other]![expense.author] = owes[other]![expense.author]! + quarter;
      }
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
    settlements: _settle(owes),
    offsets: _offsets(owes),
  );
}

/// Every debt one flatmate still owes another, each on its own.
///
/// Debts are deliberately not netted: if Аслан owes Азамат 2 000 and then
/// Азамат comes to owe Аслан 2 000, both stay until each is paid and
/// confirmed. Netting them made a debt vanish the moment the debtor bought
/// something big, which is not how the flat settles up.
List<Settlement> _settle(Map<String, Map<String, double>> owes) {
  final result = <Settlement>[];
  for (final from in kRoommates) {
    for (final to in kRoommates) {
      if (from == to) continue;
      final amount = owes[from]![to]!.roundToDouble();
      if (amount < kSettledThreshold) continue;
      result.add(Settlement(from: from, to: to, amount: amount));
    }
  }
  return result;
}

/// Every pair who owe each other at the same time, with the smaller of
/// the two debts: what a mutual offset would cancel on both sides.
List<Offset> _offsets(Map<String, Map<String, double>> owes) {
  final result = <Offset>[];
  for (var i = 0; i < kRoommates.length; i++) {
    for (var j = i + 1; j < kRoommates.length; j++) {
      final a = kRoommates[i];
      final b = kRoommates[j];
      final ab = owes[a]![b]!;
      final ba = owes[b]![a]!;
      final common = (ab < ba ? ab : ba).roundToDouble();
      if (common < kSettledThreshold) continue;
      final left = (ab - ba).abs().roundToDouble();
      result.add(Offset(
        a: a,
        b: b,
        amount: common,
        remainder: left < kSettledThreshold
            ? null
            : ab > ba
                ? Settlement(from: a, to: b, amount: left)
                : Settlement(from: b, to: a, amount: left),
      ));
    }
  }
  return result;
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
