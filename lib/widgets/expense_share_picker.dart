import 'package:flutter/material.dart';

import '../models/shared_budget.dart';
import '../theme.dart';
import 'avatar.dart';

class ExpenseSharePicker extends StatelessWidget {
  const ExpenseSharePicker({
    super.key,
    required this.members,
    required this.away,
    required this.onChanged,
    this.showError = false,
    this.scale = 1,
  });

  final Iterable<String> members;
  final Set<String> away;
  final void Function(String name, bool selected) onChanged;
  final bool showError;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'НА КОГО ДЕЛИТСЯ',
          style: microLabel(
            context,
            size: 10.5 * scale,
            color: accentForeground(context).withValues(alpha: 0.6),
          ),
        ),
        SizedBox(height: 8 * scale),
        Wrap(
          spacing: 8 * scale,
          runSpacing: 8 * scale,
          children: [
            for (final name in kRoommates)
              FilterChip(
                avatar: Opacity(
                  opacity: away.contains(name) ? 0.4 : 1,
                  child: Avatar(name, size: 22 * scale),
                ),
                label: Text(name),
                selected: members.contains(name),
                showCheckmark: false,
                onSelected: (selected) => onChanged(name, selected),
              ),
          ],
        ),
        if (showError) ...[
          SizedBox(height: 8 * scale),
          Text(
            'Отметьте хотя бы одного',
            style:
                TextStyle(color: expenseColor(context), fontSize: 13 * scale),
          ),
        ],
      ],
    );
  }
}
