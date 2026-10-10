import 'package:flutter/material.dart';

import '../models/away.dart';
import '../theme.dart';

/// The «Отпуск» switch beside the name in the app bar, showing where this
/// phone's flatmate stands: home, asking, or away.
class AwayButton extends StatelessWidget {
  final AwayStatus status;
  final VoidCallback onPressed;

  const AwayButton({super.key, required this.status, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final (label, color, filled) = switch (status) {
      AwayStatus.away => ('В отпуске', kPayColor, true),
      AwayStatus.pending => ('Ждём', kPendingColor, false),
      _ => ('Отпуск', accentForeground(context).withValues(alpha: 0.7), false),
    };
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.beach_access_rounded, size: 15),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: filled ? const Color(0xFF141318) : color,
        backgroundColor: filled ? color : Colors.transparent,
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        textStyle: const TextStyle(
          fontFamily: 'Onest',
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: filled
              ? BorderSide.none
              : BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

/// A request to go away that is still open, or this phone's own request
/// that was turned down: approvers agree or refuse here, the one asking
/// sees whom it waits on.
class AwayBanner extends StatelessWidget {
  final AwayRequest request;
  final String myName;

  /// An approver's answer: [kAwayYes] or [kAwayNo].
  final ValueChanged<String> onVote;

  /// The one asking has seen that it was turned down.
  final VoidCallback onDismiss;

  const AwayBanner({
    super.key,
    required this.request,
    required this.myName,
    required this.onVote,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final ink = accentForeground(context);
    final mine = request.name == myName;
    final rejected = request.status == AwayStatus.rejected;

    final String headline;
    if (rejected) {
      headline = '${request.rejectedBy.join(', ')} не согласовал ваш отпуск';
    } else if (mine) {
      headline = 'Вы попросили отпуск';
    } else {
      headline = '${request.name} уезжает и просит отпуск';
    }

    Widget actions;
    if (rejected) {
      actions = Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: onDismiss, child: const Text('Понятно')),
      );
    } else if (!mine &&
        request.approvers.contains(myName) &&
        request.votes[myName] == null) {
      actions = Row(
        children: [
          Expanded(
            child: _VoteButton(
              label: 'Отклонить',
              color: expenseColor(context),
              onPressed: () => onVote(kAwayNo),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _VoteButton(
              label: 'Согласовать',
              color: incomeColor(context),
              onPressed: () => onVote(kAwayYes),
            ),
          ),
        ],
      );
    } else {
      actions = Text(
        'Ждём: ${request.awaiting.join(', ')}',
        style: TextStyle(fontSize: 12.5, color: ink.withValues(alpha: 0.6)),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: kPayColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPayColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.beach_access_rounded,
                  size: 16, color: kPayColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          if (!rejected) ...[
            const SizedBox(height: 4),
            Text(
              'Пока в отпуске, новые покупки и штрафы на '
              '${mine ? 'вас' : 'него'} не делятся. Старые долги остаются.',
              style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.8)),
            ),
          ],
          const SizedBox(height: 8),
          actions,
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _VoteButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }
}
