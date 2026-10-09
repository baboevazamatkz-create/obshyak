import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/fines.dart';
import 'package:expense_tracker/models/shared_budget.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';

var _id = 0;
final _day = DateTime(2026, 10, 1);

Expense buy(String who, double amount, {double personal = 0}) => Expense(
      id: 'b${_id++}',
      amount: amount,
      personal: personal,
      date: _day,
      author: who,
      currency: AppCurrency.kzt,
    );

Expense pay(String from, String to, double amount, {bool confirmed = true}) =>
    Expense(
      id: 't${_id++}',
      amount: amount,
      date: _day,
      author: from,
      recipient: to,
      confirmed: confirmed,
      currency: AppCurrency.kzt,
      type: TransactionType.transfer,
    );

Expense offset(String a, String b, double amount) => Expense(
      id: 'o${_id++}',
      amount: amount,
      date: _day,
      author: a,
      recipient: b,
      currency: AppCurrency.kzt,
      type: TransactionType.offset,
    );

Expense fine(String offender, double amount, {bool active = true}) => Expense(
      id: 'f${_id++}',
      amount: amount,
      date: _day,
      note: 'посуда',
      author: offender,
      offender: offender,
      offenderVote: kOffenderAccept,
      votes: {
        for (final n in kRoommates)
          if (n != offender) n: active ? kVoteYes : kVoteNo,
      },
      currency: AppCurrency.kzt,
      type: TransactionType.fine,
    );

PoolPerson person(SharedPool pool, String name) =>
    pool.people.singleWhere((p) => p.name == name);

/// The rules every pool must keep, whatever was recorded.
void expectConsistent(SharedPool pool, {String reason = ''}) {
  // Money only moves between the four: balances cancel out exactly.
  final total = pool.people.fold<double>(0, (s, p) => s + p.balance);
  expect(total.abs(), lessThan(1e-6), reason: 'balances sum $reason');

  // Each balance is exactly what the listed transfers would move.
  for (final p in pool.people) {
    final incoming = pool.settlements
        .where((s) => s.to == p.name)
        .fold<double>(0, (sum, s) => sum + s.amount);
    final outgoing = pool.settlements
        .where((s) => s.from == p.name)
        .fold<double>(0, (sum, s) => sum + s.amount);
    expect(p.balance, closeTo(incoming - outgoing, 1e-6),
        reason: '${p.name} balance vs transfers $reason');
  }

  // Nobody owes themselves, and no debt is shown twice.
  for (final s in pool.settlements) {
    expect(s.from, isNot(s.to));
    expect(s.amount, greaterThanOrEqualTo(kSettledThreshold));
  }
  final pairs = pool.settlements.map((s) => '${s.from}>${s.to}').toSet();
  expect(pairs.length, pool.settlements.length);

  // An offset cancels the smaller of two real, opposing debts.
  for (final o in pool.offsets) {
    final ab = pool.settlements.firstWhere((s) => s.from == o.a && s.to == o.b);
    final ba = pool.settlements.firstWhere((s) => s.from == o.b && s.to == o.a);
    expect(o.amount, min(ab.amount, ba.amount));
    final left = (ab.amount - ba.amount).abs();
    expect(o.remainder?.amount ?? 0, left);
  }
}

