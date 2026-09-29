import 'dart:io';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/bot.dart';
import '../data/cosmetics.dart';
import '../data/roster.dart';
import '../input/keyboard_input.dart';
import '../input/touch_input.dart';
import '../net/net_match.dart';
import '../replay/replay.dart';
import '../sim/defs.dart';
import '../sim/game_state.dart';
import '../sim/input_frame.dart';
import '../sim/match_simulation.dart';
import 'fighter_art.dart';
import 'fixed_step_clock.dart';
import 'sounds.dart';
import 'stage_art.dart';

/// A match against the bot, or online against another player ([online]).
/// Runs the simulation at a fixed 60 ticks per second and draws it. Everything here only reads the simulation state; effects
/// like sparks, shake and sound are worked out by comparing ticks.
class BrawlGame extends FlameGame with KeyboardEvents {
  BrawlGame({
    required this.player,
    required this.opponent,
    required this.seed,
    this.playerSkin,
    this.opponentSkin,
    StagePalette palette = sunsetPalette,
    GameSounds? sounds,
    this.showKeyboardHints = true,
    this.localSlot = 0,
    this.online,
  }) : sounds = sounds ?? SilentSounds(),
       sim =
           online?.session.sim ??
           MatchSimulation(
             stage: StageDef.flatArena,
             fighterDefs: localSlot == 0
                 ? [player.def, opponent.def]
                 : [opponent.def, player.def],
           ),
       _backdrop = StageBackdrop(palette) {
    assert(online == null || online!.session.localSlot == localSlot);
    _bot = Bot(sim: sim, slot: 1 - localSlot, seed: seed);
    _newMatch();
  }

  /// This device's player and the other side (the bot, or the online
  /// opponent).
  final RosterEntry player;
  final RosterEntry opponent;

  /// Which simulation slot this device controls. Online, the host is 0 and
  /// the guest 1; against the bot it is always 0.
  final int localSlot;

  /// Set for online matches: the rollback session drives the simulation.
  final NetMatch? online;
  bool get isOnline => online != null;

  /// Fighters by simulation slot.
  List<RosterEntry> get entries =>
      localSlot == 0 ? [player, opponent] : [opponent, player];

  /// Why an online match can't go on ('Opponent left', 'Connection lost',
  /// 'Out of sync'), or null.
  final ValueNotifier<String?> connectionProblem = ValueNotifier(null);
  final int seed;

  /// Cosmetics: visual only, never passed to the simulation.
  final Skin? playerSkin;
  final Skin? opponentSkin;
  final GameSounds sounds;
  final bool showKeyboardHints;
  final MatchSimulation sim;

  late GameState _state;
  late final Bot _bot;
  late Replay _replay;
  late List<_Seen> _before;

  /// The live match state (read-only use; tests and debugging).
  GameState get state => _state;

  /// Every input of the current match, for saving with F5.
  Replay get replay => _replay;

  /// Off = the opponent stands still as a training dummy (T toggles).
  bool botEnabled = true;

  final FixedStepClock _clock = FixedStepClock();
  InputFrame _keyboardInput = InputFrame.none;

  /// Written by the on-screen controls, read once per tick.
  final TouchInput touchInput = TouchInput();

  /// Null while the match runs; then the winner's slot, or -1 for a draw.
  final ValueNotifier<int?> result = ValueNotifier(null);

  /// True while the pause menu is open (Esc or P toggles).
  final ValueNotifier<bool> pauseMenuOpen = ValueNotifier(false);

  /// Shows hitboxes, frame and checksum (F3 toggles).
  bool debugView = false;

  final _sparks = <_Spark>[];
  final _fx = math.Random();
  double _shake = 0;
  final StageBackdrop _backdrop;

  /// Recent weapon-tip positions per fighter, for skin weapon trails.
  final _trails = [<Offset>[], <Offset>[]];

  Skin? _skinOf(int slot) => slot == localSlot ? playerSkin : opponentSkin;

  /// Blue for this device's player, orange for the other side.
  static const _youColor = Color(0xFF4FC3F7);
  static const _themColor = Color(0xFFFF8A65);
  Color _colorOf(int slot) => slot == localSlot ? _youColor : _themColor;

