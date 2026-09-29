import 'package:brawl_arena/net/lobby.dart';
import 'package:brawl_arena/net/net_match.dart';
import 'package:brawl_arena/net/protocol.dart';
import 'package:brawl_arena/net/rollback_session.dart';
import 'package:brawl_arena/net/transport.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

StartPacket _start(HelloPacket guest) => StartPacket(
  seed: 77,
  fighterIds: ['knight', guest.fighterId],
  skinIds: ['knight_neon', guest.skinId],
  paletteId: 'midnight',
);

(LobbyHandshake, LobbyHandshake) _pair(FakeNetwork net) => (
  LobbyHandshake(
    transport: net.a,
    isHost: true,
    hello: const HelloPacket(fighterId: 'knight', skinId: 'knight_neon'),
    makeStart: _start,
  ),
  LobbyHandshake(
    transport: net.b,
    isHost: false,
    hello: const HelloPacket(fighterId: 'ranger', skinId: 'ranger_jade'),
  ),
);

void _run(FakeNetwork net, LobbyHandshake host, LobbyHandshake guest, int n) {
  for (var i = 0; i < n && !(host.done && guest.done); i++) {
    host.tick();
    guest.tick();
    net.advance();
  }
}

void main() {
  test('host and guest agree on the match settings', () {
    final net = FakeNetwork(delayTicks: 3);
    final (host, guest) = _pair(net);
    _run(net, host, guest, 120);
    expect(host.start, isNotNull);
    expect(guest.start?.seed, 77);
    expect(guest.start?.fighterIds, ['knight', 'ranger']);
    expect(guest.start?.skinIds, ['knight_neon', 'ranger_jade']);
    expect(host.remoteHello?.fighterId, 'ranger');
  });

  test('survives heavy packet loss by resending', () {
    final net = FakeNetwork(delayTicks: 4, lossPercent: 40, seed: 2);
    final (host, guest) = _pair(net);
    _run(net, host, guest, 600);
    expect(host.done && guest.done, isTrue);
  });

  test('a different game version is refused', () {
    final net = FakeNetwork();
    final host = LobbyHandshake(
      transport: net.a,
      isHost: true,
      hello: const HelloPacket(fighterId: 'knight', skinId: 'k'),
      makeStart: _start,
    );
    final guest = LobbyHandshake(
      transport: net.b,
      isHost: false,
      hello: const HelloPacket(fighterId: 'ranger', skinId: 'r', version: 999),
    );
    _run(net, host, guest, 60);
    expect(host.error, contains('version'));
  });

  test('a lost start packet is resent once the match begins', () {
    // Everything the host sends is lost until tick 40.
    final net = FakeNetwork();
    final (host, guest) = _pair(net);
    for (var i = 0; i < 5; i++) {
      host.tick();
      guest.tick();
      net.advance();
    }
    expect(host.start, isNotNull);
    net.b.poll(); // the guest never sees the first start packet

    MatchSimulation sim() => MatchSimulation(
      stage: StageDef.flatArena,
      fighterDefs: [knightDef, rangerDef],
    );
    final hostMatch = NetMatch(
      session: RollbackSession(sim: sim(), seed: 77, localSlot: 0),
      transport: net.a,
      resendUntilHeard: host.start,
    );
    for (var i = 0; i < 40 && guest.start == null; i++) {
      hostMatch.tick(InputFrame.none);
      guest.tick();
      net.advance();
    }
    expect(guest.start?.seed, 77);
  });
}
