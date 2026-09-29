import 'package:brawl_arena/input/touch_input.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stick', () {
    test('small pushes stay in the dead zone', () {
      expect(TouchInput.stickBits(0.2, 0.2), 0);
      expect(TouchInput.stickBits(0, 0), 0);
    });

    test('left and right', () {
      final left = InputFrame(TouchInput.stickBits(-0.5, 0));
      final right = InputFrame(TouchInput.stickBits(0.5, 0));
      expect(left.horizontal, -1);
      expect(right.horizontal, 1);
    });

    test('up needs a stronger push than down, since up also jumps', () {
      expect(
        InputFrame(TouchInput.stickBits(0, -0.5)).isHeld(Button.up),
        isFalse,
      );
      expect(
        InputFrame(TouchInput.stickBits(0, -0.8)).isHeld(Button.up),
        isTrue,
      );
      expect(
        InputFrame(TouchInput.stickBits(0, 0.5)).isHeld(Button.down),
        isTrue,
      );
    });

    test('diagonals give two directions', () {
      final frame = InputFrame(TouchInput.stickBits(0.7, 0.7));
      expect(frame.isHeld(Button.right), isTrue);
      expect(frame.isHeld(Button.down), isTrue);
    });
  });

  group('buttons', () {
    test('press and release', () {
      final touch = TouchInput()..press(Button.jump);
      expect(touch.frame.isHeld(Button.jump), isTrue);
      touch.release(Button.jump);
      expect(touch.frame.isHeld(Button.jump), isFalse);
    });

    test('stays held while any finger is still on it', () {
      final touch = TouchInput()
        ..press(Button.light)
        ..press(Button.light)
        ..release(Button.light);
      expect(touch.frame.isHeld(Button.light), isTrue);
    });

    test('extra releases do not go negative', () {
      final touch = TouchInput()
        ..release(Button.dodge)
        ..press(Button.dodge);
      expect(touch.frame.isHeld(Button.dodge), isTrue);
    });

    test('stick and buttons combine; reset clears both', () {
      final touch = TouchInput()
        ..setStick(1, 0)
        ..press(Button.heavy);
      expect(touch.frame.isHeld(Button.right), isTrue);
      expect(touch.frame.isHeld(Button.heavy), isTrue);
      touch.reset();
      expect(touch.frame, InputFrame.none);
    });
  });
}
