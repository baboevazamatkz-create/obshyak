import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/data/name_store.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/shared_budget.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/data/scan_service.dart';
import 'package:expense_tracker/screens/name_picker_screen.dart';
import 'package:expense_tracker/widgets/split_card.dart';

Expense _spend(String id, double amount, DateTime date) => Expense(
      id: id,
      amount: amount,
      date: date,
      currency: AppCurrency.kzt,
    );

void main() {
  group('sharedPool', () {
    Expense sharedIncome(String id, double amount, DateTime date) => Expense(
          id: id,
          amount: amount,
          date: date,
          currency: AppCurrency.kzt,
          type: TransactionType.income,
          shared: true,
        );

    Expense soloIncome(String id, String who, double amount, DateTime date) =>
        Expense(
          id: id,
          amount: amount,
          date: date,
          author: who,
          currency: AppCurrency.kzt,
          type: TransactionType.income,
        );

    Expense spendBy(String id, String who, double amount, DateTime date) =>
        Expense(
          id: id,
          amount: amount,
          date: date,
          author: who,
          currency: AppCurrency.kzt,
        );

    PoolPerson person(SharedPool pool, String name) =>
        pool.people.singleWhere((p) => p.name == name);

    test('a shared income is split four ways and counts as each share', () {
      final pool = sharedPool([
        sharedIncome('pool', 60000, DateTime(2026, 10, 1)),
        spendBy('food', 'Азамат', 8000, DateTime(2026, 10, 2)),
      ]);
      expect(person(pool, 'Азамат').contributed, 15000);
      expect(person(pool, 'Аслан').contributed, 15000);
      expect(pool.contributedTotal, 60000);
      expect(pool.spentTotal, 8000);
      expect(pool.remaining, 52000);
      expect(pool.perPerson, 2000);
      expect(person(pool, 'Азамат').spent, 8000);
      expect(person(pool, 'Аслан').spent, 0);
    });

    test('a solo income belongs to whoever entered it', () {
      final pool = sharedPool([
        soloIncome('mine', 'Имран', 5000, DateTime(2026, 10, 1)),
      ]);
      expect(person(pool, 'Имран').contributed, 5000);
      expect(person(pool, 'Аслан').contributed, 0);
      expect(pool.biggestContributors, ['Имран']);
    });

    test('the latest shared income opens the period; older spending drops out',
        () {
      final pool = sharedPool([
        spendBy('late', 'Аслан', 1000, DateTime(2026, 10, 3)),
        sharedIncome('pool', 40000, DateTime(2026, 10, 2)),
        spendBy('early', 'Азамат', 9000, DateTime(2026, 10, 1)),
      ]);
      expect(pool.since, DateTime(2026, 10, 2));
      expect(pool.spentTotal, 1000);
      expect(person(pool, 'Азамат').spent, 0);
      expect(person(pool, 'Аслан').spent, 1000);
    });

    test('a solo income from before the period opening is not counted', () {
      final pool = sharedPool([
        sharedIncome('pool', 40000, DateTime(2026, 10, 5)),
        soloIncome('old', 'Имран', 9000, DateTime(2026, 10, 1)),
      ]);
      // Only Имран's share of the shared income counts, not the old 9 000.
      expect(person(pool, 'Имран').contributed, 10000);
      expect(pool.biggestContributors, isEmpty);
    });

    test('with no shared income yet, the whole history counts', () {
      final pool = sharedPool([
        spendBy('a', 'Азамат', 400, DateTime(2026, 9, 1)),
        soloIncome('b', 'Аслан', 1000, DateTime(2026, 9, 2)),
      ]);
      expect(pool.since, isNull);
      expect(pool.spentTotal, 400);
      expect(pool.remaining, 600);
    });

    test('when one person put in more on their own, they are marked as bigger',
        () {
      final pool = sharedPool([
        sharedIncome('b', 4000, DateTime(2026, 10, 2)),
        soloIncome('a', 'Мухаммад', 3000, DateTime(2026, 10, 3)),
      ]);
      expect(pool.biggestContributors, ['Мухаммад']);
    });

    test('equal contributions mark nobody as bigger', () {
      final pool = sharedPool([
        sharedIncome('pool', 80000, DateTime(2026, 10, 1)),
      ]);
      expect(pool.biggestContributors, isEmpty);
    });

    test('an empty budget totals to zero rather than failing', () {
      final pool = sharedPool(const []);
      expect(pool.spentTotal, 0);
      expect(pool.perPerson, 0);
      expect(pool.people.length, kRoommateCount);
    });
  });

  group('Expense storage', () {
    test('round-trips the author and receipt id', () {
      final expense = Expense(
        id: 'e1',
        amount: 1200,
        date: DateTime(2026, 10, 1),
        author: 'Аслан',
        receiptId: 'r1',
        currency: AppCurrency.kzt,
      );
      final restored = Expense.fromJson(expense.toJson());
      expect(restored.author, 'Аслан');
      expect(restored.receiptId, 'r1');
    });

    test('records written before names existed read as anonymous, no receipt',
        () {
      final restored = Expense.fromJson({
        'id': 'old',
        'amount': 500,
        'category': 'food',
        'note': '',
        'date': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'currency': 'kzt',
        'type': 'expense',
      });
      expect(restored.author, '');
      expect(restored.receiptId, isNull);
    });

    test('copyWith stamps the author without touching the rest', () {
      final stamped = _spend('s', 10, DateTime(2026, 1, 1))
          .copyWith(author: 'Имран', receiptId: 'r9');
      expect(stamped.id, 's');
      expect(stamped.amount, 10);
      expect(stamped.author, 'Имран');
      expect(stamped.receiptId, 'r9');
    });
  });

  group('NameStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing is remembered until a name is picked', () async {
      expect(await NameStore.load(), isNull);
    });

    test('the picked name is remembered', () async {
      await NameStore.save('Мухаммад');
      expect(await NameStore.load(), 'Мухаммад');
    });

    test('a stored name that is no longer one of the four is forgotten',
        () async {
      SharedPreferences.setMockInitialValues({'my_name': 'Незнакомец'});
      expect(await NameStore.load(), isNull);
    });
  });

  group('prepareReceiptPhoto', () {
    test('garbage that is not an image produces no photo', () {
      expect(prepareReceiptPhoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('a wide screenshot is shrunk to the receipt width and stays a JPEG',
        () {
      final source = img.Image(width: 2000, height: 1000);
      final bytes = Uint8List.fromList(img.encodePng(source));

      final photo = prepareReceiptPhoto(bytes);

      expect(photo, isNotNull);
      final decoded = img.decodeJpg(photo!);
      expect(decoded, isNotNull);
      expect(decoded!.width, kReceiptWidth);
      expect(photo.length, lessThanOrEqualTo(kReceiptMaxBytes));
    });
  });

  testWidgets('the name picker offers the four flatmates and reports the pick',
      (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: NamePickerScreen(onPicked: (name) => picked = name),
    ));

    for (final name in kRoommates) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Аслан'));
    expect(picked, 'Аслан');
  });

  testWidgets('the pool card shows each person\'s share in tenge',
      (tester) async {
    final pool = sharedPool([
      Expense(
        id: 'pool',
        amount: 40000,
        date: DateTime(2026, 10, 1),
        author: 'Азамат',
        currency: AppCurrency.kzt,
        type: TransactionType.income,
        shared: true,
      ),
      Expense(
        id: 'food',
        amount: 10000,
        date: DateTime(2026, 10, 2),
        author: 'Аслан',
        currency: AppCurrency.kzt,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitCard(pool: pool, currency: AppCurrency.kzt),
      ),
    ));

    // Everyone put in 10 000, so nobody is marked as putting in more.
    expect(find.text('больше вклад'), findsNothing);
    expect(find.text(AppCurrency.kzt.format.format(10000)), findsWidgets);
    expect(find.text(AppCurrency.kzt.format.format(2500)), findsOneWidget);
  });
}