  /// Width of the world shown on screen, in world units. The camera zooms
  /// between these to keep both fighters in view.
  static const double _viewWidth = 1600;
  static const double _minViewWidth = 1000;
  static const double _maxViewWidth = 1700;
  double _camWidth = 1300;
  double _camX = 0;
  double _camY = -150;

  void _newMatch() {
    _state = online?.state ?? sim.initialState(seed: seed);
    _bot.reset();
    touchInput.reset();
    _sparks.clear();
    for (final t in _trails) {
      t.clear();
    }
    _shake = 0;
    _replay = Replay(
      seed: seed,
      fighterIds: [for (final e in entries) e.id],
      stage: 'flatArena',
    );
    _before = [for (final f in _state.fighters) _Seen(f)];
  }

  /// Starts a fresh match with the same fighters (not online).
  void restart() {
    if (isOnline) return;
    _newMatch();
    pauseMenuOpen.value = false;
    result.value = null;
  }

  void setPaused(bool value) {
    if (result.value != null) return;
    pauseMenuOpen.value = value;
    touchInput.reset();
    _keyboardInput = InputFrame.none;
  }

  @override
  void onMount() {
    super.onMount();
    sounds.startMusic();
  }

  @override
  void onRemove() {
    sounds.stopMusic();
    super.onRemove();
  }

  @override
  Color backgroundColor() => const Color(0xFF14161C);

  @override
  void update(double dt) {
    super.update(dt);
    _updateEffects(dt);
    if (online != null) {
      _updateOnline(online!, dt);
    } else {
      if (pauseMenuOpen.value) return;
      final ticks = _clock.advance(dt);
      for (var i = 0; i < ticks && !_state.finished; i++) {
        // Keyboard and touch can be used together.
        final human = InputFrame(_keyboardInput.bits | touchInput.frame.bits);
        final bot = botEnabled ? _bot.think(_state) : InputFrame.none;
        final inputs = [human, bot];
        _replay.record(inputs);
        sim.step(_state, inputs);
        _detectEvents();
      }
    }
    if (_state.finished && result.value == null) {
      _replay.finalChecksum = _state.checksum();
      result.value = _state.winner;
    }
  }

  // Online: the match can't pause, so an open menu only mutes this side's
  // input. Ticking goes on after the result so the final inputs and
  // checksums still reach the other player.
  void _updateOnline(NetMatch net, double dt) {
    final ticks = _clock.advance(dt);
    for (var i = 0; i < ticks; i++) {
      final human = pauseMenuOpen.value || _state.finished
          ? InputFrame.none
          : InputFrame(_keyboardInput.bits | touchInput.frame.bits);
      net.tick(human);
      _state = net.state;
      _detectEvents();
    }
    if (connectionProblem.value == null && result.value == null) {
      if (net.remoteQuit) {
        connectionProblem.value = 'Opponent left';
      } else if (net.ticksSinceHeard > 5 * 60) {
        connectionProblem.value = 'Connection lost';
      } else if (net.desynced) {
        connectionProblem.value = 'Out of sync';
      }
    }
  }

  /// Leaves an online match, telling the other side.
  void leaveOnline() => online?.quit();

  // Compare each fighter with the previous tick to trigger sparks, shake
  // and sounds.
  void _detectEvents() {
    for (var i = 0; i < _state.fighters.length; i++) {
      final now = _state.fighters[i];
      final was = _before[i];
      final def = sim.fighterDefs[i];
      // In a 1v1 the other fighter caused it; their skin colors the effect.
      final other = _skinOf(1 - i);
      if (now.stocks < was.stocks) {
        _shake = 16;
        sounds.play(Sfx.ko);
        _burst(
          Offset(
            was.x.clamp(-_viewWidth / 2 + 40, _viewWidth / 2 - 40),
            was.y.clamp(-500, 200),
          ),
          40,
          other?.koColor ?? Colors.white,
          SparkShape.dot,
        );
      } else if (now.damage > was.damage) {
        final heavy = _state.hitFreeze > 0;
        _shake = math.max(_shake, heavy ? 9 : 3);
        sounds.play(heavy ? Sfx.hitHeavy : Sfx.hitLight);
        _burst(
          Offset(
            now.x.toDouble(),
            now.y.toDouble() - def.height.toDouble() / 2,
          ),
          heavy ? 22 : 10,
          other?.sparkColor ??
              (heavy ? const Color(0xFFFFD54F) : const Color(0xFFFFF3C4)),
          other?.sparkShape ?? SparkShape.dot,
        );
      } else if (now.dodgeFrame == 1) {
        sounds.play(Sfx.dodge);
      } else if (now.vy.isNegative &&
          !was.vyNegative &&
          now.attackFrame == 0 &&
          now.hitstun == 0) {
        sounds.play(Sfx.jump);
      }
      _before[i] = _Seen(now);
    }
  }

