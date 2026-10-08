
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/models/category_group.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/household.dart';
import 'package:expense_tracker/models/transaction_type.dart';
import 'package:expense_tracker/models/expense_category.dart';
import 'package:expense_tracker/screens/home_screen.dart'
    show expenseTotals, monthDividerLabel;
import 'package:expense_tracker/screens/household_screen.dart';
import 'package:expense_tracker/screens/stats_screen.dart';
import 'package:expense_tracker/data/household_repository.dart';
import 'package:expense_tracker/data/widget_bridge.dart';
import 'package:expense_tracker/theme.dart';
import 'package:expense_tracker/widgets/readable_width.dart';
import 'package:expense_tracker/theme_mode_controller.dart';
import 'package:expense_tracker/widgets/add_expense_sheet.dart';
import 'package:expense_tracker/widgets/ai_scan_icon.dart';
import 'package:expense_tracker/widgets/expense_tile.dart';
import 'package:expense_tracker/widgets/glass.dart';
import 'package:expense_tracker/widgets/currency_symbol_icon.dart';
import 'package:expense_tracker/widgets/household_switcher_sheet.dart';
import 'package:expense_tracker/widgets/summary_card.dart';

/// Screen sizes worth covering: a small budget phone, a common modern phone
/// and a tablet.
const _screenSizes = <String, Size>{
  'small phone': Size(320, 534),
  'modern phone': Size(411, 891),
  'phone landscape': Size(891, 411),
  'tablet': Size(800, 1280),
};

/// The range the app clamps the system font scale to, plus the default.
const _textScales = <double>[0.85, 1.0, 1.25];

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required double textScale,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: inner!,
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

