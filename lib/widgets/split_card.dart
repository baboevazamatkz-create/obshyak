import 'package:flutter/material.dart';

import '../models/currency.dart';
import '../models/shared_budget.dart';
import '../models/shared_split.dart';
import '../theme.dart';

/// The flat's pool at the top of the list: what each flatmate put in, what
/// each spent, and what the whole flat spent split four ways.
class SplitCard extends StatelessWidget {
  final SharedPool pool;
  final AppCurrency currency;

  const SplitCard({super.key, required this.pool, required this.currency});

  @override
  Widget build(BuildContext context) {
    final ink = accentForeground(context);
    final muted = ink.withValues(alpha: 0.6);
    final leaders = pool.biggestContributors;
    final since = pool.since;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: heroGradientFor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            since == null
                ? 'ОБЩАК · С НАЧАЛА'
                : 'ОБЩАК · С ${_dateLabel(since).toUpperCase()}',
            style: microLabel(context,
                color: goldFor(context).withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 12),
          for (final person in pool.people)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                        ),
                        if (leaders.contains(person.name)) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: goldFor(context).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'больше вклад',
                              style: TextStyle(
                                fontSize: 10,
                                color: goldFor(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _Figure(
                      label: 'скинулся',
                      value: currency.format.format(person.contributed),
                      color: ink,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _Figure(
                      label: 'потратил',
                      value: currency.format.format(person.spent),
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          Divider(color: hairlineColor(context), height: 22),
          _Line(
            label: 'Потрачено всего',
            value: currency.format.format(pool.spentTotal),
            ink: ink,
          ),
          const SizedBox(height: 6),
          _Line(
            label: 'Каждому (всего ÷ $kRoommateCount)',
            value: currency.format.format(pool.perPerson),
            ink: ink,
          ),
          const SizedBox(height: 6),
          _Line(
            label: 'Осталось в общаке',
            value: currency.format.format(pool.remaining),
            ink: ink,
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

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Figure(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: accentForeground(context).withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final Color ink;

  const _Line({required this.label, required this.value, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: ink.withValues(alpha: 0.7),
            ),
          ),
        ),
        Text(
          value,
          style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
        ),
      ],
    );
  }
}