  void _burst(Offset at, int count, Color color, SparkShape shape) {
    for (var i = 0; i < count; i++) {
      final angle = _fx.nextDouble() * math.pi * 2;
      final speed = 3 + _fx.nextDouble() * 9;
      _sparks.add(
        _Spark(
          at,
          Offset(math.cos(angle), math.sin(angle)) * speed,
          0.25 + _fx.nextDouble() * 0.3,
          color,
          shape,
        ),
      );
    }
  }

  void _updateEffects(double dt) {
    final step = dt * 60;
    for (final s in _sparks) {
      s.pos += s.vel * step;
      s.vel *= math.pow(0.9, step).toDouble();
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    _shake = math.max(0, _shake - dt * 60);

    // Camera: frame the fighters still in the match, eased so it never jumps.
    final alive = [
      for (final f in _state.fighters)
        if (f.inPlay) f,
    ];
    if (alive.isNotEmpty) {
      final xs = [for (final f in alive) f.x.toDouble()];
      final ys = [for (final f in alive) f.y.toDouble()];
      final spread = xs.reduce(math.max) - xs.reduce(math.min);
      final targetWidth = (spread + 700).clamp(_minViewWidth, _maxViewWidth);
      final targetX = ((xs.reduce(math.max) + xs.reduce(math.min)) / 2).clamp(
        -400.0,
        400.0,
      );
      final targetY = (ys.reduce(math.min) - 80).clamp(-400.0, -60.0);
      final ease = 1 - math.pow(0.05, dt).toDouble();
      _camWidth += (targetWidth - _camWidth) * ease;
      _camX += (targetX - _camX) * ease;
      _camY += (targetY - _camY) * ease;
    }
  }

  // ---------------------------------------------------------------------------
  // Drawing

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _backdrop.paint(canvas, Size(size.x, size.y));

    final scale = size.x / _camWidth;
    canvas.save();
    if (_shake > 0) {
      canvas.translate(
        (_fx.nextDouble() - 0.5) * _shake,
        (_fx.nextDouble() - 0.5) * _shake,
      );
    }
    canvas.translate(size.x / 2, size.y * 0.55);
    canvas.scale(scale);
    canvas.translate(-_camX, -_camY - 60);

    final stage = sim.stage;
    paintPlatform(
      canvas,
      stage.groundLeft.toDouble(),
      stage.groundRight.toDouble(),
      stage.groundY.toDouble(),
      _backdrop.palette,
    );
    for (var i = 0; i < _state.fighters.length; i++) {
      _renderFighter(canvas, i);
    }
    for (final s in _sparks) {
      _paintSpark(canvas, s);
    }
    canvas.restore();

    _renderHud(canvas);
  }

