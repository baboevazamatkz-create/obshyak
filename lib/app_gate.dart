import 'package:flutter/material.dart';

import 'data/name_store.dart';
import 'screens/home_screen.dart';
import 'screens/name_picker_screen.dart';
import 'widgets/app_background_pattern.dart';
import 'widgets/orbit_loader.dart';

/// Decides what the app opens on: the name picker until this phone has
/// been given a flatmate's name, then the shared budget.
class AppGate extends StatefulWidget {
  /// Connects to the shared budget. Injectable so a test can stand in a
  /// connection that works or one that fails.
  final Future<void> Function() connect;

  const AppGate({super.key, required this.connect});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  String? _name;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
    });
    try {
      await widget.connect();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _offline = true;
        });
      }
      return;
    }
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
    if (_offline) {
      return Scaffold(
        body: AppBackgroundPattern(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Не удалось подключиться.\n'
                    'Проверьте интернет и попробуйте ещё раз.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
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
