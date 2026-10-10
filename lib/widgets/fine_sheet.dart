import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/currency.dart';
import '../models/expense.dart';
import '../models/fines.dart';
import '../models/shared_budget.dart';
import '../models/transaction_type.dart';
import '../theme.dart';

/// What a fine is when nobody types a different amount.
const double kDefaultFine = 5000;

/// Proposes a fine: whom, how much, and what for. Whoever proposes it has
/// voted yes already; the rest of the flat decides. Anyone can be fined,
/// the proposer included.
class FineSheet extends StatefulWidget {
  final String myName;
  final ValueChanged<Expense> onSubmit;

  /// Who lives in the flat now. Only they can be fined, and only they
  /// decide: someone away is out of new fines entirely.
  final List<String> members;

  const FineSheet({
    super.key,
    required this.myName,
    required this.onSubmit,
    this.members = kRoommates,
  });

  @override
  State<FineSheet> createState() => _FineSheetState();
}

class _FineSheetState extends State<FineSheet> {
  final _amount = TextEditingController(text: kDefaultFine.toInt().toString());
  final _reason = TextEditingController();
  String? _offender;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(
      _amount.text.replaceAll(' ', '').replaceAll(',', '.'),
    );
    final reason = _reason.text.trim();
    if (_offender == null) {
      setState(() => _error = 'Выберите, кого штрафуете');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Введите сумму');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Напишите, за что');
      return;
    }
    // Fining yourself is owning up: your answer is already "accept", and
    // the other three only decide whether it stands.
    final self = _offender == widget.myName;
    widget.onSubmit(Expense(
      id: const Uuid().v4(),
      amount: amount,
      date: DateTime.now(),
      note: reason,
      currency: kBudgetCurrency,
      type: TransactionType.fine,
      author: widget.myName,
      offender: _offender,
      votes: self ? const {} : {widget.myName: kVoteYes},
      offenderVote: self ? kOffenderAccept : null,
      members: widget.members,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ШТРАФ',
              style: microLabel(
                context,
                color: goldFor(context).withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in widget.members)
                  ChoiceChip(
                    label: Text(name == widget.myName ? '$name (я)' : name),
                    selected: _offender == name,
                    onSelected: (_) => setState(() {
                      _offender = name;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Сумма, ${kBudgetCurrency.symbol}',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'За что, например «не помыл посуду»',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: expenseColor(context), fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Предложить штраф'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Штраф вступит в силу, когда остальные проголосуют за, '
              'а штрафник ответит.',
              style: TextStyle(
                fontSize: 12,
                color: accentForeground(context).withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
