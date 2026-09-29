import 'package:brawl_arena/game/brawl_game.dart';
import 'package:brawl_arena/net/net_match.dart';
import 'package:brawl_arena/net/rollback_session.dart';
import 'package:brawl_arena/net/transport.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:brawl_arena/ui/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/roster.dart';

/// Host plays the Knight (slot 0), guest the Ranger (slot 1).
(BrawlGame, BrawlGame, FakeNetwork) _onlinePair({int delay = 3}) {
  final net = FakeNetwork(delayTicks: delay);
  final knight = rosterEntry('knight');
  final ranger = rosterEntry('ranger');
  BrawlGame side(int slot) {
    final sim = MatchSimulation(
      stage: StageDef.flatArena,
      fighterDefs: [knight.def, ranger.def],
    );
    return BrawlGame(
      player: slot == 0 ? knight : ranger,
      opponent: slot == 0 ? ranger : knight,
      seed: 11,
      localSlot: slot,
      online: NetMatch(
        session: RollbackSession(sim: sim, seed: 11, localSlot: slot),
        transport: slot == 0 ? net.a : net.b,
      ),
    );
  }

  return (side(0), side(1), net);
}

void _tick(BrawlGame a, BrawlGame b, FakeNetwork net, int ticks) {
  for (var i = 0; i < ticks; i++) {
    a.update(1 / 60);
    b.update(1 / 60);
    net.advance();
  }
}

void main() {
  test('both sides run the same match with slots by role', () {
    final (host, guest, net) = _onlinePair();
    expect(host.entries.map((e) => e.id), ['knight', 'ranger']);
    expect(guest.entries.map((e) => e.id), ['knight', 'ranger']);

    _tick(host, guest, net, 300);
    final a = host.online!.session.confirmedChecksums;
    final b = guest.online!.session.confirmedChecksums;
    final common = a.keys.where(b.containsKey).toList();
    expect(common, isNotEmpty);
    for (final f in common) {
      expect(a[f], b[f]);
    }
  });

  test('the guest controls slot 1', () {
    final (host, guest, net) = _onlinePair(delay: 0);
    _tick(host, guest, net, 120);
    final startX = guest.state.fighters[1].x;
    guest.touchInput.setStick(-1, 0);
    _tick(host, guest, net, 30);
    expect(guest.state.fighters[1].x < startX, isTrue);
    // The host sees the guest move too.
    expect(host.state.fighters[1].x < startX, isTrue);
  });

  test('online matches cannot restart', () {
    final (host, guest, net) = _onlinePair();
    _tick(host, guest, net, 60);
    final frame = host.state.frame;
    host.restart();
    expect(host.state.frame, frame);
  });

  test('the opponent leaving is shown', () {
    final (host, guest, net) = _onlinePair();
    _tick(host, guest, net, 60);
    guest.leaveOnline();
    for (var i = 0; i < 10; i++) {
      host.update(1 / 60);
      net.advance();
    }
    expect(host.connectionProblem.value, 'Opponent left');
  });

  test('silence for 5 seconds is a lost connection', () {
    final (host, guest, net) = _onlinePair();
    _tick(host, guest, net, 60);
    for (var i = 0; i < 6 * 60; i++) {
      host.update(1 / 60); // the guest has vanished
      net.advance();
    }
    expect(host.connectionProblem.value, 'Connection lost');
  });

  testWidgets('online results say You win for the guest when slot 1 wins', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MatchResultOverlay(
          winner: 1,
          localSlot: 1,
          names: const ['Knight', 'Ranger'],
          onRematch: null,
          onChangeFighter: () {},
        ),
      ),
    );
    expect(find.text('You win!'), findsOneWidget);
    expect(find.byKey(const Key('rematch')), findsNothing);
    expect(find.text('Leave'), findsOneWidget);
  });
}
