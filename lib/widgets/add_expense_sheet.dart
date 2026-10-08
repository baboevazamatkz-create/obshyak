import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../models/transaction_type.dart';
import '../theme.dart';
import 'currency_symbol_icon.dart';

final _dateFormat = DateFormat('d MMMM y', 'ru');

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d.,]'), '');
    final separatorMatch = RegExp(r'[.,]').firstMatch(cleaned);

    String integerPart;
    var separator = '';
    var decimalPart = '';
    if (separatorMatch != null) {
      integerPart = cleaned.substring(0, separatorMatch.start);
      separator = cleaned[separatorMatch.start];
      decimalPart = cleaned
          .substring(separatorMatch.start + 1)
          .replaceAll(RegExp(r'[.,]'), '');
    } else {
      integerPart = cleaned;
    }
    integerPart = integerPart.replaceAll(RegExp(r'[^\d]'), '');

    final result = '${_groupThousands(integerPart)}$separator$decimalPart';
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

class AddExpenseSheet extends StatefulWidget {
  final TransactionType type;
  final AppCurrency currency;
  final Expense? existing;
  final void Function(Expense expense) onSubmit;

  /// [existing] doubles as a draft's starting values -- the voice
  /// assistant's best guess at what was said, say -- without this the
  /// sheet has no way to tell "editing a real record" from "reviewing a
  /// guess before it becomes one": both prefill the same way, but only the
  /// former should read "Изменить" and reuse the record's own id.
  final bool isDraft;

  const AddExpenseSheet({
    super.key,
    required this.type,
    required this.currency,
    this.existing,
    this.isDraft = false,
    required this.onSubmit,
  });

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

/// Everything in this sheet is drawn at this fraction of its usual size.
/// It is a single-purpose form and was taking far more of the screen than
/// it needed to; one factor keeps every proportion intact instead of
/// nudging a dozen figures apart from each other. It went to 1/1.5 first,
/// which read as too small, and then back up by 1.2.
const double _kScale = 1.2 / 1.5;

double _s(double value) => value * _kScale;

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  /// The part of the receipt that was for the author alone. It stays out of
  /// what is split four ways.
  final _personalController = TextEditingController();
  String? _personalErrorText;
  DateTime _selectedDate = DateTime.now();
  String? _errorText;

