import 'dart:typed_data';

import 'package:brawl_arena/ai/bot.dart';
import 'package:brawl_arena/net/net_match.dart';
import 'package:brawl_arena/net/protocol.dart';
import 'package:brawl_arena/net/rollback_session.dart';
import 'package:brawl_arena/net/transport.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';

MatchSimulation _sim() => MatchSimulation(
  stage: StageDef.flatArena,
  fighterDefs: [knightDef, rangerDef],
);

/// Two peers, each controlled by its own bot, playing over [net].
class _Online {
  _Online(this.net, {int seed = 5, int inputDelay = 2}) {
    for (var slot = 0; slot < 2; slot++) {
      final sim = _sim();
      peers.add(
        NetMatch(
          session: RollbackSession(
            sim: sim,
            seed: seed,
            localSlot: slot,
            inputDelay: inputDelay,
          ),
          transport: slot == 0 ? net.a : net.b,
        ),
      );
      bots.add(Bot(sim: sim, slot: slot, seed: 100 + slot));
      inputs.add({for (var f = 0; f < inputDelay; f++) f: 0});
    }
  }

  final FakeNetwork net;
  final peers = <NetMatch>[];
  final bots = <Bot>[];

  /// What each peer actually sent, by frame: the true input history.
  final inputs = <Map<int, int>>[];

  void run(int ticks, {bool idle = false}) {
    for (var t = 0; t < ticks; t++) {
      for (var slot = 0; slot < 2; slot++) {
        final peer = peers[slot];
        final input = idle ? InputFrame.none : bots[slot].think(peer.state);
        if (peer.tick(input)) {
          final s = peer.session;
          inputs[slot][s.frame - 1 + s.inputDelay] = input.bits;
        }
      }
      net.advance();
    }
  }

  /// Checksums both peers recorded for the same frames.
  List<int> commonChecksumFrames() {
    final a = peers[0].session.confirmedChecksums;
    final b = peers[1].session.confirmedChecksums;
    return [
      for (final f in a.keys)
        if (b.containsKey(f)) f,
    ]..sort();
  }

  /// Offline simulation of the true input history, up to [frame].
  int offlineChecksumAt(int frame) {
    final sim = _sim();
    final state = sim.initialState(seed: 5);
    for (var f = 0; f < frame; f++) {
      sim.step(state, [InputFrame(inputs[0][f]!), InputFrame(inputs[1][f]!)]);
    }
    return state.checksum();
  }
}

void _expectInSync(_Online game) {
  final frames = game.commonChecksumFrames();
  expect(frames.length, greaterThan(5), reason: 'checksums were exchanged');
  for (final f in frames) {
    expect(
      game.peers[0].session.confirmedChecksums[f],
      game.peers[1].session.confirmedChecksums[f],
      reason: 'frame $f',
    );
  }
  expect(game.peers[0].desynced, isFalse);
  expect(game.peers[1].desynced, isFalse);
}

