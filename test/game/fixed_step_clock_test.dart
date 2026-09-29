import 'package:brawl_arena/game/fixed_step_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one 60 Hz frame gives one tick', () {
    final clock = FixedStepClock();
    expect(clock.advance(1 / 60), 1);
  });

  test('1 second of 60 Hz frames gives 60 ticks', () {
    final clock = FixedStepClock();
    var ticks = 0;
    for (var i = 0; i < 60; i++) {
      ticks += clock.advance(1 / 60);
    }
    expect(ticks, 60);
  });

  test('120 Hz frames run a tick about every second frame', () {
    final clock = FixedStepClock();
    var ticks = 0;
    for (var i = 0; i < 1200; i++) {
      ticks += clock.advance(1 / 120);
    }
    // Microsecond rounding may lose one tick over 10 seconds.
    expect(ticks, inInclusiveRange(599, 600));
  });

  test('a long pause is capped', () {
    final clock = FixedStepClock(maxTicksPerFrame: 5);
    expect(clock.advance(2), 5);
    expect(clock.advance(0), 0);
  });

  test('alpha tracks progress into the next tick', () {
    final clock = FixedStepClock();
    clock.advance(1 / 120);
    expect(clock.alpha, closeTo(0.5, 0.01));
  });
}
