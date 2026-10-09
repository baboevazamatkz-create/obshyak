import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/scanned_transaction.dart';
import '../models/transaction_type.dart';
import '../theme.dart';
import 'add_expense_sheet.dart';

final _rowDate = DateFormat('d MMM', 'ru');

/// What the scanner read, before any of it is written down.
///
/// Nothing here is a record yet: every row can be corrected, switched
/// between expense and income, or left out entirely. That is the whole
/// point of the screen -- a model reading a crumpled receipt will
/// occasionally be wrong, and a budget filled with silent guesses is worse
/// than one filled by hand.
class ScanReviewSheet extends StatefulWidget {
  final ScanResult result;
  final AppCurrency currency;

  /// Indexes into [ScanResult.transactions] that look to be in the budget
  /// already. Offered, but not ticked.
  final Set<int> duplicates;

  final void Function(List<Expense> expenses) onConfirm;

  const ScanReviewSheet({
    super.key,
    required this.result,
    required this.currency,
    required this.duplicates,
    required this.onConfirm,
  });

  @override
  State<ScanReviewSheet> createState() => _ScanReviewSheetState();
}

class _ScanReviewSheetState extends State<ScanReviewSheet> {
  late final List<ScannedTransaction> _rows =
      List.of(widget.result.transactions);
  late final Set<int> _selected = {
    for (var i = 0; i < _rows.length; i++)
      if (!widget.duplicates.contains(i)) i,
  };

  bool get _isEmpty => _rows.isEmpty;

  String get _title {
    if (_isEmpty) return 'НИЧЕГО НЕ НАЙДЕНО';
    switch (widget.result.document) {
      case ScanDocument.receipt:
        return 'ЧЕК РАЗОБРАН';
      case ScanDocument.statement:
        return 'ОПЕРАЦИИ СО СНИМКА';
      case ScanDocument.other:
        return 'ЧТО УДАЛОСЬ ПРОЧИТАТЬ';
    }
  }

  bool get _allSelected => _selected.length == _rows.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(List.generate(_rows.length, (i) => i));
      }
    });
  }

  void _toggle(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _flipType(int index) {
    final row = _rows[index];
    setState(() {
      _rows[index] = row.copyWith(
        type: row.type == TransactionType.expense
            ? TransactionType.income
            : TransactionType.expense,
      );
    });
  }

  Future<void> _edit(int index) async {
    final row = _rows[index];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sheetSurface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          // The ordinary editor, handed the scanned row as if it were an
          // existing record: one form to maintain instead of two, and the
          // corrections a user makes here look exactly like the ones they
          // make on the home screen.
          child: AddExpenseSheet(
            type: row.type,
            currency: widget.currency,
            existing: row.toExpense(householdCurrency: widget.currency),
            onSubmit: (edited) {
              setState(() {
                _rows[index] = row.copyWith(
                  amount: edited.amount,
                  category: edited.category ?? row.category,
                  note: edited.note,
                  date: edited.date,
                  personal: edited.personal,
                );
                _selected.add(index);
              });
            },
          ),
        ),
      ),
    );
  }

  void _confirm() {
    final chosen = [
      for (var i = 0; i < _rows.length; i++)
        if (_selected.contains(i))
          _rows[i].toExpense(householdCurrency: widget.currency),
    ];
    widget.onConfirm(chosen);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final gold = goldFor(context);

    return ConstrainedBox(
      // Forty rows would otherwise push the sheet to the top of the
      // screen, leaving nothing of the budget behind it to orient by.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).padding.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: accentForeground(context).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Two lines rather than one. Squeezed onto a single row, the
            // title, the count and the toggle ran 21 pixels past the edge
            // of a 320-wide phone and the title wrapped one letter per
            // line to make room.
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: microLabel(
                      context,
                      size: 11,
                      color: gold.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                if (!_isEmpty)
                  // A statement runs to dozens of rows; ticking them one
                  // by one to drop three of them is not a reasonable ask.
                  InkWell(
                    onTap: _toggleAll,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Text(
                        _allSelected ? 'СНЯТЬ ВСЕ' : 'ВЫБРАТЬ ВСЕ',
                        maxLines: 1,
                        style: microLabel(context, size: 10, color: gold),
                      ),
                    ),
                  ),
              ],
            ),
            if (!_isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ВЫБРАНО ${_selected.length} ИЗ ${_rows.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: microLabel(context, size: 10),
                ),
              ),
            const SizedBox(height: 14),
            if (_isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'На снимке не нашлось ни одной операции. Попробуйте снять '
                  'чек целиком, при ровном свете и без бликов.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: accentForeground(context).withValues(alpha: 0.75),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ScanRow(
                    row: _rows[index],
                    currency: widget.currency,
                    selected: _selected.contains(index),
                    duplicate: widget.duplicates.contains(index),
                    onToggle: () => _toggle(index),
                    onFlipType: () => _flipType(index),
                    onEdit: () => _edit(index),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_isEmpty ? 'Закрыть' : 'Отмена'),
                  ),
                ),
                if (!_isEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _selected.isEmpty ? null : _confirm,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_selected.length == 1
                            ? 'Добавить запись'
                            : 'Добавить ${_selected.length} ${_plural(_selected.length)}'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _plural(int count) {
  final mod100 = count % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'записей';
  switch (count % 10) {
    case 1:
      return 'запись';
    case 2:
    case 3:
    case 4:
      return 'записи';
    default:
      return 'записей';
  }
}

class _ScanRow extends StatelessWidget {
  final ScannedTransaction row;
  final AppCurrency currency;
  final bool selected;
  final bool duplicate;
  final VoidCallback onToggle;
  final VoidCallback onFlipType;
  final VoidCallback onEdit;

  const _ScanRow({
    required this.row,
    required this.currency,
    required this.selected,
    required this.duplicate,
    required this.onToggle,
    required this.onFlipType,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = row.type == TransactionType.income;
    final tint = isIncome ? incomeColor(context) : row.category.color;
    final ink = accentForeground(context);
    final note = row.note.isEmpty
        ? (isIncome ? 'Поступление' : row.category.label)
        : row.note;

    final subtitle = <String>[
      _rowDate.format(row.date),
      if (!isIncome) row.category.label,
      if (duplicate) 'похоже, уже есть',
      if (row.isUncertain) 'проверьте сумму',
    ].join(' · ');

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        // An unticked row stays legible but stops competing with the ones
        // that are actually going into the budget.
        opacity: selected ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: selected ? 0.07 : 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: tint.withValues(alpha: selected ? 0.26 : 0.12),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onToggle(),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              Icon(
                isIncome ? Icons.south_west_rounded : row.category.icon,
                size: 18,
                color: tint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: row.isUncertain || duplicate
                            ? goldFor(context)
                            : ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isIncome ? '+' : '−'}${currency.format.format(row.amount)}',
                style: moneyStyle(
                  size: 14,
                  weight: FontWeight.w500,
                  color: isIncome ? incomeColor(context) : ink,
                ),
              ),
              PopupMenuButton<_RowAction>(
                tooltip: 'Что сделать с записью',
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: ink.withValues(alpha: 0.6),
                ),
                onSelected: (action) {
                  switch (action) {
                    case _RowAction.edit:
                      onEdit();
                    case _RowAction.flip:
                      onFlipType();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _RowAction.edit,
                    child: Text('Изменить'),
                  ),
                  PopupMenuItem(
                    value: _RowAction.flip,
                    child: Text(isIncome ? 'Это расход' : 'Это доход'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RowAction { edit, flip }
