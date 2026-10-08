import 'package:flutter/material.dart';

import '../models/shared_budget.dart';
import '../theme.dart';
import '../widgets/app_background_pattern.dart';

/// Shown once per phone: whoever opens the app first picks which flatmate
/// they are, and that name goes on everything they enter.
class NamePickerScreen extends StatelessWidget {
  final ValueChanged<String> onPicked;

  const NamePickerScreen({super.key, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackgroundPattern(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Кто вы?',
                      textAlign: TextAlign.center,
                      style: wordmark(
                        context,
                        size: 22,
                        color: goldFor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Имя запомнится на этом телефоне и запишется '
                      'в каждый ваш расход',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: accentForeground(context).withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final name in kRoommates) ...[
                      OutlinedButton(
                        onPressed: () => onPicked(name),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          side: BorderSide(
                            color: goldFor(context).withValues(alpha: 0.55),
                          ),
                          foregroundColor: accentForeground(context),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
