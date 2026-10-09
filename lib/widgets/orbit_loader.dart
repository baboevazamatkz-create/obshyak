import 'dart:math';

import 'package:flutter/material.dart';

import '../models/shared_budget.dart';
import 'avatar.dart';

/// The loading mark: the four flatmates circling the coin, each staying
/// upright as they go round. The same picture the web page shows before
/// the app has loaded, so the hand-over between the two is seamless.
class OrbitLoader extends StatefulWidget {
  final double size;

  const OrbitLoader({super.key, this.size = 200});

  @override
  State<OrbitLoader> createState() => _OrbitLoaderState();
}

class _OrbitLoaderState extends State<OrbitLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final face = size * 0.30;
    final coin = size * 0.26;
    final radius = (size - face) / 2;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _turn,
        builder: (context, _) {
          final angle = _turn.value * 2 * pi;
          return Stack(
            children: [
              Center(
                child:
                    Image.asset('assets/coin.png', width: coin, height: coin),
              ),
              for (var i = 0; i < kRoommates.length; i++)
                Positioned(
                  left: size / 2 + radius * sin(angle + i * pi / 2) - face / 2,
                  top: size / 2 - radius * cos(angle + i * pi / 2) - face / 2,
                  child: Avatar(kRoommates[i], size: face),
                ),
            ],
          );
        },
      ),
    );
  }
}
