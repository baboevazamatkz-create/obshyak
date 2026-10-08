import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/household_repository.dart';
import '../data/household_settings_repository.dart';
import '../models/currency.dart';
import '../models/household.dart';
import '../theme.dart';
import '../widgets/readable_width.dart';
import '../widgets/app_background_pattern.dart';

class HouseholdScreen extends StatefulWidget {
  final void Function(Household household) onReady;
  final bool canCancel;

  const HouseholdScreen({
    super.key,
    required this.onReady,
    this.canCancel = false,
  });

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

/// The wordmark carries the top of this screen, so it is set well above
/// the body text rather than a shade above it.
const double _kWordmarkScale = 3.0;

/// The currency picker is the one control here people actually have to aim
/// at, so it alone is drawn larger than the rest of the form. It went to
/// 1.5 first, which read as too big beside everything else, and back down
/// by 1.2 from there.
const double _kCurrencyScale = 1.5 / 1.2;

double _c(double value) => value * _kCurrencyScale;

class _HouseholdScreenState extends State<HouseholdScreen> {
  final _labelController = TextEditingController();
  final _codeController = TextEditingController();
  final _settingsRepository = HouseholdSettingsRepository();
  AppCurrency _selectedCurrency = AppCurrency.rub;
  bool _busy = false;
  String? _labelError;
  String? _codeError;

  @override
  void dispose() {
    _labelController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool _validateLabel() {
    if (_labelController.text.trim().isEmpty) {
      setState(() => _labelError = 'Введите название бюджета');
      return false;
    }
    setState(() => _labelError = null);
    return true;
  }

  Future<void> _createHousehold() async {
    if (!_validateLabel()) return;
    setState(() => _busy = true);
    final code = HouseholdRepository.generateCode();
    final label = _labelController.text.trim();
    await _settingsRepository.setCurrency(code, _selectedCurrency);
    await _settingsRepository.setLabel(code, label);
    if (!mounted) return;
    await _showCodeDialog(code);
    if (!mounted) return;
    widget.onReady(Household(code: code, label: label));
  }

  Future<void> _joinHousehold() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _codeError = 'Введите код бюджета целиком');
      return;
    }
    setState(() {
      _busy = true;
      _codeError = null;
    });
    String label;
    try {
      label = await _settingsRepository.fetchLabel(code) ?? 'Бюджет';
    } catch (_) {
      label = 'Бюджет';
    }
    if (!mounted) return;
    widget.onReady(Household(code: code, label: label));
  }

  Future<void> _showCodeDialog(String code) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        // Tinted to match the welcome screen it is opened from, rather than
        // the plain black-on-white the Material default gives it.
        backgroundColor: Color.alphaBlend(
          goldFor(context).withValues(alpha: isDark ? 0.08 : 0.04),
          Theme.of(context).dialogTheme.backgroundColor ??
              Theme.of(context).colorScheme.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: goldFor(context).withValues(alpha: 0.3)),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Onest',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: accentForeground(context),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: goldFor(context), size: 21),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Бюджет создан',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Отправьте этот код супруге/супругу или коллегам, '
              'чтобы вести бюджет вместе:',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: goldFor(context).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: goldFor(context).withValues(alpha: 0.35)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  code,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 5,
                    color: goldFor(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: goldFor(context)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Код скопирован')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Скопировать'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          widget.canCancel ? AppBar(title: const Text('Новый бюджет')) : null,
      body: AppBackgroundPattern(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ReadableWidth(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The wordmark is the brand, so it stands above the
                      // form whether this is the first run or a second
                      // budget opened from the switcher. Only the headline
                      // under it belongs to the first run.
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'ОБЩАК',
                            style: wordmark(
                              context,
                              size: 12 * _kWordmarkScale,
                              color: goldFor(context).withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: widget.canCancel ? 28 : 20),
                      // Half of the lockup, so it stands wherever the
                      // wordmark does. It used to be first-run only, which
                      // meant anyone who already had a budget never saw it
                      // again -- and once the wordmark moved out of that
                      // block and this did not, the screen showed a name
                      // with nothing under it. A step down from the 30 it
                      // started at: under a wordmark this size it is the
                      // second voice on the screen, not the first.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Единый ритм\nмалых финансов',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30 / 1.3,
                            height: 1.15,
                            fontWeight: FontWeight.w300,
                            letterSpacing: -0.8,
                            color: accentForeground(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Создайте общий бюджет и поделитесь кодом, '
                        'чтобы вести расходы вместе',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child:
                            Text('ВАЛЮТА БЮДЖЕТА', style: microLabel(context)),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: _CurrencyPicker(
                          selected: _selectedCurrency,
                          onChanged: (currency) =>
                              setState(() => _selectedCurrency = currency),
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _labelController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'Название бюджета',
                          errorText: _labelError,
                        ),
                        onChanged: (_) {
                          if (_labelError != null) {
                            setState(() => _labelError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _createHousehold,
                          icon: const Icon(Icons.add_circle_outline, size: 19),
                          // Shrinks rather than truncating: on a narrow
                          // phone "Создать новый ..." drops the word that
                          // says what is being created.
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Создать новый бюджет', maxLines: 1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                              child: Divider(color: hairlineColor(context))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text('ИЛИ',
                                style: microLabel(context, size: 10)),
                          ),
                          Expanded(
                              child: Divider(color: hairlineColor(context))),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _codeController,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseTextFormatter()],
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 4,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Код бюджета',
                          // The field letterspaces its code digits; the hint is
                          // a sentence and should not inherit that.
                          hintStyle: Theme.of(context)
                              .inputDecorationTheme
                              .hintStyle
                              ?.copyWith(fontSize: 15, letterSpacing: 0.2),
                          errorText: _codeError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentForeground(context)
                                .withValues(alpha: 0.85),
                            side: BorderSide(color: hairlineColor(context)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onPressed: _busy ? null : _joinHousehold,
                          icon: const Icon(Icons.group_add_rounded, size: 19),
                          // Shrinks rather than truncating: on a narrow
                          // phone "Создать новый ..." drops the word that
                          // says what is being created.
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Присоединиться по коду', maxLines: 1),
                          ),
                        ),
                      ),
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _CurrencyPicker extends StatelessWidget {
  final AppCurrency selected;
  final ValueChanged<AppCurrency> onChanged;

  const _CurrencyPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Three chips at this size are wider than a 320pt phone's content
    // column, so the whole control scales down to fit rather than
    // overflowing. On anything roomier it is drawn at full size.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: EdgeInsets.all(_c(4)),
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(_c(14)),
          border: Border.all(color: hairlineColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: AppCurrency.values.map((currency) {
            final isSelected = currency == selected;
            return GestureDetector(
              onTap: () => onChanged(currency),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _c(64),
                height: _c(40),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? goldFor(context).withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(_c(10)),
                  border: isSelected
                      ? Border.all(
                          color: goldFor(context).withValues(alpha: 0.45))
                      : null,
                ),
                child: Text(
                  '${currency.symbol} ${currency.label}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected
                        ? goldFor(context)
                        : accentForeground(context).withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500,
                    fontSize: _c(11),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
