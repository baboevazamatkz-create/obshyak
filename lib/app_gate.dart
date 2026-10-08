import 'package:flutter/material.dart';

import 'data/household_repository.dart';
import 'models/household.dart';
import 'screens/home_screen.dart';
import 'screens/household_screen.dart';
import 'theme.dart';
import 'widgets/app_background_pattern.dart';

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  final _repository = HouseholdRepository();
  List<Household> _households = [];
  String? _activeCode;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final households = await _repository.loadHouseholds();
    final activeCode = await _repository.loadActiveCode();
    if (!mounted) return;
    setState(() {
      _households = households;
      _activeCode = households.any((h) => h.code == activeCode)
          ? activeCode
          : (households.isNotEmpty ? households.first.code : null);
      _loading = false;
    });
  }

  Future<void> _onHouseholdReady(Household household) async {
    await _repository.addHousehold(household);
    await _repository.setActiveCode(household.code);
    if (!mounted) return;
    setState(() {
      if (!_households.any((h) => h.code == household.code)) {
        _households = [..._households, household];
      }
      _activeCode = household.code;
    });
  }

  Future<void> _switchHousehold(String code) async {
    await _repository.setActiveCode(code);
    if (!mounted) return;
    setState(() => _activeCode = code);
  }

  /// Leaves a budget: it goes from this device's list, and the next one
  /// in the list takes over. Leaving the last one puts the gate back on
  /// the screen that creates or joins one.
  Future<void> _leaveHousehold(String code) async {
    await _repository.removeHousehold(code);
    final remaining = _households.where((h) => h.code != code).toList();
    final nextCode = _activeCode == code
        ? (remaining.isEmpty ? null : remaining.first.code)
        : _activeCode;
    if (nextCode == null) {
      await _repository.clearActiveCode();
    } else {
      await _repository.setActiveCode(nextCode);
    }
    if (!mounted) return;
    setState(() {
      _households = remaining;
      _activeCode = nextCode;
    });
  }

  void _openAddHouseholdFlow() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HouseholdScreen(
          canCancel: true,
          onReady: (household) async {
            await _onHouseholdReady(household);
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // The first screen of the app, so it wears the same room as the rest
      // of it rather than a bare Material spinner on white.
      return Scaffold(
        body: AppBackgroundPattern(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ОБЩАК',
                  style: wordmark(
                    context,
                    size: 15,
                    color: goldFor(context).withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 18),
                Image.asset(
                  'assets/brand_mark.png',
                  width: 88,
                  height: 88,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 22,
                  height: 22,
                  // backgroundColor draws the full ring, not just the
                  // moving arc -- without it, an indeterminate spinner
                  // spends part of its cycle as a short stray dash rather
                  // than a circle with a bright segment sweeping round it.
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    backgroundColor: goldFor(context).withValues(alpha: 0.16),
                    color: goldFor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final activeCode = _activeCode;
    if (activeCode == null) {
      return HouseholdScreen(onReady: _onHouseholdReady);
    }
    final activeHousehold = _households.firstWhere((h) => h.code == activeCode);
    return HomeScreen(
      household: activeHousehold,
      households: _households,
      onSwitchHousehold: _switchHousehold,
      onAddHousehold: _openAddHouseholdFlow,
      onLeaveHousehold: _leaveHousehold,
    );
  }
}
