import 'dart:math';

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

  /// What they have actually spent on the flat's shopping: their purchases,
  /// plus what they paid back towards others' purchases, minus what was
  /// paid back to them for their own. Money moving because of a fine never
  /// counts here.
  final double spent;

  const PoolPerson({
    required this.name,
    required this.paid,
    required this.sent,
    required this.received,
    required this.balance,
    required this.spent,
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

/// Splits [amount] into [parts] whole-tenge shares that add up to the
/// amount rounded to the tenge: 5 000 in three is 1 667, 1 667, 1 666.
///
/// Splitting into fractions instead left a debt of 1 666.67 shown as 1 667;
/// paying that left a third of a tenge the other way, and balances drifted
/// off the transfers by a tenge or two.
List<double> splitEvenly(double amount, int parts) => [
      for (var i = 0; i < parts; i++)
        (amount * (i + 1) / parts).roundToDouble() -
            (amount * i / parts).roundToDouble(),
    ];

/// Pure, so the rule can be tested without a Firestore stream behind it.
///
/// Everything is worked out as who owes whom, and the balances are read off
/// those same debts, so a balance always equals what the listed transfers
/// would move.
SharedPool sharedPool(List<Expense> expenses) {
  final paid = {for (final name in kRoommates) name: 0.0};
  final sent = {for (final name in kRoommates) name: 0.0};
  final received = {for (final name in kRoommates) name: 0.0};
  // owes[a][b]: what a still owes b. Never netted against owes[b][a].
  final owes = {
    for (final a in kRoommates) a: {for (final b in kRoommates) b: 0.0},
  };
  var sharedTotal = 0.0;

  void owe(String from, String to, double amount) =>
      owes[from]![to] = owes[from]![to]! + amount;

  for (final expense in expenses) {
    final author = expense.author;
    final to = expense.recipient;
    if (expense.isOffset) {
      // Both debts go down by the same amount; nobody's balance moves.
      if (!owes.containsKey(author) || !owes.containsKey(to)) continue;
      owe(author, to!, -expense.amount);
      owe(to, author, -expense.amount);
    } else if (expense.isFine) {
      // A fine in force is a debt from the offender to everyone else,
      // shared equally between them. It is not spending.
      final offender = expense.offender;
      if (fineStatus(expense) != FineStatus.active ||
          !owes.containsKey(offender)) {
        continue;
      }
      final judges = fineJudges(expense);
      final shares = splitEvenly(expense.amount, judges.length);
      for (var i = 0; i < judges.length; i++) {
        owe(offender!, judges[i], shares[i]);
      }
    } else if (expense.isTransfer) {
      // Not money until the recipient says it arrived.
      if (!expense.confirmed) continue;
      if (!owes.containsKey(author) || !owes.containsKey(to)) continue;
      sent[author] = sent[author]! + expense.amount;
      received[to!] = received[to]! + expense.amount;
      owe(author, to, -expense.amount);
    } else if (!expense.isIncome) {
      // A purchase only counts once we know who paid for it; an anonymous
      // one could not be balanced against anybody.
      if (!paid.containsKey(author)) continue;
      final shared = expense.sharedAmount;
      paid[author] = paid[author]! + shared;
      sharedTotal += shared;
      // Everyone else owes the buyer their quarter of it.
      final shares = splitEvenly(shared, kRoommateCount);
      for (var i = 0; i < kRoommates.length; i++) {
        if (kRoommates[i] != author) owe(kRoommates[i], author, shares[i]);
      }
    }
  }

  _carryOverpayments(owes);
  final spentShift = _shoppingRepaid(expenses);

  final people = [
    for (final name in kRoommates)
      PoolPerson(
        name: name,
        paid: paid[name]!,
        sent: sent[name]!,
        received: received[name]!,
        spent: paid[name]! + spentShift[name]!,
        balance: [
          for (final other in kRoommates)
            owes[other]![name]! - owes[name]![other]!,
        ].fold(0.0, (sum, x) => sum + x),
      ),
  ];

  return SharedPool(
    people: people,
    sharedTotal: sharedTotal,
    settlements: _settle(owes),
    offsets: _offsets(owes),
  );
}

/// How much of the money that changed hands went towards the flat's
/// shopping, per flatmate: positive for what they paid back on purchases,
/// negative for what they were paid back for theirs.
///
/// Each pair's debt is kept in two parts, shopping and fines. A payment or
/// an offset settles the payer's shopping debt first, then their fine,
/// then any credit the other side holds from an earlier overpayment; what
/// is left is a new overpayment, held as credit exactly as [sharedPool]
/// holds it, so later debts eat into it the same way. At the end, a credit
/// that is cancelling a fine in the same pair was fine money all along and
/// is taken back out of the shopping count.
Map<String, double> _shoppingRepaid(List<Expense> expenses) {
  // shopping[a][b] < 0 is credit: b owes a from an overpayment.
  final shopping = {
    for (final a in kRoommates) a: {for (final b in kRoommates) b: 0.0},
  };
  final fines = {
    for (final a in kRoommates) a: {for (final b in kRoommates) b: 0.0},
  };
  final shift = {for (final name in kRoommates) name: 0.0};

  void count(String from, String to, double amount) {
    shift[from] = shift[from]! + amount;
    shift[to] = shift[to]! - amount;
  }

  void settle(String from, String to, double amount) {
    var rest = amount;
    final toShopping = min(rest, max(0.0, shopping[from]![to]!));
    shopping[from]![to] = shopping[from]![to]! - toShopping;
    rest -= toShopping;
    final toFine = min(rest, fines[from]![to]!);
    fines[from]![to] = fines[from]![to]! - toFine;
    rest -= toFine;
    final toCredit = min(rest, max(0.0, -shopping[to]![from]!));
    shopping[to]![from] = shopping[to]![from]! + toCredit;
    rest -= toCredit;
    shopping[from]![to] = shopping[from]![to]! - rest;
    count(from, to, toShopping + toCredit + rest);
  }

  // Every purchase and fine first, then payments and offsets oldest first
  // (ties keep the order they came in). A payment can only ever be made
  // against debts that already exist, so taking all debts first makes the
  // split independent of how records are dated or ordered.
  bool movesMoney(Expense e) => e.isTransfer || e.isOffset;
  final ordered = [
    for (var i = 0; i < expenses.length; i++) (i, expenses[i]),
  ]..sort((x, y) {
      final byKind =
          (movesMoney(x.$2) ? 1 : 0).compareTo(movesMoney(y.$2) ? 1 : 0);
      if (byKind != 0) return byKind;
      final byDate = x.$2.date.compareTo(y.$2.date);
      return byDate != 0 ? byDate : x.$1.compareTo(y.$1);
    });

  for (final (_, expense) in ordered) {
    final author = expense.author;
    final to = expense.recipient;
    if (expense.isFine) {
      final offender = expense.offender;
      if (fineStatus(expense) != FineStatus.active ||
          !fines.containsKey(offender)) {
        continue;
      }
      final judges = fineJudges(expense);
      final shares = splitEvenly(expense.amount, judges.length);
      for (var i = 0; i < judges.length; i++) {
        fines[offender]![judges[i]] = fines[offender]![judges[i]]! + shares[i];
      }
    } else if (expense.isTransfer || expense.isOffset) {
      if (expense.isTransfer && !expense.confirmed) continue;
      if (!shift.containsKey(author) || !shift.containsKey(to)) continue;
      settle(author, to!, expense.amount);
      if (expense.isOffset) settle(to, author, expense.amount);
    } else if (!expense.isIncome && shift.containsKey(author)) {
      final shares = splitEvenly(expense.sharedAmount, kRoommateCount);
      for (var i = 0; i < kRoommates.length; i++) {
        final other = kRoommates[i];
        if (other != author) {
          shopping[other]![author] = shopping[other]![author]! + shares[i];
        }
      }
    }
  }

  // Credit sitting against a fine in the same direction: the overpayment
  // that made it covered that fine, so it was never shopping money.
  for (final a in kRoommates) {
    for (final b in kRoommates) {
      if (a == b) continue;
      final cancelled = min(fines[a]![b]!, max(0.0, -shopping[a]![b]!));
      if (cancelled > 0) count(b, a, cancelled);
    }
  }
  return shift;
}

/// A debt paid down past zero means the payer handed over too much: the
/// excess is now owed back to them, so it moves to the other direction
/// instead of sitting as a negative debt nobody is asked to settle.
void _carryOverpayments(Map<String, Map<String, double>> owes) {
  for (var i = 0; i < kRoommates.length; i++) {
    for (var j = i + 1; j < kRoommates.length; j++) {
      final a = kRoommates[i];
      final b = kRoommates[j];
      if (owes[a]![b]! < 0) {
        owes[b]![a] = owes[b]![a]! - owes[a]![b]!;
        owes[a]![b] = 0;
      }
      if (owes[b]![a]! < 0) {
        owes[a]![b] = owes[a]![b]! - owes[b]![a]!;
        owes[b]![a] = 0;
      }
    }
  }
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
      final owed = owes[from]![to]!;
      if (owed < kSettledThreshold) continue;
      result.add(Settlement(from: from, to: to, amount: owed.roundToDouble()));
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
      final smaller = ab < ba ? ab : ba;
      if (smaller < kSettledThreshold) continue;
      final common = smaller.roundToDouble();
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
