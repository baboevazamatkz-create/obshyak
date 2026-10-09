import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// A short walk through the main screen, shown once to each phone.
///
/// Five cards, one per thing a new flatmate needs to find: the pool, adding
/// a receipt, paying, fines and history. Skipping or finishing both count
/// as seen.
class OnboardingTour {
  OnboardingTour._();

  static const _seenKey = 'tour_seen_v1';

  static const _steps = [
    (
      'Общак',
      'Сверху видно, кто сколько потратил на общее и кто кому должен. '
          'Долги закрываются переводами, а не покупками.',
    ),
    (
      'Покупка по чеку',
      'Кнопка внизу справа добавляет покупку: снимите чек или выберите фото. '
          'Фото сохраняется, и по нажатию на запись его можно открыть.',
    ),
    (
      'Оплатить',
      'Если вы должны, нажмите «Оплатить». Получатель подтверждает, '
          'что деньги пришли, и долг закрывается.',
    ),
    (
      'Штраф',
      'Красная кнопка с молотком предлагает штраф. Его решают все, '
          'кроме штрафника: им нужно «назначить» или «отменить».',
    ),
    (
      'История',
      'Когда все в расчёте, период уходит в историю. Она открывается '
          'часами в шапке.',
    ),
  ];

  /// Shows the tour if this phone has not seen it. Returns at once when it
  /// has, so opening the app costs nothing more than one preference read.
  static Future<void> showIfNew(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _TourDialog(),
    );
    await prefs.setBool(_seenKey, true);
  }
}

class _TourDialog extends StatefulWidget {
  const _TourDialog();

  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  int _index = 0;

  void _next() {
    if (_index == OnboardingTour._steps.length - 1) {
      Navigator.of(context).pop();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    const steps = OnboardingTour._steps;
    final step = steps[_index];
    final last = _index == steps.length - 1;
    final ink = accentForeground(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        decoration: BoxDecoration(
          gradient: heroGradientFor(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: hairlineColor(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_index + 1} ИЗ ${steps.length}',
                    style: microLabel(
                      context,
                      color: goldFor(context).withValues(alpha: 0.9),
                    ),
                  ),
                ),
                if (!last)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Пропустить'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              step.$1,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              step.$2,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                color: ink.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? goldFor(context)
                          : ink.withValues(alpha: 0.2),
                    ),
                  ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _next,
                  child: Text(last ? 'Понятно' : 'Далее'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
