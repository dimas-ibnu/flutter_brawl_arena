import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/keyboard_input.dart';
import '../sim/defs.dart';
import '../sim/game_state.dart';
import '../sim/input_frame.dart';
import '../sim/match_simulation.dart';
import 'fixed_step_clock.dart';

/// Debug view: runs the simulation at a fixed 60 ticks per second and draws
/// the state as plain rectangles. It only reads the state, never writes it.
class BrawlGame extends FlameGame with KeyboardEvents {
  BrawlGame({int seed = 1})
    : _sim = MatchSimulation(
        stage: StageDef.flatArena,
        fighterDefs: const [FighterDef.knight, FighterDef.ranger],
      ) {
    _state = _sim.initialState(seed: seed);
  }

  final MatchSimulation _sim;
  late GameState _state;
  final FixedStepClock _clock = FixedStepClock();
  InputFrame _playerInput = InputFrame.none;

  /// Width of the world shown on screen, in world units.
  static const double _viewWidth = 1600;

  static final _groundPaint = Paint()..color = const Color(0xFF3A3F4B);
  static final _fighterPaints = [
    Paint()..color = const Color(0xFF4FC3F7),
    Paint()..color = const Color(0xFFFF8A65),
  ];
  static final _hud = TextPaint(
    style: const TextStyle(color: Colors.white70, fontSize: 14),
  );

  @override
  Color backgroundColor() => const Color(0xFF14161C);

  @override
  void update(double dt) {
    super.update(dt);
    final ticks = _clock.advance(dt);
    for (var i = 0; i < ticks; i++) {
      // Slot 1 stays idle until the bot exists.
      _sim.step(_state, [_playerInput, InputFrame.none]);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final scale = size.x / _viewWidth;

    canvas.save();
    canvas.translate(size.x / 2, size.y * 0.65);
    canvas.scale(scale);

    final stage = _sim.stage;
    canvas.drawRect(
      Rect.fromLTRB(
        stage.groundLeft.toDouble(),
        stage.groundY.toDouble(),
        stage.groundRight.toDouble(),
        stage.groundY.toDouble() + 40,
      ),
      _groundPaint,
    );

    for (var i = 0; i < _state.fighters.length; i++) {
      final f = _state.fighters[i];
      final def = _sim.fighterDefs[i];
      final w = def.width.toDouble();
      final h = def.height.toDouble();
      canvas.drawRect(
        Rect.fromLTWH(f.x.toDouble() - w / 2, f.y.toDouble() - h, w, h),
        _fighterPaints[i],
      );
    }
    canvas.restore();

    final p1 = _state.fighters[0];
    _hud.render(
      canvas,
      'frame ${_state.frame}   stocks ${p1.stocks}   '
      'checksum ${_state.checksum().toRadixString(16)}',
      Vector2(16, 16),
    );
    _hud.render(
      canvas,
      'A / D move   Space or W jump (x3)   S fast fall   '
      '— attacks not built yet',
      Vector2(16, 38),
    );
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    _playerInput = inputFromKeys(keysPressed);
    return KeyEventResult.handled;
  }
}
