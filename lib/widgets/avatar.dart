import 'package:flutter/material.dart';

/// Each flatmate's face, drawn by tool/generate_avatars.py.
const _files = {
  'Азамат': 'azamat',
  'Аслан': 'aslan',
  'Мухаммад': 'muhammad',
  'Имран': 'imran',
};

/// A flatmate's round cartoon face. Anyone not in the list -- a record
/// from before names existed -- gets a plain person icon instead.
class Avatar extends StatelessWidget {
  final String name;
  final double size;

  const Avatar(this.name, {super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final file = _files[name];
    if (file == null) {
      return Icon(Icons.account_circle_outlined, size: size);
    }
    return Image.asset(
      'assets/avatars/$file.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
