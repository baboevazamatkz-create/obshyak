import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/expense_repository.dart';
import '../models/currency.dart';
import '../models/expense.dart';
import '../models/history.dart';
import '../models/shared_budget.dart';
import '../theme.dart';
import '../widgets/app_background_pattern.dart';
import '../widgets/expense_tile.dart';
import '../widgets/readable_width.dart';
import '../widgets/receipt_dialog.dart';

final _dayFormat = DateFormat('d MMMM', 'ru');

/// Settled periods, newest first. Read-only: a period that is in history
/// has already been paid out, so nothing in it is edited or deleted here.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repository = ExpenseRepository();
  late final Stream<List<Expense>> _expenses =
      _repository.watchExpenses(kSharedBudgetCode);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История')),
      body: AppBackgroundPattern(
        child: ReadableWidth(
          child: StreamBuilder<List<Expense>>(
            stream: _expenses,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final periods = historyPeriods(snapshot.data!);
              if (periods.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Закрытых периодов пока нет.\n'
                      'Период уходит сюда, когда все в расчёте.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: accentForeground(context).withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  for (final period in periods) ..._period(context, period),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _period(BuildContext context, HistoryPeriod period) {
    final from = _dayFormat.format(period.from);
    final to = _dayFormat.format(period.to);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                from == to ? from : '$from – $to',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: goldFor(context),
                ),
              ),
            ),
            Text(
              'общие траты ${kBudgetCurrency.format.format(period.sharedTotal)}',
              style: TextStyle(
                fontSize: 13,
                color: accentForeground(context).withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      for (final expense in period.records)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: ExpenseTile(
            expense: expense,
            currency: kBudgetCurrency,
            onTap: expense.receiptId == null
                ? null
                : () => showReceiptDialog(
                      context,
                      _repository,
                      expense.receiptId!,
                    ),
          ),
        ),
    ];
  }
}
