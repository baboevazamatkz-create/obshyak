import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shared_budget.dart';
import '../theme.dart';
import '../widgets/app_background_pattern.dart';
import '../widgets/avatar.dart';

/// Shown once per phone: whoever opens the app first picks which flatmate
/// they are, confirms it with that flatmate's code, and that name goes on
/// everything they enter.
class NamePickerScreen extends StatelessWidget {
  final ValueChanged<String> onPicked;

  const NamePickerScreen({super.key, required this.onPicked});

  Future<void> _askCode(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _CodeDialog(name: name),
    );
    if (ok == true) onPicked(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackgroundPattern(
        child: SafeArea(
          // Scrolls when it has to: four names at a large text size do not
          // fit a small phone's height.
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/obshak_mark.png',
                          width: 72,
                          height: 72,
                        ),
                      ),
                      const SizedBox(height: 16),
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
                        'Выберите себя и введите свой код. Имя запомнится '
                        'на этом телефоне',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              accentForeground(context).withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 28),
                      for (final name in kRoommates) ...[
                        OutlinedButton(
                          onPressed: () => _askCode(context, name),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            side: BorderSide(
                              color: goldFor(context).withValues(alpha: 0.55),
                            ),
                            foregroundColor: accentForeground(context),
                          ),
                          child: Row(
                            children: [
                              Avatar(name, size: 34),
                              const SizedBox(width: 14),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

/// Asks for the picked flatmate's four-digit code. Closes with true once
/// the right code is typed; a wrong one clears the field and says so.
class _CodeDialog extends StatefulWidget {
  final String name;

  const _CodeDialog({required this.name});

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check(String code) {
    if (code.length < 4) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    if (code == kRoommateCodes[widget.name]) {
      Navigator.of(context).pop(true);
    } else {
      _controller.clear();
      setState(() => _error = 'Неверный код');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Avatar(widget.name, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.name)),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 24, letterSpacing: 12),
        decoration: InputDecoration(
          labelText: 'Код',
          counterText: '',
          errorText: _error,
        ),
        onChanged: _check,
        onSubmitted: _check,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}
