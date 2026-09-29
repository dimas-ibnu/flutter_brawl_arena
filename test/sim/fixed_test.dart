import 'package:brawl_arena/sim/fixed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('integers round-trip', () {
    expect(const Fx.fromInt(7).floorToInt(), 7);
    expect(const Fx.fromInt(-3).floorToInt(), -3);
  });

  test('ratio builds exact fractions', () {
    expect(const Fx.ratio(1, 2).toDouble(), 0.5);
    expect(const Fx.ratio(3, 4).toDouble(), 0.75);
  });

  test('arithmetic', () {
    const a = Fx.fromInt(6);
    const b = Fx.ratio(1, 2);
    expect((a + b).toDouble(), 6.5);
    expect((a - b).toDouble(), 5.5);
    expect((a * b).toDouble(), 3);
    expect((a / b).toDouble(), 12);
    expect((-a).toDouble(), -6);
    expect(a.mulInt(3), const Fx.fromInt(18));
    expect(a.divInt(4).toDouble(), 1.5);
  });

  test('negative multiply is exact for representable results', () {
    expect((const Fx.fromInt(-6) * const Fx.ratio(1, 4)).toDouble(), -1.5);
  });

  test('floorToInt rounds toward negative infinity', () {
    expect(const Fx.ratio(-1, 2).floorToInt(), -1);
    expect(const Fx.ratio(1, 2).floorToInt(), 0);
  });

  test('comparisons, min, max, clamp, abs', () {
    const lo = Fx.fromInt(-2);
    const hi = Fx.fromInt(5);
    expect(lo < hi, isTrue);
    expect(hi >= hi, isTrue);
    expect(Fx.min(lo, hi), lo);
    expect(Fx.max(lo, hi), hi);
    expect(const Fx.fromInt(9).clamp(lo, hi), hi);
    expect(const Fx.fromInt(-9).clamp(lo, hi), lo);
    expect(lo.abs(), const Fx.fromInt(2));
  });

  test('fromDouble rounds to the nearest step', () {
    expect(Fx.fromDouble(0.25), const Fx.ratio(1, 4));
    expect(Fx.fromDouble(-1.5), const Fx.ratio(-3, 2));
  });
}
