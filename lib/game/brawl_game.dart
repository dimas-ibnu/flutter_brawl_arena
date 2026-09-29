import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/bot.dart';
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
  BrawlGame({required List<FighterDef> fighters, int seed = 1})
    : _seed = seed,
      _sim = MatchSimulation(stage: StageDef.flatArena, fighterDefs: fighters) {
    _state = _sim.initialState(seed: seed);
    _bot = Bot(sim: _sim, slot: 1, seed: seed);
  }

  final int _seed;

  final MatchSimulation _sim;
  late GameState _state;
  late final Bot _bot;

  /// Off = the opponent stands still as a training dummy (T toggles).
  bool _botEnabled = true;
  final FixedStepClock _clock = FixedStepClock();
  InputFrame _keyboardInput = InputFrame.none;

  /// Written by the on-screen controls, read once per tick.
  final TouchInput touchInput = TouchInput();

  /// Null while the match runs; then the winner's slot, or -1 for a draw.
  final ValueNotifier<int?> result = ValueNotifier(null);

  /// Names for the result screen, by slot.
  List<String> get fighterNames => [for (final d in _sim.fighterDefs) d.name];

  /// Starts a fresh match with the same fighters.
  void restart() {
    _state = _sim.initialState(seed: _seed);
    _bot.reset();
    touchInput.reset();
    result.value = null;
  }

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
  static final _dodgePaint = Paint()..color = const Color(0x55FFFFFF);
  static final _hud = TextPaint(
    style: const TextStyle(color: Colors.white70, fontSize: 14),
  );
  static final _clockText = TextPaint(
    style: const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
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
      final opponent = _botEnabled ? _bot.think(_state) : InputFrame.none;
      _sim.step(_state, [player, opponent]);
    }
    if (_state.finished && result.value == null) result.value = _state.winner;
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
      'You (Knight) ${knight.damage}%  ${_stockDots(knight)}      '
      '${_botEnabled ? 'Bot' : 'Dummy'} (Ranger) ${ranger.damage}%  '
      '${_stockDots(ranger)}',
      Vector2(16, 16),
    );
    final secondsLeft = (_sim.ticksLeft(_state) + 59) ~/ 60;
    _clockText.render(
      canvas,
      '${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
      Vector2(size.x / 2, 12),
      anchor: Anchor.topCenter,
    );
    _hud.render(
      canvas,
      'A/D move  Space/W jump  S fast fall  J light  K heavy  L dodge  '
      '(hold a direction to change the move)  R reset  T bot/dummy   frame ${_state.frame}  '
      'checksum ${_state.checksum().toRadixString(16)}',
      Vector2(16, 38),
    );
  }

  String _stockDots(FighterState f) =>
      '${'●' * f.stocks}${'○' * (_sim.startingStocks - f.stocks)}';

  void _renderFighter(Canvas canvas, FighterState f, FighterDef def, int slot) {
    if (f.eliminated) return;
    // Blink while respawn-invincible.
    if (f.invincible > 0 && (f.invincible ~/ 4).isOdd) return;
    final x = f.x.toDouble();
    final y = f.y.toDouble();
    final w = def.width.toDouble();
    final h = def.height.toDouble();

    // Flash white every few ticks while in hitstun.
    // See-through while dodging (invincible).
    final flashing = f.hitstun > 0 && (f.hitstun ~/ 3).isEven;
    canvas.drawRect(
      Rect.fromLTWH(x - w / 2, y - h, w, h),
      f.dodgeFrame > 0
          ? _dodgePaint
          : (flashing ? _hitFlashPaint : _fighterPaints[slot]),
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

    final attack = _sim.currentMove(slot, f);
    final box = _sim.currentHitbox(slot, f);
    if (attack != null && box != null) {
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
      restart();
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyT) {
      _botEnabled = !_botEnabled;
    }
    return KeyEventResult.handled;
  }
}
