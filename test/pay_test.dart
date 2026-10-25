import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/widgets/pay_dialog.dart';

final _day = DateTime(2026, 10, 25);

Expense _buy(String who, double amount) => Expense(
      id: 'b$who$amount',
      amount: amount,
      date: _day,
      author: who,
      currency: AppCurrency.kzt,
    );

Expense _pay(String from, String to, double amount, {bool confirmed = true}) =>
    Expense(
      id: 't$from$amount$confirmed',
      amount: amount,
      date: _day,
      author: from,
      recipient: to,
      confirmed: confirmed,
      currency: AppCurrency.kzt,
      type: TransactionType.transfer,
    );

double _owed(SharedPool pool, String from, String to) => pool.settlements
    .where((s) => s.from == from && s.to == to)
    .fold(0.0, (sum, s) => sum + s.amount);

void main() {
  group('paying part of a debt', () {
    final buy = _buy('Азамат', 12000); // everyone else owes 3 000

    test('a confirmed part comes off and the rest stays owed', () {
      final pool = sharedPool([buy, _pay('Аслан', 'Азамат', 1000)]);
      expect(_owed(pool, 'Аслан', 'Азамат'), 2000);
      final aslan = pool.people.firstWhere((p) => p.name == 'Аслан');
      expect(aslan.spent, 1000);
      expect(aslan.balance, -2000);
    });

    test('a part not yet confirmed changes nothing', () {
      final pool = sharedPool(
        [buy, _pay('Аслан', 'Азамат', 1000, confirmed: false)],
      );
      expect(_owed(pool, 'Аслан', 'Азамат'), 3000);
    });

    test('parts paid one after another settle the debt', () {
      final pool = sharedPool([
        buy,
        _pay('Аслан', 'Азамат', 1000),
        _pay('Аслан', 'Азамат', 500),
        _pay('Аслан', 'Азамат', 1500),
      ]);
      expect(_owed(pool, 'Аслан', 'Азамат'), 0);
      expect(pool.people.firstWhere((p) => p.name == 'Аслан').spent, 3000);
    });
  });

  group('the pay dialog', () {
    const debt = Settlement(from: 'Аслан', to: 'Азамат', amount: 3000);

    testWidgets('starts on the whole debt and returns a smaller part',
        (tester) async {
      double? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPayDialog(context, debt),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('3 000'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1200');
      await tester.tap(find.text('Отправил'));
      await tester.pumpAndSettle();
      expect(result, 1200);
    });

    testWidgets('refuses more than the debt, and nothing', (tester) async {
      double? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPayDialog(context, debt),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '5000');
      await tester.tap(find.text('Отправил'));
      await tester.pump();
      expect(find.text('Не больше долга'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Отправил'));
      await tester.pump();
      expect(find.text('Введите сумму'), findsOneWidget);
      expect(result, isNull);
    });
  });
}
