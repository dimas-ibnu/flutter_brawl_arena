import 'package:brawl_arena/ui/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, int winner, VoidCallback onRematch) =>
    tester.pumpWidget(
      MaterialApp(
        home: MatchResultOverlay(
          winner: winner,
          names: const ['Knight', 'Ranger'],
          onRematch: onRematch,
        ),
      ),
    );

void main() {
  testWidgets('player win', (tester) async {
    await _pump(tester, 0, () {});
    expect(find.text('Knight wins!'), findsOneWidget);
    expect(find.text('You win'), findsOneWidget);
  });

  testWidgets('player loss', (tester) async {
    await _pump(tester, 1, () {});
    expect(find.text('Ranger wins!'), findsOneWidget);
    expect(find.text('You lose'), findsOneWidget);
  });

  testWidgets('draw', (tester) async {
    await _pump(tester, -1, () {});
    expect(find.text('Draw'), findsOneWidget);
  });

  testWidgets('Rematch calls back', (tester) async {
    var rematches = 0;
    await _pump(tester, 0, () => rematches++);
    await tester.tap(find.byKey(const Key('rematch')));
    expect(rematches, 1);
  });
}
