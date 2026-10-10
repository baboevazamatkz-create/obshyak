import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/models/away.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/expense_category.dart';
import 'package:expense_tracker/models/fines.dart';
import 'package:expense_tracker/models/scanned_transaction.dart';
import 'package:expense_tracker/models/shared_split.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/screens/camera_capture_screen.dart';
import 'package:expense_tracker/screens/home_screen.dart';
import 'package:expense_tracker/screens/name_picker_screen.dart';
import 'package:expense_tracker/theme.dart';
import 'package:expense_tracker/widgets/away_banner.dart';
import 'package:expense_tracker/widgets/expense_tile.dart';
import 'package:expense_tracker/widgets/fine_banner.dart';
import 'package:expense_tracker/widgets/fine_sheet.dart';
import 'package:expense_tracker/widgets/glass.dart';
import 'package:expense_tracker/widgets/scan_review_sheet.dart';
import 'package:expense_tracker/widgets/split_card.dart';
import 'package:expense_tracker/widgets/tour.dart';

/// The smallest phone the flat is likely to own (320 x 568, an iPhone SE of
/// the first generation), at the largest text size the app allows, and the
/// same with the keyboard up. Flutter reports any overflow as an error, so a
/// screen that does not fit fails here instead of on someone's phone.
const _phones = {
  'small phone': Size(320, 568),
  'common phone': Size(390, 844),
  'tablet': Size(820, 1180),
};

Future<void> _fit(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1.25,
  double keyboard = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(Brightness.dark),
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: inner!,
    ),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

Expense _buy(String who, double amount) => Expense(
      id: '$who$amount',
      amount: amount,
      date: DateTime(2026, 10, 1),
      author: who,
      note: 'Продукты на неделю в Магнуме, большой список',
      personal: 1250,
      receiptId: 'r',
      currency: AppCurrency.kzt,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final phone in _phones.entries) {
    final size = phone.value;

    group(phone.key, () {
      testWidgets('the pool card with every kind of row', (tester) async {
        final records = [
          _buy('Мухаммад', 1234567),
          _buy('Азамат', 987654),
          Expense(
            id: 'fine',
            amount: 150000,
            date: DateTime(2026, 10, 2),
            author: 'Аслан',
            offender: 'Имран',
            offenderVote: kOffenderAccept,
            votes: const {
              'Азамат': kVoteYes,
              'Аслан': kVoteYes,
              'Мухаммад': kVoteYes,
            },
            currency: AppCurrency.kzt,
            type: TransactionType.fine,
          ),
        ];
        final pending = Expense(
          id: 'sent',
          amount: 300000,
          date: DateTime(2026, 10, 3),
          author: 'Имран',
          recipient: 'Мухаммад',
          confirmed: false,
          currency: AppCurrency.kzt,
          type: TransactionType.transfer,
        );
        await _fit(
          tester,
          SingleChildScrollView(
            child: SplitCard(
              pool: sharedPool([...records, pending]),
              currency: AppCurrency.kzt,
              myName: 'Имран',
              pending: [pending],
              onPaid: (_) {},
              onConfirm: (_) {},
              onOffset: (_) {},
            ),
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a fine notice with its buttons', (tester) async {
        await _fit(
          tester,
          FineBanner(
            fine: Expense(
              id: 'f',
              amount: 1500000,
              date: DateTime(2026, 10, 2),
              note: 'Не помыл посуду после ужина, третий раз за неделю',
              author: 'Мухаммад',
              offender: 'Азамат',
              votes: const {'Мухаммад': kVoteYes},
              offenderVote: kOffenderDispute,
              currency: AppCurrency.kzt,
              type: TransactionType.fine,
            ),
            myName: 'Аслан',
            onVote: (_) {},
            onAnswer: (_) {},
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('list rows of every kind', (tester) async {
        await _fit(
          tester,
          ListView(
            children: [
              ExpenseTile(
                expense: _buy('Мухаммад', 1234567),
                currency: AppCurrency.kzt,
              ),
              ExpenseTile(
                expense: Expense(
                  id: 'o',
                  amount: 25000,
                  date: DateTime(2026, 10, 3),
                  author: 'Мухаммад',
                  recipient: 'Азамат',
                  currency: AppCurrency.kzt,
                  type: TransactionType.offset,
                ),
                currency: AppCurrency.kzt,
              ),
            ],
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });

      for (final keyboard in [0.0, 300.0]) {
        testWidgets('the scan sheet, keyboard ${keyboard > 0 ? 'up' : 'down'}',
            (tester) async {
          await _fit(
            tester,
            Align(
              alignment: Alignment.bottomCenter,
              child: GlassSheet(
                child: ScanReviewSheet(
                  result: ScanResult(
                    document: ScanDocument.receipt,
                    transactions: [
                      for (var i = 0; i < 6; i++)
                        ScannedTransaction(
                          type: TransactionType.expense,
                          amount: 123456,
                          currency: AppCurrency.kzt,
                          date: DateTime(2026, 10, 1),
                          note: 'Сыр, молоко, хлеб и всякое по мелочи',
                          category: ExpenseCategory.food,
                          personal: 1500,
                        ),
                    ],
                  ),
                  currency: AppCurrency.kzt,
                  duplicates: const {},
                  onConfirm: (_) {},
                ),
              ),
            ),
            size: size,
            keyboard: keyboard,
          );
          expect(tester.takeException(), isNull);
          // The button stays above the keyboard.
          final button = tester.getRect(find.byType(ElevatedButton));
          expect(button.bottom, lessThanOrEqualTo(size.height - keyboard));
        });
      }

      testWidgets('the fine form with the keyboard up', (tester) async {
        await _fit(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: GlassSheet(
              child: FineSheet(myName: 'Мухаммад', onSubmit: (_) {}),
            ),
          ),
          size: size,
          keyboard: 300,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the longest name with the away switch in the app bar',
          (tester) async {
        for (final status in AwayStatus.values) {
          await _fit(
            tester,
            Column(
              children: [
                AppBar(
                  title: HomeTitle(
                    name: 'Мухаммад',
                    away: status,
                    onAway: () {},
                  ),
                  titleSpacing: 24,
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.history_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
            size: size,
          );
        }
      });

      testWidgets('an away request with its buttons', (tester) async {
        await _fit(
          tester,
          SingleChildScrollView(
            child: AwayBanner(
              request: AwayRequest(
                name: 'Мухаммад',
                since: DateTime(2026, 10, 1),
                approvers: const ['Азамат', 'Аслан', 'Имран'],
              ),
              myName: 'Азамат',
              onVote: (_) {},
              onDismiss: () {},
            ),
          ),
          size: size,
        );
      });

      testWidgets('the name picker', (tester) async {
        await _fit(tester, NamePickerScreen(onPicked: (_) {}), size: size);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the camera screen without a camera', (tester) async {
        await _fit(
          tester,
          CameraCaptureScreen(
            loadCameras: () async => <CameraDescription>[],
            pickFromGallery: () async => <Uint8List>[],
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the tour card', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await _fit(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => OnboardingTour.showIfNew(context),
              child: const Text('open'),
            ),
          ),
          size: size,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }
}
