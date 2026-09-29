// Cross-platform determinism: these values were recorded on native. The
// same test must pass compiled to JavaScript:
//   flutter test test/web --platform chrome
// If web and native disagree, online play between them would desync.
import 'package:brawl_arena/ai/bot.dart';
import 'package:brawl_arena/data/fighter_data.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:brawl_arena/sim/game_state.dart';
import 'package:brawl_arena/sim/int_math.dart';
import 'package:brawl_arena/sim/match_simulation.dart';
import 'package:brawl_arena/sim/rules_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fighters_fixture.dart';

void main() {
  final fighters = parseFighters(fightersFixture);
  final defs = [fighters['knight']!, fighters['ranger']!];
  MatchSimulation sim() =>
      MatchSimulation(stage: StageDef.flatArena, fighterDefs: defs);

  test('fixed-point math', () {
    expect(Fx.fromInt(-500).raw, -500 * 65536);
    expect((Fx.fromInt(-500) * const Fx.ratio(3, 5)).raw, -19660500);
    expect(Fx.fromDouble(-0.6).raw, -39322);
    expect((Fx.fromInt(-7) / Fx.fromInt(3)).raw, -152917);
    expect(const Fx.ratio(-1, 2).floorToInt(), -1);
    expect(Fx.fromInt(-500) < Fx.fromInt(500), isTrue);
  });

  test('32-bit helpers', () {
    // Exact value; the plain product would lose precision on web.
    expect(mul32(0xFFFFFFFF, 0x01000193), 4278189677);
    expect(xor32(0xF0F0F0F0, 0x0F0F0F0F), 0xFFFFFFFF);
    expect(hi32(-1), 0xFFFFFFFF);
    expect(lo32(-1), 0xFFFFFFFF);
    expect(floorDiv(-1, 65536), -1);
  });

  test('stage edges keep their sign (the web bug)', () {
    final s = StageDef.flatArena;
    expect(s.groundLeft.toDouble(), -500);
    expect(s.blastLeft.toDouble(), -1100);
    expect(s.groundLeft < s.groundRight, isTrue);
  });

  test('random numbers', () {
    final g = GameState(fighters: [], seed: 99);
    expect(
      [for (var i = 0; i < 5; i++) g.nextRandom(1000000)],
      [193669, 245289, 753847, 6716, 645631],
    );
  });

  test('rules fingerprint', () {
    expect(rulesFingerprint(sim(), defs), 1522397744);
  });

  test('a full bot match gives the same checksums', () {
    final m = sim();
    final s = m.initialState(seed: 12345);
    final a = Bot(sim: m, slot: 0, seed: 7);
    final b = Bot(sim: m, slot: 1, seed: 9);
    final sums = <int>[];
    for (var i = 0; i < 3000 && !s.finished; i++) {
      m.step(s, [a.think(s), b.think(s)]);
      if (i % 500 == 0) sums.add(s.checksum());
    }
    expect(sums, [
      345230563,
      3193348129,
      1255503906,
      2792229127,
      3654042234,
      2477820900,
    ]);
    expect(s.checksum(), 3553198316);
    expect(s.frame, 2900);
  });
}
