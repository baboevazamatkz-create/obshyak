import 'package:flutter/material.dart';

import '../models/currency.dart';
import '../models/shared_budget.dart';
import '../models/shared_split.dart';
import '../theme.dart';

/// The flat's standing at the top of the list: what each flatmate paid for
/// everyone, where each stands against a fair quarter, and the transfers
/// that would even it out.
class SplitCard extends StatelessWidget {
  final SharedPool pool;
  final AppCurrency currency;

  /// Records that a suggested transfer has been paid.
  final ValueChanged<Settlement> onSettle;

  const SplitCard({
    super.key,
    required this.pool,
    required this.currency,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final ink = accentForeground(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: heroGradientFor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ОБЩАК',
            style: microLabel(
              context,
              color: goldFor(context).withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          for (final person in pool.people)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
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
                  Expanded(
                    flex: 3,
                    child: _Figure(
                      label: 'потратил',
                      value: currency.format.format(person.paid),
                      color: ink.withValues(alpha: 0.85),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _Figure(
                      label: _balanceLabel(person.balance),
                      value: _signed(person.balance),
                      color: _balanceColor(context, person.balance),
                    ),
                  ),
                ],
              ),
            ),
          Divider(color: hairlineColor(context), height: 20),
          _Line(
            label: 'Общие траты',
            value: currency.format.format(pool.sharedTotal),
            ink: ink,
          ),
          const SizedBox(height: 4),
          _Line(
            label: 'Доля каждого (÷ $kRoommateCount)',
            value: currency.format.format(pool.perPerson),
            ink: ink,
          ),
          const SizedBox(height: 12),
          if (pool.isSettled)
            Text(
              'Все в расчёте',
              style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.6)),
            )
          else ...[
            Text(
              'КТО КОМУ ПЕРЕВОДИТ',
              style: microLabel(
                context,
                color: goldFor(context).withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 6),
            for (final settlement in pool.settlements)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${settlement.from} → ${settlement.to}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: ink),
                    ),
                  ),
                  Text(
                    currency.format.format(settlement.amount),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => onSettle(settlement),
                    child: const Text('Оплачено'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  String _signed(double balance) {
    if (balance.abs() < kSettledThreshold) return currency.format.format(0);
    final sign = balance > 0 ? '+' : '−';
    return '$sign${currency.format.format(balance.abs())}';
  }

  static String _balanceLabel(double balance) {
    if (balance >= kSettledThreshold) return 'ему должны';
    if (balance <= -kSettledThreshold) return 'довнести';
    return 'в расчёте';
  }

  static Color _balanceColor(BuildContext context, double balance) {
    if (balance >= kSettledThreshold) return incomeColor(context);
    if (balance <= -kSettledThreshold) return expenseColor(context);
    return accentForeground(context).withValues(alpha: 0.6);
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Figure({
    required this.label,
    required this.value,
    required this.color,
  });

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
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
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
            style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.7)),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ],
    );
  }
}
