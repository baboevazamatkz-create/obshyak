import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/scanned_transaction.dart';
import '../models/transaction_type.dart';
import '../theme.dart';
import 'amount_format.dart';

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

  /// A selected row whose personal part is larger than its amount, or a
  /// negative amount, cannot be written down as it stands.
  bool _rowInvalid(ScannedTransaction row) =>
      row.amount <= 0 || row.personal < 0 || row.personal > row.amount;

  bool get _canConfirm =>
      _selected.isNotEmpty && _selected.every((i) => !_rowInvalid(_rows[i]));

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

  /// Writes an edit straight into the row and ticks it, since a row that
  /// is being corrected is one the user means to keep.
  void _update(int index, ScannedTransaction row) {
    setState(() {
      _rows[index] = row;
      _selected.add(index);
    });
  }

  void _confirm() {
    if (!_canConfirm) return;
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

    final media = MediaQuery.of(context);
    // The rows hold text fields, so the on-screen keyboard comes up over
    // the sheet: it is lifted above the keyboard and shrinks to the space
    // left, rather than leaving the fields and the button underneath it.
    final keyboard = media.viewInsets.bottom;
    return ConstrainedBox(
      // Forty rows would otherwise push the sheet to the top of the
      // screen, leaving nothing of the budget behind it to orient by.
      constraints: BoxConstraints(
        maxHeight: (media.size.height - keyboard) * 0.9 + keyboard,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: (keyboard > 0 ? keyboard : media.padding.bottom) + 18,
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
                    key: ValueKey(index),
                    row: _rows[index],
                    currency: widget.currency,
                    selected: _selected.contains(index),
                    duplicate: widget.duplicates.contains(index),
                    invalid: _rowInvalid(_rows[index]),
                    onToggle: () => _toggle(index),
                    onChanged: (row) => _update(index, row),
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
                      onPressed: _canConfirm ? _confirm : null,
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
  final bool invalid;
  final VoidCallback onToggle;
  final ValueChanged<ScannedTransaction> onChanged;

  const _ScanRow({
    super.key,
    required this.row,
    required this.currency,
    required this.selected,
    required this.duplicate,
    required this.invalid,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(context),
        // Always open: every field of the record is in front of the user,
        // so a personal part, a name or a date is set right here.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _RowEditor(
            row: row,
            currency: currency,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context) {
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
      if (row.personal > 0) 'лично ${currency.format.format(row.personal)}',
      if (invalid) 'проверьте сумму',
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
                  color: invalid
                      ? goldFor(context)
                      : isIncome
                          ? incomeColor(context)
                          : ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The fields of a scanned row, edited where it sits in the sheet: amount,
/// the part that was for the person alone (kept out of the flat's split),
/// the note and the date. Every change goes straight back into the row.
class _RowEditor extends StatefulWidget {
  final ScannedTransaction row;
  final AppCurrency currency;
  final ValueChanged<ScannedTransaction> onChanged;

  const _RowEditor({
    required this.row,
    required this.currency,
    required this.onChanged,
  });

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final TextEditingController _amount = TextEditingController(
    text: _formatAmount(widget.row.amount),
  );
  late final TextEditingController _personal = TextEditingController(
    text: widget.row.personal > 0 ? _formatAmount(widget.row.personal) : '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.row.note,
  );

  @override
  void dispose() {
    _amount.dispose();
    _personal.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Whole tenge, grouped: 12500 reads "12 500". The fields take no
  /// hundredths, so a fractional amount from the scanner shows rounded.
  static String _formatAmount(double value) =>
      groupThousands(value.round().toString());

  /// Reads a sum typed with the thousands spaces in it: "12 500".
  static double? _parse(String text) =>
      double.tryParse(text.replaceAll(' ', '').trim());

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final ink = accentForeground(context);
    final amount = _parse(_amount.text);
    final personal =
        _personal.text.trim().isEmpty ? 0.0 : _parse(_personal.text);
    final personalError = personal == null
        ? 'Введите сумму'
        : (amount != null && personal > amount)
            ? 'Не больше суммы чека'
            : null;
    final amountError = amount == null || amount <= 0 ? 'Введите сумму' : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sheetSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairlineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [WholeAmountFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Сумма, ${widget.currency.symbol}',
                    errorText: amountError,
                  ),
                  onChanged: (_) => _push(row),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _personal,
                  keyboardType: TextInputType.number,
                  inputFormatters: [WholeAmountFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Лично, не в общак',
                    errorText: personalError,
                  ),
                  onChanged: (_) => _push(row),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Название траты'),
            onChanged: (_) => _push(row),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 16, color: ink),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: row.date,
                    firstDate: DateTime(DateTime.now().year - 5),
                    lastDate: DateTime.now(),
                  );
                  if (picked == null || !context.mounted) return;
                  widget.onChanged(row.copyWith(date: picked));
                },
                child: Text(_rowDate.format(row.date)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Passes the fields on as they stand, read from the boxes at the moment
  /// of the change. A field that does not read as a sum yet keeps the row's
  /// last good value underneath, so the row never holds nonsense; the error
  /// text says what is missing.
  void _push(ScannedTransaction row) {
    final amount = _parse(_amount.text);
    final personal =
        _personal.text.trim().isEmpty ? 0.0 : _parse(_personal.text);
    widget.onChanged(row.copyWith(
      amount: amount ?? row.amount,
      personal: personal ?? row.personal,
      note: _note.text.trim(),
    ));
  }
}
