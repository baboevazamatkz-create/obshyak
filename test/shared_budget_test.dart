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

Expense _income(String id, double amount, DateTime date) => Expense(
      id: id,
      amount: amount,
      date: date,
      currency: AppCurrency.kzt,
      type: TransactionType.income,
    );

void main() {
  group('sharedSplit', () {
    test('with no income yet, every expense counts and is split four ways', () {
      final split = sharedSplit(
        [
          _spend('a', 4000, DateTime(2026, 9, 1)),
          _spend('b', 2000, DateTime(2026, 9, 2)),
        ],
        people: kRoommateCount,
      );
      expect(split.total, 6000);
      expect(split.perPerson, 1500);
      expect(split.since, isNull);
    });

    test('an income starts the count over: earlier spending drops out', () {
      final split = sharedSplit(
        [
          _spend('late', 1000, DateTime(2026, 10, 3)),
          _income('pool', 50000, DateTime(2026, 10, 2)),
          _spend('early', 9000, DateTime(2026, 10, 1)),
        ],
        people: kRoommateCount,
      );
      expect(split.total, 1000);
      expect(split.perPerson, 250);
      expect(split.since, DateTime(2026, 10, 2));
    });

    test('income is never added to the total, even after the last spend', () {
      final split = sharedSplit(
        [
          _income('pool', 50000, DateTime(2026, 10, 2)),
          _spend('x', 800, DateTime(2026, 10, 3)),
        ],
        people: kRoommateCount,
      );
      expect(split.total, 800);
    });

    test('the most recent income decides the reset, whatever the list order',
        () {
      final split = sharedSplit(
        [
          _income('older', 1, DateTime(2026, 9, 1)),
          _spend('mid', 300, DateTime(2026, 9, 5)),
          _income('newer', 1, DateTime(2026, 9, 10)),
          _spend('after', 700, DateTime(2026, 9, 12)),
        ],
        people: kRoommateCount,
      );
      expect(split.total, 700);
      expect(split.since, DateTime(2026, 9, 10));
    });

    test('an empty budget splits to zero rather than failing', () {
      final split = sharedSplit(const [], people: kRoommateCount);
      expect(split.total, 0);
      expect(split.perPerson, 0);
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

  testWidgets('the split card shows each person\'s share in tenge',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SplitCard(
          split: SharedSplit(total: 10000, perPerson: 2500, since: null),
          currency: AppCurrency.kzt,
        ),
      ),
    ));

    expect(find.text(AppCurrency.kzt.format.format(2500)), findsOneWidget);
    expect(find.text('Доходов ещё не было, считаем всё'), findsOneWidget);
  });
}