  void _paintSpark(Canvas canvas, _Spark s) {
    final paint = Paint()
      ..color = s.color.withValues(alpha: (s.life * 3).clamp(0, 1));
    final r = 3 + s.life * 6;
    switch (s.shape) {
      case SparkShape.dot:
        canvas.drawCircle(s.pos, r, paint);
      case SparkShape.star:
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5 - math.pi / 2;
          final d = i.isEven ? r * 1.6 : r * 0.6;
          final pt = s.pos + Offset(math.cos(a), math.sin(a)) * d;
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path..close(), paint);
      case SparkShape.shard:
        final dir = s.vel.distance == 0
            ? const Offset(1, 0)
            : s.vel / s.vel.distance;
        canvas.drawLine(
          s.pos - dir * r * 1.5,
          s.pos + dir * r * 1.5,
          paint
            ..strokeWidth = r * 0.6
            ..strokeCap = StrokeCap.round,
        );
    }
  }

  void _renderTrail(Canvas canvas, List<Offset> trail, Color color) {
    for (var i = 1; i < trail.length; i++) {
      final t = i / trail.length;
      canvas.drawLine(
        trail[i - 1],
        trail[i],
        Paint()
          ..color = color.withValues(alpha: t * 0.8)
          ..strokeWidth = 4 + t * 10
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _renderFighter(Canvas canvas, int slot) {
    final f = _state.fighters[slot];
    final def = sim.fighterDefs[slot];
    if (!f.inPlay) return;
    // Blink while respawn-invincible.
    if (f.invincible > 0 && (f.invincible ~/ 4).isOdd) return;

    final x = f.x.toDouble();
    final y = f.y.toDouble();
    final attack = sim.currentMove(slot, f);
    final box = sim.currentHitbox(slot, f);
    Offset? reach;
    var windUp = false;
    if (attack != null && box != null) {
      if (f.attackFrame <= attack.startup) {
        windUp = true;
      } else if (attack.isActiveOn(f.attackFrame)) {
        reach = Offset(
          (box.left.toDouble() + box.right.toDouble()) / 2 - x,
          (box.top.toDouble() + box.bottom.toDouble()) / 2 - y,
        );
      }
    }
    final running = f.grounded && f.vx.abs().toDouble() > 1;
    final flash = f.hitstun > 0 && (f.hitstun ~/ 3).isEven;
    final skin = _skinOf(slot);
    final trail = _trails[slot];
    if (skin?.trailColor != null && trail.length > 1) {
      _renderTrail(canvas, trail, skin!.trailColor!);
    }

    final tip = paintFighter(
      canvas,
      feet: Offset(x, y),
      width: def.width.toDouble(),
      height: def.height.toDouble(),
      rim: _colorOf(slot),
      skin: flash ? _flashSkin(skin) : skin,
      weapon: weaponArtFor(entries[slot].id),
      opacity: f.dodgeFrame > 0 ? 0.35 : 1,
      pose: FighterPose(
        facing: f.facing,
        runPhase: running ? x / 18 : 0,
        airborne: !f.grounded,
        reach: reach,
        windUp: windUp,
        stunned: f.hitstun > 0,
        speedX: f.vx.toDouble(),
      ),
    );

    // Weapon trail: remember the tip while an attack is out.
    if (skin != null && skin.trailLength > 0 && reach != null) {
      trail.add(tip);
      while (trail.length > skin.trailLength) {
        trail.removeAt(0);
      }
    } else if (trail.isNotEmpty) {
      trail.removeAt(0);
    }

    // Marker above the head: blue = you, orange = bot, whatever the skin.
    final top = Offset(x, y - def.height.toDouble() - 26);
    canvas.drawPath(
      Path()
        ..moveTo(top.dx - 9, top.dy - 10)
        ..lineTo(top.dx + 9, top.dy - 10)
        ..lineTo(top.dx, top.dy)
        ..close(),
      Paint()..color = _colorOf(slot),
    );

    if (debugView && attack != null && box != null) {
      final rect = Rect.fromLTRB(
        box.left.toDouble(),
        box.top.toDouble(),
        box.right.toDouble(),
        box.bottom.toDouble(),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = attack.isActiveOn(f.attackFrame)
              ? const Color(0xAAFF1744)
              : const Color(0x88FFEB3B)
          ..style = attack.isActiveOn(f.attackFrame)
              ? PaintingStyle.fill
              : PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  static final _smallText = TextPaint(
    style: const TextStyle(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    ),
  );
  static final _nameText = TextPaint(
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );
  static final _clockText = TextPaint(
    style: const TextStyle(
      color: Colors.white,
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
  );
  static final _hintText = TextPaint(
    style: const TextStyle(color: Colors.white54, fontSize: 12),
  );

  /// Damage color: white at 0% shifting to red by 150% (PRD HUD).
  static Color damageColor(int damage) => Color.lerp(
    Colors.white,
    const Color(0xFFFF1744),
    (damage / 150).clamp(0, 1),
  )!;

  void _renderHud(Canvas canvas) {
    String label(int slot) => slot == localSlot
        ? 'YOU'
        : (isOnline ? 'OPPONENT' : (botEnabled ? 'BOT' : 'DUMMY'));
    _renderPanel(canvas, 0, label(0), left: true);
    _renderPanel(canvas, 1, label(1), left: false);

    final secondsLeft = (sim.ticksLeft(_state) + 59) ~/ 60;
    _clockText.render(
      canvas,
      '${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
      Vector2(size.x / 2, 10),
      anchor: Anchor.topCenter,
    );

    if (showKeyboardHints) {
      _hintText.render(
        canvas,
        'A/D move · Space jump · S fast fall · J light · K heavy · L dodge '
        '· hold a direction to change the move · Esc pause',
        Vector2(size.x / 2, size.y - 10),
        anchor: Anchor.bottomCenter,
      );
    }
    if (debugView) {
      _hintText.render(
        canvas,
        'frame ${_state.frame}  checksum ${_state.checksum().toRadixString(16)}'
        '  R reset  T bot/dummy  F5 save replay',
        Vector2(16, size.y - 28),
      );
    }
  }

  void _renderPanel(
    Canvas canvas,
    int slot,
    String label, {
    required bool left,
  }) {
    final f = _state.fighters[slot];
    final entry = entries[slot];
    final x = left ? 20.0 : size.x - 20;
    final anchor = left ? Anchor.topLeft : Anchor.topRight;
    _smallText.render(canvas, label, Vector2(x, 10), anchor: anchor);
    _nameText.render(canvas, entry.name, Vector2(x, 26), anchor: anchor);
    TextPaint(
      style: TextStyle(
        color: damageColor(f.damage),
        fontSize: 30,
        fontWeight: FontWeight.w800,
        shadows: const [Shadow(blurRadius: 4)],
      ),
    ).render(canvas, '${f.damage}%', Vector2(x, 44), anchor: anchor);

    // Stock dots.
    for (var i = 0; i < sim.startingStocks; i++) {
      final dx = left ? x + 6 + i * 16.0 : x - 6 - i * 16.0;
      canvas.drawCircle(
        Offset(dx, 90),
        5,
        Paint()
          ..color = i < f.stocks ? _colorOf(slot) : Colors.white24
          ..style = PaintingStyle.fill,
      );
    }
  }

  /// Hit flash: the same skin with a white rim.
  static Skin _flashSkin(Skin? skin) => Skin(
    id: skin?.id ?? 'flash',
    name: '',
    fighterId: skin?.fighterId ?? '',
    rim: Colors.white,
    body: skin?.body,
    weaponColor: skin?.weaponColor,
    weaponGlow: skin?.weaponGlow ?? 0,
    weaponLength: skin?.weaponLength ?? 1,
    accessories: skin?.accessories ?? const [],
  );

  // ---------------------------------------------------------------------------
  // Keyboard

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
        setPaused(!pauseMenuOpen.value);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) restart();
      if (key == LogicalKeyboardKey.keyT && !isOnline) botEnabled = !botEnabled;
      if (key == LogicalKeyboardKey.f3) debugView = !debugView;
      if (key == LogicalKeyboardKey.f5) saveReplay();
    }
    _keyboardInput = pauseMenuOpen.value
        ? InputFrame.none
        : inputFromKeys(keysPressed);
    return KeyEventResult.handled;
  }

  /// Writes the current match's inputs to the system temp folder and returns
  /// the file. `Replay.fromJson` + `Replay.play` reproduce the match.
  File saveReplay() {
    final dir = Directory('${Directory.systemTemp.path}/brawl_replays')
      ..createSync(recursive: true);
    _replay.finalChecksum ??= _state.checksum();
    final file = File(
      '${dir.path}/replay_${DateTime.now().millisecondsSinceEpoch}.json',
    )..writeAsStringSync(_replay.toJson());
    debugPrint('Replay saved to ${file.path}');
    return file;
  }
}

/// What a fighter looked like on the previous tick, for event detection.
class _Seen {
  _Seen(FighterState f)
    : stocks = f.stocks,
      damage = f.damage,
      x = f.x.toDouble(),
      y = f.y.toDouble(),
      vyNegative = f.vy.isNegative;

  final int stocks;
  final int damage;
  final double x;
  final double y;
  final bool vyNegative;
}

class _Spark {
  _Spark(this.pos, this.vel, this.life, this.color, this.shape);

  Offset pos;
  Offset vel;
  double life;
  final Color color;
  final SparkShape shape;
}
