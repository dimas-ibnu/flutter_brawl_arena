import 'package:brawl_arena/sim/input_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('of packs buttons and isHeld reads them', () {
    final input = InputFrame.of([Button.left, Button.jump]);
    expect(input.isHeld(Button.left), isTrue);
    expect(input.isHeld(Button.jump), isTrue);
    expect(input.isHeld(Button.right), isFalse);
    expect(InputFrame.none.isHeld(Button.jump), isFalse);
  });

  test('wasPressed is true only on the first held tick', () {
    final held = InputFrame.of([Button.light]);
    expect(held.wasPressed(Button.light, InputFrame.none), isTrue);
    expect(held.wasPressed(Button.light, held), isFalse);
  });

  test('directions', () {
    expect(InputFrame.of([Button.left]).horizontal, -1);
    expect(InputFrame.of([Button.right]).horizontal, 1);
    expect(InputFrame.of([Button.left, Button.right]).horizontal, 0);
    expect(InputFrame.of([Button.up]).vertical, -1);
    expect(InputFrame.of([Button.down]).vertical, 1);
  });
}
