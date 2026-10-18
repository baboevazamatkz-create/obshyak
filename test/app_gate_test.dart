import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/app_gate.dart';
import 'package:expense_tracker/data/budget_cache.dart';
import 'package:expense_tracker/models/away.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/screens/home_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a failed connection says so and can be retried', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: AppGate(connect: () async {
        attempts++;
        throw Exception('offline');
      }),
    ));
    await tester.pump();
    expect(find.textContaining('Не удалось подключиться'), findsOneWidget);
    // The cause is shown, small, for a screenshot to carry.
    expect(find.textContaining('offline'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(attempts, 2);
  });

  testWidgets('once connected, a new phone is asked who it is', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppGate(connect: () async {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Кто вы?'), findsOneWidget);
  });

  testWidgets('a known phone opens on the saved figures without waiting',
      (tester) async {
    await initializeDateFormatting('ru');
    SharedPreferences.setMockInitialValues({
      'my_name_v3': 'Имран',
      // The tour has been seen; it would only cover the screen here.
      'tour_seen_v1': true,
    });
    await BudgetCache.save([
      Expense(
        id: 'a',
        amount: 4000,
        note: 'Рыба',
        date: DateTime(2026, 10, 18),
        author: 'Аслан',
        currency: AppCurrency.kzt,
      ),
    ], AwayBook());

    // A connection that never comes.
    final never = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: AppGate(connect: () => never.future),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Рыба'), findsOneWidget);
    expect(find.byTooltip('Обновляется'), findsOneWidget);
  });
}
