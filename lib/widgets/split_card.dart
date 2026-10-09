import 'package:flutter/material.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../models/shared_split.dart';
import '../theme.dart';

/// The flat's standing at the top of the list: what each flatmate paid for
/// everyone, where each stands against a fair quarter, and the transfers
/// that would even it out.
class SplitCard extends StatelessWidget {
  final SharedPool pool;
  final AppCurrency currency;

  /// The flatmate using this phone. Only the payer can say a transfer was
  /// sent, and only the recipient can confirm it arrived.
  final String myName;

  /// Transfers the payer marked as sent that are waiting on the recipient.
  final List<Expense> pending;

  /// The payer says they sent [Settlement].
  final ValueChanged<Settlement> onPaid;

  /// The recipient confirms a pending transfer arrived.
  final ValueChanged<Expense> onConfirm;

  const SplitCard({
    super.key,
    required this.pool,
    required this.currency,
    required this.myName,
    required this.pending,
    required this.onPaid,
    required this.onConfirm,
  });

  Expense? _pendingFor(Settlement settlement) {
    for (final transfer in pending) {
      if (transfer.author == settlement.from &&
          transfer.recipient == settlement.to) {
        return transfer;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ink = accentForeground(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        gradient: heroGradientFor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Spacer(flex: 4),
              Expanded(flex: 3, child: _Header('потратил')),
              Expanded(flex: 3, child: _Header('баланс')),
            ],
          ),
          for (final person in pool.people)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      person.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _Figure(
                      label: 'потратил',
                      value: currency.format.format(person.spent),
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
          Divider(color: hairlineColor(context), height: 12),
          _Line(
            label: 'Общие траты',
            value: currency.format.format(pool.sharedTotal),
            ink: ink,
          ),
          const SizedBox(height: 4),
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
            const SizedBox(height: 2),
            for (final settlement in pool.settlements)
              // Spaced apart so a thumb lands on one row, not between two.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
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
                    _action(context, settlement),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// What the row offers this phone: the payer marks it sent, the
  /// recipient confirms it, everyone else just sees where it stands.
  Widget _action(BuildContext context, Settlement settlement) {
    final waiting = _pendingFor(settlement);
    if (waiting == null) {
      if (myName == settlement.from) {
        return _SettleButton(
          label: 'Оплатить',
          color: kPayColor,
          onPressed: () => onPaid(settlement),
        );
      }
      return _Status(
          'не оплачено', accentForeground(context).withValues(alpha: 0.45));
    }
    if (myName == settlement.to) {
      return _SettleButton(
        label: 'Подтвердить',
        color: kPendingColor,
        filled: true,
        onPressed: () => onConfirm(waiting),
      );
    }
    return const _Status('ожидает', kPendingColor, filled: true);
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

/// A compact text button that tints only while pressed. On the web a
/// tapped button keeps focus after the dialog closes, and the default
/// focus tint read as a coloured fill.
class _SettleButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onPressed;

  const _SettleButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: filled ? const Color(0xFF141318) : color,
        backgroundColor: filled ? color : Colors.transparent,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? color.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Where a transfer stands, for whoever cannot act on it from this phone.
class _Status extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const _Status(this.text, this.color, {this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: filled
          ? BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Text(
        text,
        style:
            TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 10.5,
        color: accentForeground(context).withValues(alpha: 0.5),
      ),
    );
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
    return Tooltip(
      message: label,
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
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
