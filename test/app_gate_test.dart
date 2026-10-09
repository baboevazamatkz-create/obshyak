import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/app_gate.dart';

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
}
