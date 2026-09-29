import 'package:brawl_arena/ui/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  int winner, {
  VoidCallback? onRematch,
  VoidCallback? onChangeFighter,
}) => tester.pumpWidget(
  MaterialApp(
    home: MatchResultOverlay(
      winner: winner,
      names: const ['Knight', 'Ranger'],
      onRematch: onRematch ?? () {},
      onChangeFighter: onChangeFighter ?? () {},
    ),
  ),
);

void main() {
  testWidgets('player win', (tester) async {
    await _pump(tester, 0);
    expect(find.text('You win!'), findsOneWidget);
    expect(find.text('Knight wins the match'), findsOneWidget);
  });

  testWidgets('player loss', (tester) async {
    await _pump(tester, 1);
    expect(find.text('You lose'), findsOneWidget);
    expect(find.text('Ranger wins the match'), findsOneWidget);
  });

  testWidgets('draw', (tester) async {
    await _pump(tester, -1);
    expect(find.text('Draw'), findsOneWidget);
  });

  testWidgets('Rematch and Change fighter call back', (tester) async {
    var rematches = 0;
    var changes = 0;
    await _pump(
      tester,
      0,
      onRematch: () => rematches++,
      onChangeFighter: () => changes++,
    );
    await tester.tap(find.byKey(const Key('rematch')));
    await tester.tap(find.byKey(const Key('change-fighter')));
    expect((rematches, changes), (1, 1));
  });

  testWidgets('pause menu buttons call back and mute toggles', (tester) async {
    final calls = <String>[];
    final muted = ValueNotifier(false);
    await tester.pumpWidget(
      MaterialApp(
        home: PauseOverlay(
          muted: muted,
          onResume: () => calls.add('resume'),
          onRestart: () => calls.add('restart'),
          onQuit: () => calls.add('quit'),
        ),
      ),
    );
    for (final key in ['resume', 'restart', 'quit']) {
      await tester.tap(find.byKey(Key(key)));
    }
    await tester.tap(find.byKey(const Key('mute')));
    expect(calls, ['resume', 'restart', 'quit']);
    expect(muted.value, isTrue);
  });
}
