import 'package:flutter/material.dart';

import 'data/name_store.dart';
import 'screens/home_screen.dart';
import 'screens/name_picker_screen.dart';
import 'widgets/app_background_pattern.dart';
import 'widgets/orbit_loader.dart';

/// Decides what the app opens on: the name picker until this phone has
/// been given a flatmate's name, then the shared budget.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  String? _name;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await NameStore.load();
    if (!mounted) return;
    setState(() {
      _name = name;
      _loading = false;
    });
  }

  Future<void> _pick(String name) async {
    await NameStore.save(name);
    if (!mounted) return;
    setState(() => _name = name);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // The first screen of the app, so it wears the same room as the rest
      // of it rather than a bare Material spinner on white.
      return const Scaffold(
        body: AppBackgroundPattern(
          child: Center(child: OrbitLoader()),
        ),
      );
    }
    final name = _name;
    if (name == null) {
      return NamePickerScreen(onPicked: _pick);
    }
    return HomeScreen(myName: name);
  }
}