  bool get _isEditing => widget.existing != null && !widget.isDraft;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      final rawAmount = existing.amount == existing.amount.roundToDouble()
          ? existing.amount.toInt().toString()
          : existing.amount.toString();
      final dotIndex = rawAmount.indexOf('.');
      _amountController.text = dotIndex == -1
          ? _groupThousands(rawAmount)
          : '${_groupThousands(rawAmount.substring(0, dotIndex))}${rawAmount.substring(dotIndex)}';
      _selectedDate = existing.date;
      _noteController.text = existing.note;
      if (existing.personal > 0) {
        _personalController.text = _groupThousands(
          existing.personal == existing.personal.roundToDouble()
              ? existing.personal.toInt().toString()
              : existing.personal.toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _personalController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  static double? _parseAmount(String text) =>
      double.tryParse(text.replaceAll(' ', '').replaceAll(',', '.').trim());

  void _submit() {
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _errorText = 'Введите корректную сумму');
      return;
    }
    var personal = 0.0;
    if (_personalController.text.trim().isNotEmpty) {
      final parsed = _parseAmount(_personalController.text);
      if (parsed == null || parsed < 0 || parsed > amount) {
        setState(() => _personalErrorText = 'Не больше суммы чека');
        return;
      }
      personal = parsed;
    }

    widget.onSubmit(
      Expense(
        id: _isEditing ? widget.existing!.id : const Uuid().v4(),
        amount: amount,
        // No category is picked any more; a scanned record keeps the one
        // the scanner gave it.
        category: widget.existing?.category,
        note: _noteController.text.trim(),
        date: _selectedDate,
        currency: widget.currency,
        type: widget.type,
        // Editing keeps who entered the record and its receipt; the sheet
        // itself does not know either of them.
        author: widget.existing?.author ?? '',
        receiptId: widget.existing?.receiptId,
        personal: widget.type == TransactionType.expense ? personal : 0,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final input = theme.inputDecorationTheme;
    final radius = BorderRadius.circular(_s(14));

    // The fields, the chips and the submit button take their metrics from
    // the app theme, so scaling only the numbers written here would shrink
    // the gaps and leave the controls full size. This override scales them
    // too, and stops at this sheet.
    return Theme(
      data: theme.copyWith(
        iconTheme: theme.iconTheme.copyWith(size: _s(24)),
        inputDecorationTheme: input.copyWith(
          contentPadding:
              EdgeInsets.symmetric(horizontal: _s(16), vertical: _s(15)),
          border: _scaledBorder(input.border, radius),
          enabledBorder: _scaledBorder(input.enabledBorder, radius),
          focusedBorder: _scaledBorder(input.focusedBorder, radius),
          hintStyle: input.hintStyle?.copyWith(fontSize: _s(16)),
          prefixIconConstraints:
              BoxConstraints(minWidth: _s(48), minHeight: _s(48)),
        ),
        chipTheme: theme.chipTheme.copyWith(
          padding: EdgeInsets.symmetric(horizontal: _s(8), vertical: _s(6)),
          labelPadding: EdgeInsets.symmetric(horizontal: _s(8)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: theme.elevatedButtonTheme.style?.copyWith(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: _s(22), vertical: _s(17)),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(
                fontFamily: 'Onest',
                fontSize: _s(15),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: radius),
            ),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: _s(20),
          right: _s(20),
          top: _s(20),
          bottom: MediaQuery.of(context).viewInsets.bottom + _s(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: _s(38),
                  height: _s(4),
                  margin: EdgeInsets.only(bottom: _s(22)),
                  decoration: BoxDecoration(
                    color: accentForeground(context).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(_s(2)),
                  ),
                ),
              ),
              Text(
                (_isEditing
                        ? (widget.type == TransactionType.expense
                            ? 'Изменить расход'
                            : 'Изменить доход')
                        : (widget.type == TransactionType.expense
                            ? 'Новый расход'
                            : 'Новый доход'))
                    .toUpperCase(),
                style: microLabel(
                  context,
                  size: _s(11),
                  color: goldFor(context).withValues(alpha: 0.9),
                ),
              ),
              SizedBox(height: _s(18)),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_ThousandsSeparatorFormatter()],
                autofocus: true,
                style: moneyStyle(
                  size: _s(26),
                  weight: FontWeight.w300,
                  color: accentForeground(context),
                  letterSpacing: -0.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Сумма, ${widget.currency.symbol}',
                  hintStyle: TextStyle(
                    fontSize: _s(20),
                    fontWeight: FontWeight.w300,
                    color: accentForeground(context).withValues(alpha: 0.4),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: _s(16),
                    vertical: _s(18),
                  ),
                  errorText: _errorText,
                  // The currency's own symbol, not a generic money icon --
                  // wrong to imply "dollar" when the budget is in rubles or
                  // tenge.
                  prefixIcon: CurrencySymbolIcon(
                      currency: widget.currency, size: _s(24)),
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              if (widget.type == TransactionType.expense) ...[
                SizedBox(height: _s(16)),
                TextField(
                  controller: _personalController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_ThousandsSeparatorFormatter()],
                  decoration: InputDecoration(
                    hintText: 'Из них лично, не в общак',
                    errorText: _personalErrorText,
                    prefixIcon:
                        Icon(Icons.person_outline_rounded, size: _s(20)),
                  ),
                  onChanged: (_) {
                    if (_personalErrorText != null) {
                      setState(() => _personalErrorText = null);
                    }
                  },
                ),
              ],
              SizedBox(height: _s(16)),
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  hintText: 'Что купили',
                  prefixIcon: Icon(Icons.edit_note_rounded, size: _s(24)),
                ),
              ),
              SizedBox(height: _s(16)),
              InkWell(
                borderRadius: radius,
                onTap: _pickDate,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: _s(16),
                    vertical: _s(14),
                  ),
                  decoration: BoxDecoration(
                    color: input.fillColor,
                    borderRadius: radius,
                    border: Border.all(color: hairlineColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: _s(18)),
                      SizedBox(width: _s(12)),
                      // A long month name at a large system font scale used to
                      // run past the edge of the row; the date shrinks to fit
                      // rather than being clipped.
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _dateFormat.format(_selectedDate),
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: _s(16),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: _s(24)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: widget.type == TransactionType.income
                      ? ElevatedButton.styleFrom(
                          backgroundColor: incomeColor(context),
                          foregroundColor: const Color(0xFFF6F2EA),
                        )
                      : null,
                  onPressed: _submit,
                  child: Text(_isEditing ? 'Сохранить' : 'Добавить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps an input border's own colours while giving it the sheet's radius.
InputBorder? _scaledBorder(InputBorder? border, BorderRadius radius) =>
    border is OutlineInputBorder
        ? border.copyWith(borderRadius: radius)
        : border;
