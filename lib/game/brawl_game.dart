import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../input/keyboard_input.dart';
import '../input/touch_input.dart';
import '../sim/defs.dart';
import '../sim/game_state.dart';
import '../sim/input_frame.dart';
import '../sim/match_simulation.dart';
import 'fixed_step_clock.dart';

/// Debug view: runs the simulation at a fixed 60 ticks per second and draws
/// the state as plain rectangles. It only reads the state, never writes it.
class BrawlGame extends FlameGame with KeyboardEvents {
  BrawlGame({int seed = 1})
    : _seed = seed,
      _sim = MatchSimulation(
        stage: StageDef.flatArena,
        fighterDefs: const [FighterDef.knight, FighterDef.ranger],
      ) {
    _state = _sim.initialState(seed: seed);
  }

  final int _seed;

  final MatchSimulation _sim;
  late GameState _state;
  final FixedStepClock _clock = FixedStepClock();
  InputFrame _keyboardInput = InputFrame.none;

  /// Written by the on-screen controls, read once per tick.
  final TouchInput touchInput = TouchInput();

  /// Width of the world shown on screen, in world units.
  static const double _viewWidth = 1600;

  static final _groundPaint = Paint()..color = const Color(0xFF3A3F4B);
  static final _fighterPaints = [
    Paint()..color = const Color(0xFF4FC3F7),
    Paint()..color = const Color(0xFFFF8A65),
  ];
  static final _hitFlashPaint = Paint()..color = Colors.white;
  static final _facingPaint = Paint()..color = const Color(0xFF14161C);
  static final _windUpPaint = Paint()
    ..color = const Color(0x88FFEB3B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final _hitboxPaint = Paint()..color = const Color(0xAAFF1744);
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
      // Keyboard and touch can be used together.
      final player = InputFrame(_keyboardInput.bits | touchInput.frame.bits);
      // Slot 1 is the training dummy: it stands still until the bot exists.
      _sim.step(_state, [player, InputFrame.none]);
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
      _renderFighter(canvas, _state.fighters[i], _sim.fighterDefs[i], i);
    }
    canvas.restore();

    final knight = _state.fighters[0];
    final ranger = _state.fighters[1];
    _hud.render(
      canvas,
      'You (Knight) ${knight.damage}%  stocks ${knight.stocks}      '
      'Dummy (Ranger) ${ranger.damage}%  stocks ${ranger.stocks}',
      Vector2(16, 16),
    );
    _hud.render(
      canvas,
      'Keys: A / D move   Space or W jump (x3)   S fast fall   J light attack'
      '   R reset      frame ${_state.frame}  '
      'checksum ${_state.checksum().toRadixString(16)}',
      Vector2(16, 38),
    );
  }

  void _renderFighter(Canvas canvas, FighterState f, FighterDef def, int slot) {
    final x = f.x.toDouble();
    final y = f.y.toDouble();
    final w = def.width.toDouble();
    final h = def.height.toDouble();

    // Flash white every few ticks while in hitstun.
    final flashing = f.hitstun > 0 && (f.hitstun ~/ 3).isEven;
    canvas.drawRect(
      Rect.fromLTWH(x - w / 2, y - h, w, h),
      flashing ? _hitFlashPaint : _fighterPaints[slot],
    );
    // Eye on the facing side.
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(x + f.facing * w / 4, y - h + 18),
        width: 8,
        height: 8,
      ),
      _facingPaint,
    );

    if (f.attackFrame > 0) {
      final attack = def.lightAttack;
      final box = MatchSimulation.hitboxOf(f, attack);
      final rect = Rect.fromLTRB(
        box.left.toDouble(),
        box.top.toDouble(),
        box.right.toDouble(),
        box.bottom.toDouble(),
      );
      if (attack.isActiveOn(f.attackFrame)) {
        canvas.drawRect(rect, _hitboxPaint);
      } else if (f.attackFrame <= attack.startup) {
        canvas.drawRect(rect, _windUpPaint);
      }
    }
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    _keyboardInput = inputFromKeys(keysPressed);
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyR) {
      _state = _sim.initialState(seed: _seed);
    }
    return KeyEventResult.handled;
  }
}
