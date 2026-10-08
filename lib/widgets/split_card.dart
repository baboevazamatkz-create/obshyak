import 'package:flutter/material.dart';

import '../models/currency.dart';
import '../models/shared_budget.dart';
import '../models/shared_split.dart';
import '../theme.dart';

/// The flat's running total at the top of the list: what has been spent
/// since the last income, and what each of the [kRoommateCount] owes.
class SplitCard extends StatelessWidget {
  final SharedSplit split;
  final AppCurrency currency;

  const SplitCard({super.key, required this.split, required this.currency});

  @override
  Widget build(BuildContext context) {
    final since = split.since;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        gradient: heroGradientFor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'НА КАЖДОГО',
            style: microLabel(
              context,
              color: goldFor(context).withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currency.format.format(split.perPerson),
              style: moneyStyle(
                size: 34,
                color: accentForeground(context),
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Всего потрачено ${currency.format.format(split.total)} '
            '· делим на $kRoommateCount',
            style: TextStyle(
              fontSize: 13,
              color: accentForeground(context).withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            since == null
                ? 'Доходов ещё не было, считаем всё'
                : 'С последнего дохода: ${_dateLabel(since)}',
            style: TextStyle(
              fontSize: 12,
              color: accentForeground(context).withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}
