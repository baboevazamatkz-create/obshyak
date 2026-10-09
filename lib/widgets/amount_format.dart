import 'package:flutter/services.dart';

/// Groups the digits of a whole number in threes with spaces: 1234567 gives
/// "1 234 567".
String groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Whole tenge only: digits typed in as they come, grouped in thousands.
/// No hundredths, which a shop receipt never needs.
class WholeAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Anything after a decimal separator is hundredths: dropped, not joined.
    final whole = newValue.text.split(RegExp(r'[.,]')).first;
    final digits = whole.replaceAll(RegExp(r'\D'), '');
    final result = groupThousands(digits);
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