/// Runs [build] on every screen size and font scale combination and fails if
/// any of them overflows or otherwise throws while laying out.
void testAcrossScreens(String description, Widget Function() build) {
  for (final entry in _screenSizes.entries) {
    for (final scale in _textScales) {
      testWidgets('$description — ${entry.key} @ ${scale}x', (tester) async {
        await _pumpAt(tester, build(), size: entry.value, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // The app follows the system theme, so every screen has to survive the dark
  // one too.
  testWidgets('$description — dark theme', (tester) async {
    await _pumpAt(
      tester,
      build(),
      size: _screenSizes['modern phone']!,
      textScale: 1.0,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('Household screen offers create and join actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HouseholdScreen(onReady: (_) {}),
      ),
    );

    expect(find.text('Единый ритм\nмалых финансов'), findsOneWidget);
    expect(find.text('Создать новый бюджет'), findsOneWidget);
    expect(find.text('Присоединиться по коду'), findsOneWidget);
  });

  testWidgets('The brand stands on both ways into the budget screen',
      (tester) async {
    // canCancel is the difference between the first run and "add another
    // budget" from the switcher. The wordmark was moved out of the
    // first-run-only block and the line under it was left behind, so the
    // second path showed a name with nothing beneath it -- which is most
    // of the time, since it is the path anyone with a budget takes.
    for (final canCancel in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: HouseholdScreen(canCancel: canCancel, onReady: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ОБЩАК'), findsOneWidget,
          reason: 'wordmark missing with canCancel: $canCancel');
      expect(find.text('Единый ритм\nмалых финансов'), findsOneWidget,
          reason: 'tagline missing with canCancel: $canCancel');
    }
  });

  testWidgets('A faded list keeps its scroll position while it scrolls',
      (tester) async {
    // The fade used to be added and removed around the scroll view as the
    // offset crossed a threshold. That re-parented the CustomScrollView,
    // which built a fresh Scrollable each time, threw the position away and
    // left the list jumping instead of scrolling.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopFadeMask(
            controller: controller,
            child: ListView.builder(
              controller: controller,
              itemCount: 60,
              itemBuilder: (context, index) =>
                  SizedBox(height: 50, child: Text('row $index')),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(controller.offset, 120);

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(controller.offset, 200);

    // ...and back to the top leaves it exactly there, not bouncing.
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('Theme toggle flips away from what is currently on screen',
      (tester) async {
    // While the app is still following the system, the first tap has to
    // invert the brightness the user is actually looking at -- not the
    // stored ThemeMode, which is neither light nor dark at that point.
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => ThemeModeController.mode.value = ThemeMode.system);
    ThemeModeController.mode.value = ThemeMode.system;

    late BuildContext darkContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Builder(builder: (context) {
          darkContext = context;
          return const SizedBox();
        }),
      ),
    );
    // MaterialApp lerps between themes, so the first frame after a pump
    // still reports the previous brightness.
    await tester.pumpAndSettle();
    await ThemeModeController.toggle(darkContext);
    expect(ThemeModeController.mode.value, ThemeMode.light);

    late BuildContext lightContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(builder: (context) {
          lightContext = context;
          return const SizedBox();
        }),
      ),
    );
    await tester.pumpAndSettle();
    await ThemeModeController.toggle(lightContext);
    expect(ThemeModeController.mode.value, ThemeMode.dark);
  });

  testWidgets('Budget switcher icons stay visible on the dark theme',
      (tester) async {
    // The sheet is drawn in the champagne accent rather than the near-black
    // ink, which used to disappear into the dark background entirely -- and
    // on dark it is the *lighter* champagne, since the deep one goes muddy
    // against near-black.
    await _pumpAt(
      tester,
      Scaffold(
        body: HouseholdSwitcherSheet(
          households: const [
            Household(code: 'ABCD2345', label: 'Семья'),
            Household(code: 'EFGH6789', label: 'Работа'),
          ],
          activeCode: 'ABCD2345',
          currencies: const {
            'ABCD2345': AppCurrency.rub,
            'EFGH6789': AppCurrency.usd,
          },
          onSwitch: (_) {},
          onAddHousehold: () {},
          onLeave: (_) {},
        ),
      ),
      size: _screenSizes['modern phone']!,
      textScale: 1.0,
      brightness: Brightness.dark,
    );

    final checkIcon = tester.widget<Icon>(
      find.byIcon(Icons.check_circle_rounded),
    );
    expect(checkIcon.color, kChampagne);

    // The coin icon was replaced by the currency's own symbol (see
    // CurrencySymbolIcon); check that took the same colour.
    final symbolText = tester.widget<Text>(
      find.descendant(
        of: find.byType(CurrencySymbolIcon).first,
        matching: find.byType(Text),
      ),
    );
    expect(symbolText.style?.color, kChampagne);
  });

  testWidgets(
      'Budget switcher shows each budget\'s own currency, not the active one',
      (tester) async {
    // A ruble budget and a dollar budget in the same list: the icon on
    // each row must match that row's own currency, not whichever budget
    // happens to be open (activeCode is the ruble one here).
    await _pumpAt(
      tester,
      Scaffold(
        body: HouseholdSwitcherSheet(
          households: const [
            Household(code: 'ABCD2345', label: 'Семья'),
            Household(code: 'EFGH6789', label: 'Доллары'),
          ],
          activeCode: 'ABCD2345',
          currencies: const {
            'ABCD2345': AppCurrency.rub,
            'EFGH6789': AppCurrency.usd,
          },
          onSwitch: (_) {},
          onAddHousehold: () {},
          onLeave: (_) {},
        ),
      ),
      size: _screenSizes['modern phone']!,
      textScale: 1.0,
    );

    final symbols = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(CurrencySymbolIcon),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .toList();
    expect(
        symbols,
        containsAll(<String>[
          AppCurrency.rub.symbol,
          AppCurrency.usd.symbol,
        ]));
  });

  testAcrossScreens(
    'Household screen lays out',
    () => HouseholdScreen(onReady: (_) {}),
  );

  testAcrossScreens(
    'Summary card lays out with large amounts',
    () => const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: SummaryCard(
          todayExpenseTotal: 1234567,
          todayIncomeTotal: 7654321,
          monthExpenseTotal: 98765432,
          monthIncomeTotal: 12345678,
          allExpenseTotal: 987654321,
          allIncomeTotal: 123456789,
          currency: AppCurrency.kzt,
        ),
      ),
    ),
  );

  testAcrossScreens(
    'Expense row lays out with a long note',
    () => Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ExpenseTile(
          expense: Expense(
            id: 'a',
            amount: 12345678,
            date: DateTime(2026, 1, 15),
            category: ExpenseCategory.entertainment,
            note: 'Очень длинная заметка, которая точно не помещается в строку',
            type: TransactionType.expense,
          ),
          currency: AppCurrency.kzt,
        ),
      ),
    ),
  );

  testAcrossScreens(
    'Budget switcher lays out with a long budget name',
    () => Scaffold(
      body: HouseholdSwitcherSheet(
        households: const [
          Household(
            code: 'ABCD2345',
            label: 'Очень длинное название общего семейного бюджета',
          ),
          Household(code: 'EFGH6789', label: 'Работа'),
        ],
        activeCode: 'ABCD2345',
        currencies: const {
          'ABCD2345': AppCurrency.kzt,
          'EFGH6789': AppCurrency.rub,
        },
        onSwitch: (_) {},
        onAddHousehold: () {},
        onLeave: (_) {},
      ),
    ),
  );

  testWidgets('A budget can be left, and the code is shown before it goes',
      (tester) async {
    String? left;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSwitcherSheet(
            households: const [
              Household(code: 'ABCD2345', label: 'Казахстан'),
              Household(code: 'EFGH6789', label: 'Работа'),
            ],
            activeCode: 'ABCD2345',
            onSwitch: (_) {},
            onAddHousehold: () {},
            onLeave: (code) => left = code,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти из бюджета'));
    await tester.pumpAndSettle();

    // The code is the only way back in, so it is put in front of the user
    // at the moment they are about to lose it.
    expect(find.text('EFGH6789'), findsWidgets);
    expect(find.textContaining('Записи в нём останутся'), findsOneWidget);
    // Two budgets, so nothing about being the last one.
    expect(find.textContaining('единственный бюджет'), findsNothing);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(left, isNull);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти из бюджета'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(left, 'EFGH6789');
  });

  testWidgets('Leaving the last budget says what happens next', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSwitcherSheet(
            households: const [Household(code: 'ABCD2345', label: 'Дом')],
            activeCode: 'ABCD2345',
            onSwitch: (_) {},
            onAddHousehold: () {},
            onLeave: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти из бюджета'));
    await tester.pumpAndSettle();

    expect(find.textContaining('единственный бюджет'), findsOneWidget);
  });

  test('Leaving a budget forgets it here and nowhere else', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = HouseholdRepository();
    await repository.saveHouseholds(const [
      Household(code: 'ABCD2345', label: 'Дом'),
      Household(code: 'EFGH6789', label: 'Работа'),
    ]);
    await repository.setActiveCode('EFGH6789');

    await repository.removeHousehold('EFGH6789');

    expect(
      (await repository.loadHouseholds()).map((h) => h.code),
      ['ABCD2345'],
    );

    // The active code is the gate's own pointer; left dangling it would
    // send the app looking for a budget that is no longer in the list.
    await repository.clearActiveCode();
    expect(await repository.loadActiveCode(), isNull);
  });

  testWidgets('The scanner wears a mark that says what reads the snapshot',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: AiScanIcon()))),
    );

    // A capture frame with a spark inside it: one glyph says "point this
    // at something", the other says what happens next.
    expect(find.byIcon(Icons.crop_free_rounded), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });

  testAcrossScreens(
    'Add-budget screen lays out when opened from the switcher',
    () => HouseholdScreen(onReady: (_) {}, canCancel: true),
  );

  testAcrossScreens(
    'New expense sheet lays out with every category chip',
    () => const Scaffold(
      body: AddExpenseSheet(
        type: TransactionType.expense,
        currency: AppCurrency.kzt,
        onSubmit: _ignoreExpense,
      ),
    ),
  );

  testAcrossScreens(
    'New income sheet lays out',
    () => const Scaffold(
      body: AddExpenseSheet(
        type: TransactionType.income,
        currency: AppCurrency.rub,
        onSubmit: _ignoreExpense,
      ),
    ),
  );

  testAcrossScreens(
    'Income row lays out',
    () => Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ExpenseTile(
          expense: Expense(
            id: 'b',
            amount: 9876543,
            date: DateTime(2026, 9, 30),
            note: '',
            type: TransactionType.income,
          ),
          currency: AppCurrency.rub,
        ),
      ),
    ),
  );

  testAcrossScreens(
    'Category breakdown lays out with limits set',
    () => Scaffold(
      body: CategoriesTab(
        entries: _categoryEntries,
        currency: AppCurrency.kzt,
        budgetsStream: Stream.value({
          for (final entry in _categoryEntries)
            entry.key.storageKey: entry.value * 0.8,
        }),
        onEditBudget: _ignoreBudget,
      ),
    ),
  );

  testAcrossScreens(
    'Category breakdown lays out without limits',
    () => Scaffold(
      body: CategoriesTab(
        entries: _categoryEntries,
        currency: AppCurrency.rub,
        budgetsStream: Stream.value(const <String, double>{}),
        onEditBudget: _ignoreBudget,
      ),
    ),
  );

  testAcrossScreens(
    'Monthly history lays out',
    () => Scaffold(
      body: HistoryTab(
        monthlyTotals: _monthlyTotals,
        currency: AppCurrency.kzt,
        monthLabel: DateFormat('LLL', 'ru').format,
      ),
    ),
  );

  group('buildCategoryGroups', () {
    final september = DateTime(2026, 9);

    test('only includes expenses that fall within the given month', () {
      final inMonth = Expense(
        id: 'a',
        amount: 500,
        date: DateTime(2026, 9, 10),
        category: ExpenseCategory.food,
      );
      final outOfMonth = Expense(
        id: 'b',
        amount: 999,
        date: DateTime(2026, 8, 10),
        category: ExpenseCategory.food,
      );
      final groups = buildCategoryGroups(
        [inMonth, outOfMonth],
        month: september,
      );
      expect(groups, hasLength(1));
      expect(groups.single.items, [inMonth]);
      expect(groups.single.total, 500);
    });

    test('income forms its own group, listed first', () {
      final income = Expense(
        id: 'i',
        amount: 1000,
        date: DateTime(2026, 9, 3),
        type: TransactionType.income,
      );
      final food = Expense(
        id: 'f',
        amount: 300,
        date: DateTime(2026, 9, 3),
        category: ExpenseCategory.food,
      );
      final groups = buildCategoryGroups([food, income], month: september);
      expect(groups.first.label, 'Доход');
      expect(groups.first.total, 1000);
    });

    test('categories are ordered by total spent, highest first', () {
      final smallFood = Expense(
        id: 'f1',
        amount: 100,
        date: DateTime(2026, 9, 1),
        category: ExpenseCategory.food,
      );
      final bigTransport = Expense(
        id: 't1',
        amount: 5000,
        date: DateTime(2026, 9, 2),
        category: ExpenseCategory.transport,
      );
      final groups = buildCategoryGroups(
        [smallFood, bigTransport],
        month: september,
      );
      expect(groups.map((g) => g.label), ['Транспорт', 'Еда']);
    });

    test("sums every transaction in a category into that group's total", () {
      final a = Expense(
        id: 'a',
        amount: 100,
        date: DateTime(2026, 9, 1),
        category: ExpenseCategory.food,
      );
      final b = Expense(
        id: 'b',
        amount: 250,
        date: DateTime(2026, 9, 15),
        category: ExpenseCategory.food,
      );
      final groups = buildCategoryGroups([a, b], month: september);
      expect(groups.single.total, 350);
      expect(groups.single.items, hasLength(2));
    });

    test('a month with nothing recorded produces no groups', () {
      expect(buildCategoryGroups(<Expense>[], month: september), isEmpty);
    });
  });

  group('buildMonthSections', () {
    test('splits into one section per calendar month, newest first', () {
      final expenses = [
        Expense(
          id: 'a',
          amount: 100,
          date: DateTime(2026, 7, 5),
          category: ExpenseCategory.food,
        ),
        Expense(
          id: 'b',
          amount: 200,
          date: DateTime(2026, 9, 1),
          category: ExpenseCategory.food,
        ),
        Expense(
          id: 'c',
          amount: 300,
          date: DateTime(2026, 8, 20),
          category: ExpenseCategory.food,
        ),
      ];
      final sections = buildMonthSections(expenses);
      expect(sections.map((s) => s.month), [
        DateTime(2026, 9),
        DateTime(2026, 8),
        DateTime(2026, 7),
      ]);
    });

    test('is correctly ordered regardless of the input order', () {
      // buildMonthSections must not assume expenses arrive newest-first.
      final expenses = [
        Expense(
          id: 'old',
          amount: 100,
          date: DateTime(2026, 1, 1),
          category: ExpenseCategory.food,
        ),
        Expense(
          id: 'new',
          amount: 100,
          date: DateTime(2026, 12, 1),
          category: ExpenseCategory.food,
        ),
      ];
      final sections = buildMonthSections(expenses);
      expect(sections.first.month, DateTime(2026, 12));
      expect(sections.last.month, DateTime(2026, 1));
    });

    test("each section's groups never mix another month's spending in", () {
      final september = Expense(
        id: 'sep',
        amount: 1000,
        date: DateTime(2026, 9, 10),
        category: ExpenseCategory.food,
      );
      final august = Expense(
        id: 'aug',
        amount: 5000,
        date: DateTime(2026, 8, 10),
        category: ExpenseCategory.food,
      );
      final sections = buildMonthSections([september, august]);
      final septemberSection =
          sections.firstWhere((s) => s.month == DateTime(2026, 9));
      expect(septemberSection.groups.single.total, 1000);
      expect(septemberSection.groups.single.items, [september]);
    });

    test('an empty list produces no sections', () {
      expect(buildMonthSections(<Expense>[]), isEmpty);
    });
  });

  group('monthDividerLabel', () {
    test('omits the year for the current calendar year', () {
      final thisYear = DateTime(DateTime.now().year, 9, 1);
      expect(monthDividerLabel(thisYear), 'Сентябрь');
    });

    test('includes the year once it is not the current one', () {
      expect(monthDividerLabel(DateTime(2019, 3, 1)), 'Март 2019');
    });
  });

  group('convertApprox', () {
    test('same currency is returned unchanged, not just approximately equal',
        () {
      expect(convertApprox(12345, from: AppCurrency.usd, to: AppCurrency.usd),
          12345);
    });

    test('round-tripping through another currency returns to the original', () {
      const original = 50000.0;
      final toUsd =
          convertApprox(original, from: AppCurrency.rub, to: AppCurrency.usd);
      final back =
          convertApprox(toUsd, from: AppCurrency.usd, to: AppCurrency.rub);
      expect(back, closeTo(original, 0.001));
    });

    test('a dollar is worth many more tenge than one, in that direction', () {
      final kzt = convertApprox(1, from: AppCurrency.usd, to: AppCurrency.kzt);
      expect(kzt, greaterThan(100));
    });
  });

  group('expenseTotals', () {
    final now = DateTime(2026, 9, 14, 13);

    Expense at(DateTime date, double amount, {bool income = false}) => Expense(
          id: '${date.toIso8601String()}-$amount-$income',
          amount: amount,
          date: date,
          type: income ? TransactionType.income : TransactionType.expense,
          category: income ? null : ExpenseCategory.food,
        );

    final ledger = [
      at(DateTime(2026, 9, 14, 9), 300), // сегодня
      at(DateTime(2026, 9, 14, 11), 1000, income: true), // сегодня
      at(DateTime(2026, 9, 2), 700), // этот месяц, не сегодня
      at(DateTime(2026, 8, 30), 5000), // прошлый месяц
      at(DateTime(2025, 9, 14), 40, income: true), // тот же день год назад
    ];

    test('today is this month, this day, and nothing else', () {
      final totals = expenseTotals(ledger, now: now);
      expect(totals.todayExpense, 300);
      expect(totals.todayIncome, 1000);
    });

    test(
        'the month stops at the month, and the same day a year ago is not '
        'today', () {
      final totals = expenseTotals(ledger, now: now);
      expect(totals.monthExpense, 1000); // 300 + 700, без августовских 5000
      expect(totals.monthIncome, 1000);
    });

    test('all time counts everything, whatever month it fell in', () {
      final totals = expenseTotals(ledger, now: now);
      expect(totals.allExpense, 6000); // 300 + 700 + 5000
      expect(totals.allIncome, 1040); // 1000 + 40
    });

    test('an empty budget totals to zero rather than to nothing', () {
      final totals = expenseTotals(const [], now: now);
      expect(totals.allExpense, 0);
      expect(totals.allIncome, 0);
      expect(totals.monthExpense, 0);
      expect(totals.todayExpense, 0);
    });
  });

  testWidgets('The card carries all time as well as today and the month',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: SummaryCard(
            todayExpenseTotal: 300,
            todayIncomeTotal: 1000,
            monthExpenseTotal: 1000,
            monthIncomeTotal: 1000,
            allExpenseTotal: 6000,
            allIncomeTotal: 1040,
            currency: AppCurrency.rub,
          ),
        ),
      ),
    );

    expect(find.text('СЕГОДНЯ'), findsOneWidget);
    expect(find.text('ЗА МЕСЯЦ'), findsOneWidget);
    expect(find.text('ЗА ВСЁ ВРЕМЯ'), findsOneWidget);

    // Built through the formatter rather than typed out: it groups with
    // non-breaking spaces, which look identical in a source file and are
    // not the same character.
    String rub(double value) => AppCurrency.rub.format.format(value);

    // The all-time net is its own figure, not a repeat of the month's.
    expect(find.text('−${rub(4960)}'), findsOneWidget);
    expect(find.text('+${rub(1040)}'), findsOneWidget);
    expect(find.text('−${rub(6000)}'), findsOneWidget);
  });

  testWidgets('Summary card marks converted totals as approximate',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryCard(
            todayExpenseTotal: 1000,
            todayIncomeTotal: 2000,
            monthExpenseTotal: 1000,
            monthIncomeTotal: 2000,
            allExpenseTotal: 5000,
            allIncomeTotal: 9000,
            currency: AppCurrency.usd,
            isApproximate: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('≈'), findsWidgets);
  });

  testWidgets('Summary card does not mark exact totals as approximate',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryCard(
            todayExpenseTotal: 1000,
            todayIncomeTotal: 2000,
            monthExpenseTotal: 1000,
            monthIncomeTotal: 2000,
            allExpenseTotal: 5000,
            allIncomeTotal: 9000,
            currency: AppCurrency.rub,
          ),
        ),
      ),
    );
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('Expense row shows the override amount, not the recorded one',
      (tester) async {
    final expense = Expense(
      id: 'c',
      amount: 1000,
      date: DateTime(2026, 9, 1),
      category: ExpenseCategory.food,
      type: TransactionType.expense,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseTile(
            expense: expense,
            currency: AppCurrency.usd,
            amountOverride: 11.63,
            isApproximate: true,
          ),
        ),
      ),
    );
    // The recorded amount (1000 RUB) must not appear; only the converted
    // override, marked approximate, should render.
    expect(find.textContaining('1 000'), findsNothing);
    expect(find.textContaining('≈'), findsWidgets);
  });

  testWidgets(
      'Expense row hides its icon when told to, keeping the title and note',
      (tester) async {
    final withNote = Expense(
      id: 'd',
      amount: 500,
      date: DateTime(2026, 9, 1),
      category: ExpenseCategory.food,
      note: 'Кофе с собой',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseTile(
            expense: withNote,
            currency: AppCurrency.rub,
            showIcon: false,
          ),
        ),
      ),
    );
    // The category's icon (shown once already in the group header above
    // this row in the grouped view) does not repeat on the row itself...
    expect(find.byIcon(ExpenseCategory.food.icon), findsNothing);
    // ...but the row's own title and note still show.
    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Кофе с собой'), findsOneWidget);
  });

  testWidgets('Expense row shows its icon by default', (tester) async {
    final expense = Expense(
      id: 'e',
      amount: 500,
      date: DateTime(2026, 9, 1),
      category: ExpenseCategory.food,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseTile(expense: expense, currency: AppCurrency.rub),
        ),
      ),
    );
    expect(find.byIcon(ExpenseCategory.food.icon), findsOneWidget);
    expect(find.text('Еда'), findsOneWidget);
  });

  test('Income is the one group that has to be recoloured per theme', () {
    // buildCategoryGroups is a pure function with no BuildContext, so the
    // colour it stores is the light palette's. The flag is what lets the
    // grouped view swap in Obsidian's green instead of drawing Ivory's.
    final groups = buildCategoryGroups(
      [
        Expense(
            id: 'i',
            amount: 10,
            date: DateTime(2026, 9, 3),
            type: TransactionType.income),
        Expense(
            id: 'e',
            amount: 5,
            category: ExpenseCategory.food,
            date: DateTime(2026, 9, 3)),
      ],
      month: DateTime(2026, 9),
    );
    expect(groups.where((g) => g.isIncome).length, 1);
    expect(groups.firstWhere((g) => g.isIncome).label, 'Доход');
    expect(groups.where((g) => !g.isIncome).every((g) => !g.isIncome), isTrue);
  });

  testWidgets('The button row sits on the bottom edge, its buttons level',
      (tester) async {
    // Both halves of a regression: wrapping this row in a widget that
    // centres on both axes floated it to the middle of the screen, because
    // Scaffold hands the button slot loose constraints the size of the
    // whole scaffold. And the small button on the left has to line up with
    // the bottom of the tall one on the right, not with its middle.
    const clear = Key('clear');
    const income = Key('income');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ReadableWidth.maxWidth),
          child: const Padding(
            padding: EdgeInsets.only(left: 22, right: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(key: clear, width: 40, height: 40),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 56, height: 56),
                    SizedBox(height: 14),
                    SizedBox(key: income, width: 56, height: 56),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: const SizedBox.expand(),
      ),
    ));
    await tester.pumpAndSettle();

    final screenHeight = tester.getSize(find.byType(Scaffold)).height;
    final clearBottom = tester.getBottomLeft(find.byKey(clear)).dy;
    final incomeBottom = tester.getBottomLeft(find.byKey(income)).dy;

    expect(clearBottom, incomeBottom,
        reason: 'the two buttons share a bottom edge');
    expect(clearBottom, greaterThan(screenHeight - 40),
        reason: 'and that edge is near the bottom of the screen, not its '
            'middle');
  });

  testWidgets('The add sheet opens on the category it was handed',
      (tester) async {
    // What the home-screen widget's chip is for: it cannot record anything
    // itself, so it passes the category through and the sheet opens already
    // on it rather than on the default.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddExpenseSheet(
          type: TransactionType.expense,
          currency: AppCurrency.rub,
          initialCategory: ExpenseCategory.transport,
          onSubmit: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(ChoiceChip),
          ),
        );

    expect(chipFor(ExpenseCategory.transport.label).selected, isTrue);
    expect(chipFor(ExpenseCategory.food.label).selected, isFalse,
        reason: 'the default must give way to what was handed in');
  });

  testWidgets('The wordmark is set in the interface face, heavier and spaced out',
      (tester) async {
    late TextStyle style;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Builder(builder: (context) {
        style = wordmark(context, size: 36);
        return const SizedBox();
      }),
    ));
    expect(style.fontFamily, 'Onest');
    expect(style.fontWeight, FontWeight.w600);
    // Tracking is a share of the size, so the wordmark keeps its rhythm at
    // whichever of the two sizes it is drawn.
    expect(style.letterSpacing, closeTo(36 * 0.12, 0.001));
  });

  test('The widget writes the same document the app does', () {
    // SolidusWidgetProvider.kt builds an expense by hand, because it
    // records from a broadcast receiver with no Dart to call. Nothing in
    // Kotlin can be checked from here, but the field names can: if the
    // model gains or renames one, this fails and says where to go.
    const widgetWrites = {
      'id',
      'amount',
      'category',
      'note',
      'date',
      'currency',
      'type',
    };
    final json = Expense(
      id: 'x',
      amount: 1,
      date: DateTime(2026, 9, 13),
      category: ExpenseCategory.food,
    ).toJson();

    expect(json.keys.toSet(), widgetWrites,
        reason: 'android/app/src/main/kotlin/.../SolidusWidgetProvider.kt '
            'builds this document by hand and must be updated with it');
    // The two enums it also mirrors, by name and order.
    expect(ExpenseCategory.values.map((c) => c.storageKey).toList(), [
      'food',
      'transport',
      'housing',
      'entertainment',
      'health',
      'shopping',
      'other'
    ]);
    expect(TransactionType.values.map((t) => t.storageKey).toList(),
        ['expense', 'income']);
  });

  testWidgets('Amounts are grouped in threes as they are typed',
      (tester) async {
    // The widget groups its own pill the same way, with the same plain
    // space, so a figure does not look like two different conventions
    // depending on where it was entered. See grouped() in
    // SolidusWidgetProvider.kt.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AddExpenseSheet(
          type: TransactionType.expense,
          currency: AppCurrency.rub,
          onSubmit: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '1234567');
    await tester.pump();
    expect(find.text('1 234 567'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1234.5');
    await tester.pump();
    expect(find.text('1 234.5'), findsOneWidget,
        reason: 'only the whole part is grouped');
  });

  test('The widget reads the budget and currency under agreed key names', () {
    // Read natively out of FlutterSharedPreferences, where Flutter stores
    // them under a "flutter." prefix.
    expect(WidgetBridge.householdKey, 'widget_household_code');
    expect(WidgetBridge.currencyKey, 'widget_currency');
  });

  test('The reading width caps wide screens without pinching narrow ones', () {
    // A phone is narrower than the cap, so nothing about the current
    // layout changes; the cap only bites on tablets and desktop browsers.
    expect(ReadableWidth.maxWidth, greaterThan(430));
    expect(ReadableWidth.maxWidth, lessThan(768));
  });

  test('Each room sets the phone\'s bars to icons it can be read against', () {
    // Left alone, Flutter guesses the icon brightness from the app bar's
    // background colour, and a transparent bar reads as dark -- which put
    // white status icons on Ivory's paper.
    final ivory =
        buildAppTheme(Brightness.light).appBarTheme.systemOverlayStyle!;
    final obsidian =
        buildAppTheme(Brightness.dark).appBarTheme.systemOverlayStyle!;

    expect(ivory.statusBarIconBrightness, Brightness.dark);
    expect(ivory.systemNavigationBarIconBrightness, Brightness.dark);
    expect(obsidian.statusBarIconBrightness, Brightness.light);
    expect(obsidian.systemNavigationBarIconBrightness, Brightness.light);

    // Transparent on purpose: the page runs edge to edge behind both bars,
    // so their colour is the room's own rather than a second copy of it.
    for (final style in [ivory, obsidian]) {
      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
    }
  });

  testWidgets(
      'A fixed snackbar lifts the FAB slot, and nothing else in the Scaffold',
      (tester) async {
    // Why the clear button lives in the floatingActionButton slot rather
    // than as a Positioned child of the body: a fixed snackbar raises only
    // what Scaffold lays out as the FAB. As a body child the button stayed
    // where it was while the other two rose over the toast.
    final key = GlobalKey<ScaffoldMessengerState>();
    const inSlot = Key('in_fab_slot');
    const inBody = Key('in_body');

    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: key,
      home: const Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SizedBox(key: inSlot, width: 56, height: 56),
        body: Stack(
          children: [
            Positioned(
              left: 22,
              bottom: 16,
              child: SizedBox(key: inBody, width: 40, height: 40),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final slotBefore = tester.getBottomLeft(find.byKey(inSlot)).dy;
    final bodyBefore = tester.getBottomLeft(find.byKey(inBody)).dy;

    key.currentState!.showSnackBar(const SnackBar(
      content: Text('Удалено'),
      behavior: SnackBarBehavior.fixed,
    ));
    await tester.pumpAndSettle();

    expect(tester.getBottomLeft(find.byKey(inSlot)).dy, lessThan(slotBefore),
        reason: 'the FAB slot should rise above the snackbar');
    expect(tester.getBottomLeft(find.byKey(inBody)).dy, bodyBefore,
        reason: 'a body child stays put -- which is the bug being avoided');
  });
}

final _categoryEntries = <MapEntry<ExpenseCategory, double>>[
  for (final category in ExpenseCategory.values)
    MapEntry(category, 1234567.0 - category.index * 1000),
];

final _monthlyTotals = <MapEntry<DateTime, double>>[
  for (var i = 5; i >= 0; i--)
    MapEntry(DateTime(2026, 9 - i), 1234567.0 - i * 100000),
];

void _ignoreExpense(Expense expense) {}

void _ignoreBudget(ExpenseCategory category, double? current) {}
