import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/widgets/tour.dart';

void main() {
  testWidgets('the tour walks five cards and is then never shown again',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => OnboardingTour.showIfNew(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 ИЗ 5'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }
    expect(find.text('5 ИЗ 5'), findsOneWidget);
    expect(find.text('Понятно'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.text('5 ИЗ 5'), findsNothing);

    // Seen once: opening it again shows nothing.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ИЗ 5'), findsNothing);
  });

  testWidgets('skipping counts as seen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => OnboardingTour.showIfNew(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ИЗ 5'), findsNothing);
  });
}
