enum Button {
  left,
  right,
  up,
  down,
  jump,
  light,
  heavy,
  dodge,
  weapon;

  int get bit => 1 << index;
}

/// One player's input for one simulation tick: 4 directions + 5 buttons,
/// packed into an int.
///
/// Keyboard, touch, the bot and (later) the network all produce this same
/// value, so the simulation never knows where an input came from.
extension type const InputFrame(int bits) {
  static const InputFrame none = InputFrame(0);

  factory InputFrame.of(Iterable<Button> buttons) =>
      InputFrame(buttons.fold(0, (bits, b) => bits | b.bit));

  bool isHeld(Button button) => bits & button.bit != 0;

  /// True only on the tick the button goes down.
  bool wasPressed(Button button, InputFrame previous) =>
      isHeld(button) && !previous.isHeld(button);

  /// -1 for left, 1 for right, 0 for neither or both.
  int get horizontal =>
      (isHeld(Button.right) ? 1 : 0) - (isHeld(Button.left) ? 1 : 0);

  /// -1 for up, 1 for down (screen coordinates), 0 for neither or both.
  int get vertical =>
      (isHeld(Button.down) ? 1 : 0) - (isHeld(Button.up) ? 1 : 0);
}
