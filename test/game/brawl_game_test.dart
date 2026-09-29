import 'package:brawl_arena/game/brawl_game.dart';
import 'package:brawl_arena/game/sounds.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/roster.dart';

class _RecordingSounds implements GameSounds {
  final played = <Sfx>[];
  var musicOn = false;

  @override
  final ValueNotifier<bool> muted = ValueNotifier(false);

  @override
  void play(Sfx sfx) => played.add(sfx);

  @override
  void startMusic() => musicOn = true;

  @override
  void stopMusic() => musicOn = false;
}

BrawlGame _game([GameSounds? sounds]) => BrawlGame(
  player: rosterEntry('knight'),
  opponent: rosterEntry('ranger'),
  seed: 1,
  sounds: sounds,
);

void _tick(BrawlGame game, int ticks) {
  for (var i = 0; i < ticks; i++) {
    game.update(1 / 60);
  }
}

void main() {
  test('runs 60 ticks per second of real time', () {
    final game = _game();
    _tick(game, 60);
    expect(game.state.frame, 60);
  });

  test('pausing stops the match; resuming continues it', () {
    final game = _game();
    _tick(game, 10);
    game.setPaused(true);
    _tick(game, 30);
    expect(game.state.frame, 10);
    game.setPaused(false);
    _tick(game, 5);
    expect(game.state.frame, 15);
  });

  test('every tick is recorded and the replay matches the match', () {
    final game = _game();
    _tick(game, 300);
    // Hit-freeze ticks are recorded too, though the match clock stands still.
    expect(game.replay.ticks.length, 300);
    expect(game.replay.play(game.sim).checksum(), game.state.checksum());
  });

  test('hits and knockouts play sounds', () {
    final sounds = _RecordingSounds();
    final game = _game(sounds);
    // Stand still next to the bot and let it attack.
    game.state.fighters[0].x = Fx.fromInt(150);
    _tick(game, 60 * 30);
    expect(
      sounds.played,
      anyOf(contains(Sfx.hitLight), contains(Sfx.hitHeavy)),
    );
    expect(sounds.played, contains(Sfx.ko));
  });

  test('the result is published when the match ends', () {
    final game = _game();
    game.state.fighters[0]
      ..stocks = 1
      ..y = game.sim.stage.blastBottom + Fx.fromInt(10);
    _tick(game, 2);
    expect(game.result.value, 1);
    expect(game.replay.finalChecksum, game.state.checksum());
  });

  test('restart clears the result and starts over', () {
    final game = _game();
    _tick(game, 120);
    game.restart();
    expect(game.state.frame, 0);
    expect(game.result.value, isNull);
    expect(game.replay.ticks, isEmpty);
  });

  test('pause cannot be opened after the match ended', () {
    final game = _game();
    game.result.value = 0;
    game.setPaused(true);
    expect(game.pauseMenuOpen.value, isFalse);
  });

  test('touch input moves the player', () {
    final game = _game();
    _tick(game, 120);
    final startX = game.state.fighters[0].x;
    game.touchInput.setStick(1, 0);
    _tick(game, 10);
    expect(game.state.fighters[0].x > startX, isTrue);
    game.touchInput.press(Button.jump);
    _tick(game, 2);
    expect(game.state.fighters[0].grounded, isFalse);
  });

  test('damage color goes from white to red', () {
    expect(BrawlGame.damageColor(0), Colors.white);
    expect(BrawlGame.damageColor(150), const Color(0xFFFF1744));
    expect(BrawlGame.damageColor(300), const Color(0xFFFF1744));
  });
}
