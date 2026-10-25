import 'package:flutter/material.dart';

import '../models/currency.dart';
import '../models/shared_budget.dart';
import '../models/shared_split.dart';
import 'amount_format.dart';

/// Asks how much of [debt] was sent: all of it, as filled in, or any part
/// up to it. Returns the amount, or null when cancelled.
///
/// Whatever is sent comes off the debt once the recipient confirms it, and
/// the rest stays owed. More than the debt is not taken: the overpayment
/// would turn into a debt the other way, which is never what was meant.
Future<double?> showPayDialog(BuildContext context, Settlement debt) =>
    showDialog<double>(
      context: context,
      builder: (_) => _PayDialog(debt: debt),
    );

class _PayDialog extends StatefulWidget {
  final Settlement debt;

  const _PayDialog({required this.debt});

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final _controller = TextEditingController(
    text: groupThousands(widget.debt.amount.round().toString()),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final amount = double.tryParse(_controller.text.replaceAll(' ', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Введите сумму');
      return;
    }
    if (amount > widget.debt.amount) {
      setState(() => _error = 'Не больше долга');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    final whole = kBudgetCurrency.format.format(debt.amount);
    return AlertDialog(
      title: const Text('Вернуть долг'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Вы должны ${debt.to} $whole. Можно вернуть и часть.'),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [WholeAmountFormatter()],
            decoration: InputDecoration(
              labelText: 'Сколько перевели, ${kBudgetCurrency.symbol}',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 8),
          Text(
            'Долг уменьшится, когда ${debt.to} подтвердит.',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(onPressed: _send, child: const Text('Отправил')),
      ],
    );
  }
}
