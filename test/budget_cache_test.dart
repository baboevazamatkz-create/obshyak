import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expense_tracker/data/budget_cache.dart';
import 'package:expense_tracker/models/away.dart';
import 'package:expense_tracker/models/currency.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/models/fines.dart';
import 'package:expense_tracker/models/transaction_type.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing saved reads as no cache', () async {
    expect(await BudgetCache.load(), isNull);
  });

  test('the open period and who is away come back as they were saved',
      () async {
    final records = [
      Expense(
        id: 'a',
        amount: 4519,
        personal: 500,
        note: 'Рыба',
        date: DateTime(2026, 10, 18, 9, 30),
        author: 'Аслан',
        currency: AppCurrency.kzt,
        receiptId: 'r1',
        members: const ['Азамат', 'Аслан', 'Мухаммад'],
      ),
      Expense(
        id: 'f',
        amount: 5000,
        note: 'посуда',
        date: DateTime(2026, 10, 17),
        author: 'Азамат',
        offender: 'Имран',
        votes: const {'Азамат': kVoteYes},
        currency: AppCurrency.kzt,
        type: TransactionType.fine,
      ),
    ];
    final away = AwayBook({
      'Имран': AwayRequest(
        name: 'Имран',
        since: DateTime(2026, 10, 1),
        approvers: const [],
      ),
    });

    await BudgetCache.save(records, away);
    final back = (await BudgetCache.load())!;

    expect(back.expenses, hasLength(2));
    final a = back.expenses.first;
    expect(a.amount, 4519);
    expect(a.personal, 500);
    expect(a.date, DateTime(2026, 10, 18, 9, 30));
    expect(a.members, ['Азамат', 'Аслан', 'Мухаммад']);
    expect(a.receiptId, 'r1');
    expect(back.expenses.last.votes, {'Азамат': kVoteYes});
    expect(back.expenses.last.offender, 'Имран');
    expect(back.away.isAway('Имран'), isTrue);
  });

  test('a cache that cannot be read is ignored', () async {
    SharedPreferences.setMockInitialValues({'budget_cache_v1': 'не json'});
    expect(await BudgetCache.load(), isNull);
  });
}
