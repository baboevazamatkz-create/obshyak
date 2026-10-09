import 'package:flutter/material.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../models/fines.dart';
import '../models/shared_budget.dart';
import '../theme.dart';

/// The notice for a fine still being voted on, with the buttons this phone
/// is allowed to press: the offender accepts or disputes, every other
/// flatmate sets it or cancels it, and whoever has already acted just sees
/// who the fine is waiting on.
class FineBanner extends StatelessWidget {
  final Expense fine;
  final String myName;

  /// A judge's vote: [kVoteYes] or [kVoteNo].
  final ValueChanged<String> onVote;

  /// The offender's answer: [kOffenderAccept] or [kOffenderDispute].
  final ValueChanged<String> onAnswer;

  const FineBanner({
    super.key,
    required this.fine,
    required this.myName,
    required this.onVote,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final ink = accentForeground(context);
    final amount = kBudgetCurrency.format.format(fine.amount);
    final offender = fine.offender ?? '';
    final iAmOffender = myName == offender;
    final disputed = fineIsDisputed(fine);
    final awaiting = fineAwaiting(fine);

    final String headline;
    if (iAmOffender) {
      headline = '${fine.author} предлагает оштрафовать вас на $amount';
    } else {
      headline = '${fine.author} предлагает штраф: $offender, $amount';
    }

    Widget actions;
    if (iAmOffender && fine.offenderVote == null) {
      actions = _buttons(
        context,
        yes: 'Принять',
        no: 'Оспорить',
        onYes: () => onAnswer(kOffenderAccept),
        onNo: () => onAnswer(kOffenderDispute),
      );
    } else if (!iAmOffender && fine.votes[myName] == null) {
      actions = _buttons(
        context,
        yes: 'Назначить',
        no: 'Отменить',
        onYes: () => onVote(kVoteYes),
        onNo: () => onVote(kVoteNo),
      );
    } else {
      actions = Text(
        'Ждём: ${awaiting.join(', ')}',
        style: TextStyle(fontSize: 12.5, color: ink.withValues(alpha: 0.6)),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: kPendingColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPendingColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 16, color: kPendingColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'За что: ${fine.note}',
            style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.8)),
          ),
          if (disputed) ...[
            const SizedBox(height: 4),
            Text(
              iAmOffender
                  ? 'Вы оспорили. Остальные голосуют заново'
                  : '$offender оспорил. Нужно подтвердить заново',
              style: const TextStyle(fontSize: 12.5, color: kPendingColor),
            ),
          ],
          const SizedBox(height: 8),
          actions,
        ],
      ),
    );
  }

  Widget _buttons(
    BuildContext context, {
    required String yes,
    required String no,
    required VoidCallback onYes,
    required VoidCallback onNo,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onNo,
            style: OutlinedButton.styleFrom(
              foregroundColor: expenseColor(context),
              side: BorderSide(
                color: expenseColor(context).withValues(alpha: 0.6),
              ),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(no),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: onYes,
            style: OutlinedButton.styleFrom(
              foregroundColor: incomeColor(context),
              side: BorderSide(
                color: incomeColor(context).withValues(alpha: 0.6),
              ),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(yes),
          ),
        ),
      ],
    );
  }
}
