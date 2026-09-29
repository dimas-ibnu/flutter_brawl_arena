import 'package:brawl_arena/input/touch_input.dart';
import 'package:brawl_arena/sim/input_frame.dart';
import 'package:brawl_arena/ui/touch_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TouchInput> _pump(WidgetTester tester) async {
  // Landscape phone size.
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final input = TouchInput();
  await tester.pumpWidget(MaterialApp(home: TouchControls(input: input)));
  return input;
}

void main() {
  testWidgets('holding a button holds it in the input', (tester) async {
    final input = await _pump(tester);
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('touch-jump'))),
    );
    await tester.pump();
    expect(input.frame.isHeld(Button.jump), isTrue);

    await finger.up();
    await tester.pump();
    expect(input.frame.isHeld(Button.jump), isFalse);
  });

  testWidgets('dragging the stick right walks right', (tester) async {
    final input = await _pump(tester);
    final stick = tester.getCenter(find.byKey(const Key('touch-stick')));
    final finger = await tester.startGesture(stick);
    await finger.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(input.frame.horizontal, 1);

    await finger.up();
    await tester.pump();
    expect(input.frame, InputFrame.none);
  });

  testWidgets('stick and a button work at the same time', (tester) async {
    final input = await _pump(tester);
    final stickFinger = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('touch-stick'))),
    );
    await stickFinger.moveBy(const Offset(-60, 0));
    final buttonFinger = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('touch-light'))),
    );
    await tester.pump();

    expect(input.frame.horizontal, -1);
    expect(input.frame.isHeld(Button.light), isTrue);

    await stickFinger.up();
    await buttonFinger.up();
  });

  testWidgets('all five buttons are on screen and do not overlap', (
    tester,
  ) async {
    await _pump(tester);
    final rects = [
      for (final b in [
        Button.jump,
        Button.light,
        Button.heavy,
        Button.dodge,
        Button.weapon,
      ])
        tester.getRect(find.byKey(Key('touch-${b.name}'))),
    ];
    final screen = Offset.zero & tester.view.physicalSize / 3;
    for (var i = 0; i < rects.length; i++) {
      expect(screen.contains(rects[i].topLeft), isTrue);
      expect(
        screen.contains(rects[i].bottomRight - const Offset(1, 1)),
        isTrue,
      );
      for (var j = i + 1; j < rects.length; j++) {
        expect(
          rects[i].overlaps(rects[j]),
          isFalse,
          reason: 'button $i overlaps button $j',
        );
      }
    }
  });
}
