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
    Expense buy(String who, double amount, {double personal = 0}) => Expense(
          id: '$who-$amount-$personal',
          amount: amount,
          date: DateTime(2026, 10, 1),
          author: who,
          personal: personal,
          currency: AppCurrency.kzt,
        );

    Expense paidBack(String from, String to, double amount) => Expense(
          id: '$from-$to-$amount',
          amount: amount,
          date: DateTime(2026, 10, 2),
          author: from,
          recipient: to,
          currency: AppCurrency.kzt,
          type: TransactionType.transfer,
        );

    PoolPerson person(SharedPool pool, String name) =>
        pool.people.singleWhere((p) => p.name == name);

    test('one purchase: the buyer is owed three quarters, the rest owe one',
        () {
      final pool = sharedPool([buy('Азамат', 8000)]);
      expect(pool.sharedTotal, 8000);
      expect(pool.perPerson, 2000);
      expect(person(pool, 'Азамат').paid, 8000);
      expect(person(pool, 'Азамат').balance, 6000);
      expect(person(pool, 'Аслан').balance, -2000);
      expect(pool.settlements.length, 3);
      expect(pool.settlements.every((s) => s.to == 'Азамат'), isTrue);
      expect(pool.settlements.every((s) => s.amount == 2000), isTrue);
    });

    test('the personal part of a receipt is not split', () {
      final pool = sharedPool([buy('Имран', 10000, personal: 2000)]);
      expect(pool.sharedTotal, 8000);
      expect(person(pool, 'Имран').paid, 8000);
      expect(person(pool, 'Имран').balance, 6000);
    });

    test('a recorded transfer closes that debt', () {
      final pool = sharedPool([
        buy('Азамат', 8000),
        paidBack('Аслан', 'Азамат', 2000),
      ]);
      expect(person(pool, 'Аслан').balance, 0);
      expect(person(pool, 'Азамат').balance, 4000);
      // The 2 000 paid back is Аслан's spending now, and no longer Азамат's.
      expect(person(pool, 'Аслан').spent, 2000);
      expect(person(pool, 'Азамат').spent, 6000);
      expect(pool.settlements.any((s) => s.from == 'Аслан'), isFalse);
    });

    test('everyone paying their quarter leaves nothing to settle', () {
      final pool = sharedPool([
        for (final name in kRoommates) buy(name, 3000),
      ]);
      expect(pool.isSettled, isTrue);
      for (final p in pool.people) {
        expect(p.balance, 0);
      }
    });

    test('balances always add up to zero', () {
      final pool = sharedPool([
        buy('Азамат', 4300),
        buy('Аслан', 1250, personal: 250),
        buy('Мухаммад', 999),
        paidBack('Имран', 'Азамат', 700),
      ]);
      final sum = pool.people.fold<double>(0, (s, p) => s + p.balance);
      expect(sum.abs(), lessThan(0.001));
    });

    test('settling the suggested transfers brings everyone to zero', () {
      final records = [
        buy('Азамат', 4300),
        buy('Аслан', 1000),
        buy('Мухаммад', 999),
      ];
      final first = sharedPool(records);
      final settled = sharedPool([
        ...records,
        for (final s in first.settlements) paidBack(s.from, s.to, s.amount),
      ]);
      expect(settled.isSettled, isTrue);
    });

    test('a purchase with no known author is left out of the split', () {
      final pool = sharedPool([
        Expense(
          id: 'old',
          amount: 5000,
          date: DateTime(2026, 1, 1),
          currency: AppCurrency.kzt,
        ),
      ]);
      expect(pool.sharedTotal, 0);
      expect(pool.isSettled, isTrue);
    });

    test('legacy income records change nothing', () {
      final pool = sharedPool([
        Expense(
          id: 'income',
          amount: 60000,
          date: DateTime(2026, 1, 1),
          author: 'Азамат',
          currency: AppCurrency.kzt,
          type: TransactionType.income,
        ),
      ]);
      expect(pool.sharedTotal, 0);
      expect(pool.isSettled, isTrue);
    });

    test('an empty budget is settled and splits to zero', () {
      final pool = sharedPool(const []);
      expect(pool.sharedTotal, 0);
      expect(pool.perPerson, 0);
      expect(pool.isSettled, isTrue);
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
        personal: 300,
        recipient: 'Имран',
        currency: AppCurrency.kzt,
      );
      final restored = Expense.fromJson(expense.toJson());
      expect(restored.author, 'Аслан');
      expect(restored.receiptId, 'r1');
      expect(restored.personal, 300);
      expect(restored.recipient, 'Имран');
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
      expect(restored.personal, 0);
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

  testWidgets('the pool card lists who pays whom and reports a settle tap',
      (tester) async {
    final pool = sharedPool([
      Expense(
        id: 'food',
        amount: 8000,
        date: DateTime(2026, 10, 2),
        author: 'Азамат',
        currency: AppCurrency.kzt,
      ),
    ]);
    Settlement? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SplitCard(
            pool: pool,
            currency: AppCurrency.kzt,
            onSettle: (s) => tapped = s,
          ),
        ),
      ),
    ));

    expect(find.text('Аслан → Азамат'), findsOneWidget);
    expect(find.text('Оплачено'), findsNWidgets(3));
    await tester.tap(find.text('Оплачено').first);
    expect(tapped, isNotNull);
    expect(tapped!.to, 'Азамат');
  });

  testWidgets('a settled flat says so instead of listing transfers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SplitCard(
            pool: sharedPool(const []),
            currency: AppCurrency.kzt,
            onSettle: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('Все в расчёте'), findsOneWidget);
    expect(find.text('Оплачено'), findsNothing);
  });
}
