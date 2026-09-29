import 'int_math.dart';

/// Fixed-point number in Q16.16 format, stored in a plain `int`.
///
/// All gameplay math in the simulation uses [Fx] instead of `double`, so the
/// same inputs give bit-identical results on every device. Replays and
/// rollback netcode depend on that.
///
/// Values must stay within about ±32,000 world units so products don't
/// overflow 64-bit ints.
extension type const Fx.raw(int raw) {
  static const int fractionBits = 16;
  static const int _one = 65536; // 2^fractionBits

  static const Fx zero = Fx.raw(0);
  static const Fx one = Fx.raw(_one);

  const Fx.fromInt(int value) : raw = value * _one;

  /// [numerator] / [denominator] as a constant, e.g. `Fx.ratio(1, 2)` = 0.5.
  const Fx.ratio(int numerator, int denominator)
    : raw = (numerator * _one) ~/ denominator;

  /// Converts a double to fixed point. Use only for loading tuning data,
  /// never inside the simulation step.
  factory Fx.fromDouble(double value) => Fx.raw((value * _one).round());

  Fx operator +(Fx other) => Fx.raw(raw + other.raw);
  Fx operator -(Fx other) => Fx.raw(raw - other.raw);
  Fx operator -() => Fx.raw(-raw);

  /// floor(a * b / 2^16), computed in two halves so no product exceeds
  /// 2^47: exact on both native and web.
  Fx operator *(Fx other) {
    final high = floorDiv(raw, _one);
    final low = raw % _one;
    return Fx.raw(high * other.raw + floorDiv(low * other.raw, _one));
  }

  Fx operator /(Fx other) => Fx.raw((raw * _one) ~/ other.raw);

  Fx mulInt(int factor) => Fx.raw(raw * factor);
  Fx divInt(int divisor) => Fx.raw(raw ~/ divisor);

  bool operator <(Fx other) => raw < other.raw;
  bool operator <=(Fx other) => raw <= other.raw;
  bool operator >(Fx other) => raw > other.raw;
  bool operator >=(Fx other) => raw >= other.raw;

  bool get isNegative => raw < 0;
  Fx abs() => raw < 0 ? Fx.raw(-raw) : this;
  Fx clamp(Fx low, Fx high) => this < low ? low : (this > high ? high : this);

  /// Rounds toward negative infinity.
  int floorToInt() => floorDiv(raw, _one);

  /// For rendering and debugging only.
  double toDouble() => raw / _one;

  static Fx min(Fx a, Fx b) => a < b ? a : b;
  static Fx max(Fx a, Fx b) => a > b ? a : b;
}
