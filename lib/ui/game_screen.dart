import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/brawl_game.dart';
import 'touch_controls.dart';

/// The match: the Flame game with the touch controls layered on top.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.showTouchControls});

  final bool showTouchControls;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final BrawlGame _game = BrawlGame();

  @override
  Widget build(BuildContext context) {
    // Material gives the button labels a proper text style.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          GameWidget(game: _game),
          if (widget.showTouchControls) TouchControls(input: _game.touchInput),
        ],
      ),
    );
  }
}