void main() {
  test('whole-tenge shares always add back up to the amount', () {
    expect(splitEvenly(5000, 3), [1667, 1666, 1667]);
    expect(splitEvenly(1001, 4), [250, 251, 250, 250]);
    expect(splitEvenly(8000, 4), [2000, 2000, 2000, 2000]);
    final rng = Random(1);
    for (var i = 0; i < 500; i++) {
      final amount = rng.nextInt(100000).toDouble();
      for (final parts in [3, 4]) {
        final shares = splitEvenly(amount, parts);
        expect(shares.reduce((a, b) => a + b), amount);
        expect(shares.every((s) => s == s.roundToDouble()), isTrue);
        expect(shares.reduce(max) - shares.reduce(min), lessThanOrEqualTo(1));
      }
    }
  });

  test('a 5 000 fine paid as shown leaves everyone at exactly zero', () {
    final records = [fine('Имран', 5000)];
    final owed = sharedPool(records);
    expect(owed.settlements.map((s) => s.amount).toList()..sort(),
        [1666, 1667, 1667]);
    expect(person(owed, 'Имран').balance, -5000);
    final paid = sharedPool([
      ...records,
      for (final s in owed.settlements) pay(s.from, s.to, s.amount),
    ]);
    expect(paid.isSettled, isTrue);
    for (final p in paid.people) {
      expect(p.balance, 0);
    }
  });

  test('an odd purchase is split to the tenge and settles to zero', () {
    final records = [buy('Аслан', 1001)];
    final owed = sharedPool(records);
    // The odd tenge falls on Аслан's own quarter: the others owe 250 each.
    expect(person(owed, 'Аслан').balance, 750);
    expect(owed.settlements.every((s) => s.amount == 250), isTrue);
    expectConsistent(owed);
    final paid = sharedPool([
      ...records,
      for (final s in owed.settlements) pay(s.from, s.to, s.amount),
    ]);
    expect(paid.isSettled, isTrue);
  });

  test('paying too much is owed back the other way', () {
    final pool =
        sharedPool([buy('Азамат', 8000), pay('Аслан', 'Азамат', 3000)]);
    final back = pool.settlements
        .singleWhere((s) => s.from == 'Азамат' && s.to == 'Аслан');
    expect(back.amount, 1000);
    expect(person(pool, 'Аслан').balance, 1000);
    expectConsistent(pool);
  });

  test('the personal part never reaches anyone else', () {
    final pool = sharedPool([buy('Мухаммад', 10000, personal: 10000)]);
    expect(pool.sharedTotal, 0);
    expect(pool.isSettled, isTrue);
  });

  test('a waiting transfer, a voting fine and a cancelled fine move nothing',
      () {
    final base = [buy('Азамат', 8000)];
    final before = sharedPool(base);
    final after = sharedPool([
      ...base,
      pay('Аслан', 'Азамат', 2000, confirmed: false),
      fine('Имран', 6000, active: false),
      Expense(
        id: 'voting',
        amount: 3000,
        date: _day,
        author: 'Азамат',
        offender: 'Мухаммад',
        votes: const {'Азамат': kVoteYes},
        currency: AppCurrency.kzt,
        type: TransactionType.fine,
      ),
    ]);
    for (var i = 0; i < kRoommates.length; i++) {
      expect(after.people[i].balance, before.people[i].balance);
    }
    expect(after.settlements.length, before.settlements.length);
  });

  test('shared total is every known purchase, personal parts left out', () {
    final pool = sharedPool([
      buy('Азамат', 5000, personal: 1000),
      buy('Аслан', 2500),
      Expense(id: 'anon', amount: 9999, date: _day, currency: AppCurrency.kzt),
    ]);
    expect(pool.sharedTotal, 6500);
    expect(pool.perPerson, 1625);
  });

  test('random flats always add up, and settle to zero when paid', () {
    final rng = Random(42);
    for (var round = 0; round < 300; round++) {
      String anyone() => kRoommates[rng.nextInt(kRoommates.length)];
      final records = <Expense>[];
      final steps = 1 + rng.nextInt(14);
      for (var step = 0; step < steps; step++) {
        final pick = rng.nextInt(10);
        if (pick < 6) {
          final amount = (100 + rng.nextInt(20000)).toDouble();
          final personal =
              rng.nextBool() ? 0.0 : rng.nextInt(amount.toInt()).toDouble();
          records.add(buy(anyone(), amount, personal: personal));
        } else if (pick < 7) {
          records.add(fine(anyone(), (500 + rng.nextInt(9500)).toDouble()));
        } else {
          // Pay part, all, or more than one of the debts currently shown.
          final open = sharedPool(records).settlements;
          if (open.isEmpty) continue;
          final s = open[rng.nextInt(open.length)];
          final factor = [0.5, 1.0, 1.3][rng.nextInt(3)];
          records.add(pay(s.from, s.to, (s.amount * factor).roundToDouble()));
        }
        expectConsistent(sharedPool(records), reason: 'round $round');
      }

      // Offset whatever can be offset, then pay everything that is left.
      var pool = sharedPool(records);
      for (final o in pool.offsets) {
        records.add(offset(o.a, o.b, o.amount));
      }
      pool = sharedPool(records);
      expect(pool.offsets, isEmpty, reason: 'round $round offsets');
      expectConsistent(pool, reason: 'round $round after offsets');

      for (final s in pool.settlements) {
        records.add(pay(s.from, s.to, s.amount));
      }
      final done = sharedPool(records);
      expect(done.isSettled, isTrue, reason: 'round $round settled');
      for (final p in done.people) {
        expect(p.balance.abs(), lessThan(kSettledThreshold),
            reason: 'round $round ${p.name}');
      }
    }
  });
}
