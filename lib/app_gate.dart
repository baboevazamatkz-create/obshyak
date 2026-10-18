import 'package:flutter/material.dart';

import 'data/budget_cache.dart';
import 'data/name_store.dart';
import 'models/away.dart';
import 'models/expense.dart';
import 'screens/home_screen.dart';
import 'screens/name_picker_screen.dart';
import 'theme.dart';
import 'widgets/app_background_pattern.dart';
import 'widgets/orbit_loader.dart';

/// Decides what the app opens on: the name picker until this phone has
/// been given a flatmate's name, then the shared budget.
///
/// Neither waits for the connection. The budget opens on the figures this
/// phone saw last while Firebase starts alongside; only if connecting
/// fails does the gate step in with a retry.
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
  ({List<Expense> expenses, AwayBook away})? _cached;
  bool _loading = true;
  bool _offline = false;

  /// What went wrong, shown small under the message so a screenshot is
  /// enough to tell a dead network from a bug.
  String? _reason;

  @override
  void initState() {
    super.initState();
    _connect();
    _loadLocal();
  }

  /// What this phone already knows: whose it is, and the budget as last
  /// seen. Both are local reads, done in moments.
  Future<void> _loadLocal() async {
    final name = await NameStore.load();
    final cached = name == null ? null : await BudgetCache.load();
    if (!mounted) return;
    setState(() {
      _name = name;
      _cached = cached;
      _loading = false;
    });
  }

  Future<void> _connect() async {
    if (_offline) setState(() => _offline = false);
    try {
      await widget.connect();
    } catch (error) {
      if (mounted) {
        setState(() {
          _offline = true;
          _reason = error.toString();
        });
      }
    }
  }

  Future<void> _pick(String name) async {
    await NameStore.save(name);
    if (!mounted) return;
    setState(() => _name = name);
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: _connect,
                    child: const Text('Повторить'),
                  ),
                  if (_reason != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      _reason!,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            accentForeground(context).withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_loading) {
      // Only for the moment the local reads take.
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
    return HomeScreen(myName: name, cached: _cached);
  }
}
