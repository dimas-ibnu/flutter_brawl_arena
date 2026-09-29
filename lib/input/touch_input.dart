import '../sim/input_frame.dart';

/// Holds what the on-screen controls are pressing right now.
///
/// The touch widgets write to it; the game reads [frame] once per tick and
/// combines it with the keyboard.
class TouchInput {
  /// Stick push (as a fraction of its radius) needed to count as a direction.
  /// Up is harder to reach on purpose, because up also jumps.
  static const double horizontalThreshold = 0.3;
  static const double downThreshold = 0.5;
  static const double upThreshold = 0.65;

  int _stickBits = 0;
  final Map<Button, int> _pointersOnButton = {};

  InputFrame get frame {
    var bits = _stickBits;
    _pointersOnButton.forEach((button, count) {
      if (count > 0) bits |= button.bit;
    });
    return InputFrame(bits);
  }

  /// [dx], [dy]: stick offset from its center divided by its radius, so
  /// -1..1 on each axis (y grows downward). Pass 0, 0 when released.
  void setStick(double dx, double dy) {
    _stickBits = stickBits(dx, dy);
  }

  void press(Button button) =>
      _pointersOnButton[button] = (_pointersOnButton[button] ?? 0) + 1;

  void release(Button button) {
    final count = (_pointersOnButton[button] ?? 0) - 1;
    _pointersOnButton[button] = count < 0 ? 0 : count;
  }

  /// Clears everything, e.g. when the app goes to the background.
  void reset() {
    _stickBits = 0;
    _pointersOnButton.clear();
  }

  static int stickBits(double dx, double dy) {
    var bits = 0;
    if (dx <= -horizontalThreshold) bits |= Button.left.bit;
    if (dx >= horizontalThreshold) bits |= Button.right.bit;
    if (dy <= -upThreshold) bits |= Button.up.bit;
    if (dy >= downThreshold) bits |= Button.down.bit;
    return bits;
  }
}
