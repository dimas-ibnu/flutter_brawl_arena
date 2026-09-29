/// Integer helpers that give the same answer on native (64-bit ints) and
/// web (JavaScript numbers).
///
/// On web a Dart `int` is a JavaScript double: exact only up to 2^53, and
/// bit operators (`<<`, `>>`, `&`, `^`) truncate to 32 bits. So the
/// simulation never uses bit operators on large values; it uses `*`, `~/`
/// and `%` on numbers that stay below 2^53, where both platforms agree.
library;

const int two16 = 65536;
const int two32 = 4294967296;

/// Floor division for a positive divisor (like `>>` for powers of two).
/// Dart's `%` is never negative, so `x - x % d` is always a multiple of d.
int floorDiv(int x, int d) => (x - x % d) ~/ d;

/// The low 32 bits of [x], as 0..2^32-1.
int lo32(int x) => x % two32;

/// Bits 32..63 of [x], as 0..2^32-1 (x must stay within ±2^53).
int hi32(int x) => floorDiv(x, two32) % two32;

/// (a * b) mod 2^32 for 32-bit unsigned [a] and [b], without ever forming
/// the full 64-bit product (which would lose precision on web).
int mul32(int a, int b) {
  final aHigh = a ~/ two16;
  final aLow = a % two16;
  return ((aHigh * b % two16) * two16 + aLow * b) % two32;
}

/// XOR of two 32-bit unsigned values, always 0..2^32-1 on both platforms.
int xor32(int a, int b) {
  final aH = a ~/ two16, aL = a % two16, bH = b ~/ two16, bL = b % two16;
  return (aH ^ bH) * two16 + (aL ^ bL);
}

/// One xorshift32 step: the random generator used by the match and the bot.
int xorshift32(int x) {
  x = xor32(x, (x * 8192) % two32); // x ^= x << 13
  x = xor32(x, x ~/ 131072); // x ^= x >> 17
  x = xor32(x, (x * 32) % two32); // x ^= x << 5
  return x;
}

/// Adds [v] (any int within ±2^53) to an FNV-1a hash, as two 32-bit words.
int fnvAdd(int hash, int v) {
  hash = mul32(xor32(hash, lo32(v)), 0x01000193);
  return mul32(xor32(hash, hi32(v)), 0x01000193);
}

const int fnvStart = 0x811C9DC5;
