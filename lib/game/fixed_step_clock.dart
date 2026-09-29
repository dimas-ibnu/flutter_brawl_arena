/// Turns variable render-frame time into a whole number of fixed simulation
/// ticks.
///
/// This lives outside `sim/` because it deals in real (floating-point) time.
/// It only decides how many ticks to run, never what a tick does.
class FixedStepClock {
  FixedStepClock({this.ticksPerSecond = 60, this.maxTicksPerFrame = 5});

  final int ticksPerSecond;

  /// Cap on catch-up ticks after a long frame (e.g. the app was paused), so
  /// one slow frame doesn't snowball into more slow frames.
  final int maxTicksPerFrame;

  static const int _microsPerSecond = 1000000;

  // Stored as microseconds × ticksPerSecond so a 60 Hz tick divides exactly.
  int _accumulated = 0;

  /// Adds [dtSeconds] of real time and returns how many ticks to run now.
  int advance(double dtSeconds) {
    _accumulated += (dtSeconds * _microsPerSecond).round() * ticksPerSecond;
    var ticks = _accumulated ~/ _microsPerSecond;
    _accumulated -= ticks * _microsPerSecond;
    if (ticks > maxTicksPerFrame) {
      ticks = maxTicksPerFrame;
      _accumulated = 0;
    }
    return ticks;
  }

  /// How far (0..1) real time is into the next tick. Rendering can use it to
  /// blend between the last two states.
  double get alpha => _accumulated / _microsPerSecond;
}
