import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../theme.dart';
import 'glass.dart';

final _dateFormat = DateFormat('d MMM', 'ru');

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  final AppCurrency currency;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The amount to display, if it differs from [expense.amount] -- used
  /// when the list is being viewed in a currency other than the one the
  /// expense was actually recorded in. [expense.amount] itself never
  /// changes; only the displayed figure does.
  final double? amountOverride;

  /// True when [amountOverride] is a currency conversion rather than the
  /// recorded amount, so the row can mark itself as approximate.
  final bool isApproximate;

  /// False in the grouped view, where the category header right above the
  /// row already carries that category's icon -- repeating the same icon
  /// on every row under it was the redundant part, not the row's own
  /// title. The title and note stay exactly as they are; only the
  /// leading icon (and the space it took) drops out.
  final bool showIcon;

  const ExpenseTile({
    super.key,
    required this.expense,
    required this.currency,
    this.onTap,
    this.onLongPress,
    this.amountOverride,
    this.isApproximate = false,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = expense.isIncome;
    final isTransfer = expense.isTransfer;
    final accent = isTransfer
        ? goldFor(context)
        : isIncome
            ? incomeColor(context)
            : expenseColor(context);
    final icon = isTransfer
        ? Icons.swap_horiz_rounded
        : isIncome
            ? Icons.arrow_downward_rounded
            : Icons.shopping_basket_outlined;
    final title = isTransfer
        ? '${expense.author} → ${expense.recipient ?? ''}'
        : isIncome
            ? 'Доход'
            : (expense.note.isNotEmpty ? expense.note : 'Покупка');
    final details = [
      if (isTransfer) 'вернул долг',
      if (!isTransfer && expense.author.isNotEmpty) expense.author,
      if (isIncome && expense.note.isNotEmpty) expense.note,
      if (expense.personal > 0)
        'личное ${currency.format.format(expense.personal)}',
      if (expense.receiptId != null) 'чек',
    ].join(' · ');
    final sign = isTransfer ? '' : (isIncome ? '+' : '−');
    final displayAmount = amountOverride ?? expense.amount;
    final approxPrefix = isApproximate ? '≈ ' : '';
    final ink = accentForeground(context);

    return GlassPanel(
      radius: 14,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.fromLTRB(showIcon ? 10 : 14, 6, 14, 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The amount is given a share of the row rather than whatever it
                // wants: a seven-digit sum on a small screen used to push the row
                // past its width. Inside that share it scales down to fit, so it
                // stays readable instead of being clipped.
                final amountMaxWidth = constraints.maxWidth * 0.42;
                return Row(
                  children: [
                    if (showIcon) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: 0.22),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: accent, size: 15),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1,
                              color: ink.withValues(alpha: 0.92),
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              details,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.15,
                                fontWeight: FontWeight.w400,
                                color: ink.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: amountMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$approxPrefix$sign${currency.format.format(displayAmount)}',
                              maxLines: 1,
                              softWrap: false,
                              style: moneyStyle(
                                size: 13,
                                weight: FontWeight.w500,
                                color: accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              _dateFormat.format(expense.date).toUpperCase(),
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 7.2,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: ink.withValues(alpha: 0.52),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
