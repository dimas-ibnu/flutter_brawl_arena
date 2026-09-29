import 'dart:convert';
import 'dart:io';

import 'package:brawl_arena/data/fighter_data.dart';
import 'package:brawl_arena/net/lobby.dart';
import 'package:brawl_arena/net/protocol.dart';
import 'package:brawl_arena/net/transport.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:brawl_arena/sim/rules_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

int _fingerprint(List<FighterDef> roster, {int respawnDelay = 90}) =>
    rulesFingerprint(
      MatchSimulation(
        stage: StageDef.flatArena,
        fighterDefs: roster,
        respawnDelayTicks: respawnDelay,
      ),
      roster,
    );

void main() {
  final roster = [knightDef, rangerDef];

  test('the same data gives the same fingerprint', () {
    expect(_fingerprint(roster), _fingerprint([knightDef, rangerDef]));
  });

  test('changing one move number changes it', () {
    final json =
        jsonDecode(File(fightersAsset).readAsStringSync())
            as Map<String, dynamic>;
    (json['knight']['moves']['neutralLight'] as Map)['damage'] = 8;
    final tweaked = parseFighters(jsonEncode(json));
    expect(
      _fingerprint([tweaked['knight']!, tweaked['ranger']!]),
      isNot(_fingerprint(roster)),
    );
  });

  test('changing a match rule changes it', () {
    expect(
      _fingerprint(roster, respawnDelay: 120),
      isNot(_fingerprint(roster)),
    );
  });

  test('the lobby refuses players with different rules', () {
    final net = FakeNetwork();
    final host = LobbyHandshake(
      transport: net.a,
      isHost: true,
      hello: const HelloPacket(fighterId: 'knight', skinId: 'k', rules: 111),
      makeStart: (g) => const StartPacket(
        seed: 1,
        fighterIds: ['knight', 'ranger'],
        skinIds: ['k', 'r'],
        paletteId: 'sunset',
      ),
    );
    final guest = LobbyHandshake(
      transport: net.b,
      isHost: false,
      hello: const HelloPacket(fighterId: 'ranger', skinId: 'r', rules: 222),
    );
    for (var i = 0; i < 60; i++) {
      host.tick();
      guest.tick();
      net.advance();
    }
    expect(host.error, contains('different version'));
    expect(guest.error, contains('different version'));
    expect(host.start, isNull);
  });
}