void main() {
  _unevenRates();

  group('protocol', () {
    Packet roundTrip(Packet p) => Packet.decode(p.encode());

    test('input packets keep frames, inputs and ack', () {
      final p =
          roundTrip(
                const InputPacket(
                  startFrame: 1234,
                  inputs: [0, 5, 511, 3],
                  ackFrame: 1200,
                ),
              )
              as InputPacket;
      expect(p.startFrame, 1234);
      expect(p.inputs, [0, 5, 511, 3]);
      expect(p.ackFrame, 1200);
    });

    test('an empty input packet with no ack yet', () {
      final p =
          roundTrip(const InputPacket(startFrame: 0, inputs: [], ackFrame: -1))
              as InputPacket;
      expect(p.inputs, isEmpty);
      expect(p.ackFrame, -1);
    });

    test('checksum, ping and quit packets', () {
      final c =
          roundTrip(const ChecksumPacket(frame: 600, checksum: 0xDEADBEEF))
              as ChecksumPacket;
      expect((c.frame, c.checksum), (600, 0xDEADBEEF));
      final ping =
          roundTrip(const PingPacket(id: 42, reply: true)) as PingPacket;
      expect((ping.id, ping.reply), (42, true));
      expect(roundTrip(const QuitPacket()), isA<QuitPacket>());
    });

    test('hello and start packets', () {
      final h =
          roundTrip(
                const HelloPacket(fighterId: 'knight', skinId: 'knight_neon'),
              )
              as HelloPacket;
      expect(
        (h.fighterId, h.skinId, h.version),
        ('knight', 'knight_neon', Packet.protocolVersion),
      );
      final s =
          roundTrip(
                const StartPacket(
                  seed: 99,
                  fighterIds: ['knight', 'ranger'],
                  skinIds: ['a', 'b'],
                  paletteId: 'midnight',
                ),
              )
              as StartPacket;
      expect(s.seed, 99);
      expect(s.fighterIds, ['knight', 'ranger']);
      expect(s.skinIds, ['a', 'b']);
      expect(s.paletteId, 'midnight');
    });

    test('unknown packet types are rejected', () {
      expect(
        () => Packet.decode(Uint8List.fromList([99])),
        throwsFormatException,
      );
    });
  });

  group('rollback session', () {
    test('a perfect network stays in sync with no rollbacks needed', () {
      final game = _Online(FakeNetwork());
      game.run(600);
      _expectInSync(game);
    });

    test('lag, jitter and 20% packet loss still stay in sync', () {
      final game = _Online(
        FakeNetwork(delayTicks: 5, jitterTicks: 3, lossPercent: 20, seed: 9),
      );
      game.run(1800);
      _expectInSync(game);
      expect(game.net.dropped, greaterThan(0));
      expect(
        game.peers[0].session.rollbacks + game.peers[1].session.rollbacks,
        greaterThan(0),
        reason: 'predictions were corrected',
      );
    });

    test('both peers match an offline replay of the real inputs', () {
      final game = _Online(
        FakeNetwork(delayTicks: 4, jitterTicks: 2, lossPercent: 10, seed: 3),
      );
      game.run(1200);
      game.run(60, idle: true); // let the last inputs arrive
      final frames = game.commonChecksumFrames();
      final last = frames.last;
      expect(
        game.peers[0].session.confirmedChecksums[last],
        game.offlineChecksumAt(last),
      );
    });

    test('a full online bot match reaches a result on both sides', () {
      final game = _Online(
        FakeNetwork(delayTicks: 3, jitterTicks: 2, lossPercent: 5),
      );
      for (var i = 0; i < 4 * 60 * 60 + 600; i++) {
        game.run(1);
        if (game.peers.every((p) => p.state.finished)) break;
      }
      game.run(60, idle: true);
      expect(game.peers[0].state.finished, isTrue);
      expect(game.peers[0].state.winner, game.peers[1].state.winner);
      _expectInSync(game);
    });

    test('it waits instead of running too far ahead of a silent peer', () {
      final sim = _sim();
      final net = FakeNetwork();
      final lonely = NetMatch(
        session: RollbackSession(sim: sim, seed: 1, localSlot: 0),
        transport: net.a,
      );
      for (var i = 0; i < 100; i++) {
        lonely.tick(InputFrame.none);
        net.advance();
      }
      expect(lonely.session.frame, lonely.session.maxRollback + 0);
      expect(lonely.session.stalls, greaterThan(80));
      expect(lonely.ticksSinceHeard, 100);
    });

    test('a changed state is caught as a desync', () {
      final game = _Online(FakeNetwork());
      game.run(120);
      // Cheat on peer 0: once everything so far is confirmed, change it.
      game.peers[0].state.fighters[1].damage += 50;
      game.run(300);
      expect(game.peers[0].desynced || game.peers[1].desynced, isTrue);
    });

    test('the other side quitting is noticed', () {
      final game = _Online(FakeNetwork());
      game.run(30);
      game.peers[1].quit();
      game.net.advance();
      game.peers[0].tick(InputFrame.none);
      expect(game.peers[0].remoteQuit, isTrue);
    });

    test('round-trip time is measured', () {
      final game = _Online(FakeNetwork(delayTicks: 6));
      game.run(200);
      expect(game.peers[0].rttTicks, closeTo(12, 3));
    });
  });
}

/// Regression: devices never tick in lockstep. When one side ran slower, the
/// fast side's inputs arrived ahead of its clock and were pruned before use,
/// so the first attack desynced ("Out of sync").
void _unevenRates() {
  group('uneven tick rates (real devices)', () {
    for (final (label, rateB, delay, loss) in [
      ('guest slower', 0.7, 3, 0),
      ('guest much slower, lossy', 0.5, 6, 20),
      ('guest in bursts', 1.6, 5, 10),
    ]) {
      test('$label stays in sync while both attack', () {
        final net = FakeNetwork(
          delayTicks: delay,
          jitterTicks: 2,
          lossPercent: loss,
          seed: 4,
        );
        NetMatch peer(int slot) => NetMatch(
          session: RollbackSession(sim: _sim(), seed: 3, localSlot: slot),
          transport: slot == 0 ? net.a : net.b,
        );
        final peers = [peer(0), peer(1)];
        final spam = [
          Bot(sim: _sim(), slot: 0, seed: 1),
          Bot(sim: _sim(), slot: 1, seed: 2),
        ];
        var owed = 0.0;
        for (var t = 0; t < 2400; t++) {
          peers[0].tick(spam[0].think(peers[0].state));
          owed += rateB;
          while (owed >= 1) {
            peers[1].tick(spam[1].think(peers[1].state));
            owed -= 1;
          }
          net.advance();
        }
        final a = peers[0].session.confirmedChecksums;
        final b = peers[1].session.confirmedChecksums;
        final common = a.keys.where(b.containsKey).toList();
        expect(common.length, greaterThan(10));
        for (final f in common) {
          expect(a[f], b[f], reason: 'frame $f');
        }
        expect(peers.any((p) => p.desynced), isFalse);
        final hits = peers[0].state.fighters.map((f) => f.damage + f.stocks);
        expect(hits, isNotEmpty);
      });
    }
  });
}
