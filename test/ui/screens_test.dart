import 'package:brawl_arena/data/roster.dart';
import 'package:brawl_arena/ui/fighter_select_screen.dart';
import 'package:brawl_arena/ui/title_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/roster.dart';

void _landscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('title screen: Play calls back', (tester) async {
    _landscape(tester);
    var played = 0;
    await tester.pumpWidget(
      MaterialApp(home: TitleScreen(onPlay: () => played++)),
    );
    expect(find.text('BRAWL ARENA'), findsOneWidget);
    await tester.tap(find.byKey(const Key('play')));
    expect(played, 1);
  });

  group('fighter select', () {
    Future<List<RosterEntry>> pump(WidgetTester tester) async {
      _landscape(tester);
      final fought = <RosterEntry>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FighterSelectScreen(roster: testRoster, onFight: fought.add),
        ),
      );
      return fought;
    }

    testWidgets('shows a card per fighter with its weapon', (tester) async {
      await pump(tester);
      for (final e in testRoster) {
        expect(find.byKey(Key('card-${e.id}')), findsOneWidget);
        expect(find.text('Weapon: ${e.weapon}'), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: 'layout fits');
    });

    testWidgets('Fight! is disabled until a fighter is picked', (tester) async {
      final fought = await pump(tester);
      await tester.tap(find.byKey(const Key('fight')));
      expect(fought, isEmpty);

      await tester.tap(find.byKey(const Key('card-ranger')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('fight')));
      expect(fought.single.id, 'ranger');
    });

    testWidgets('picking again switches the choice', (tester) async {
      final fought = await pump(tester);
      await tester.tap(find.byKey(const Key('card-ranger')));
      await tester.tap(find.byKey(const Key('card-knight')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('fight')));
      expect(fought.single.id, 'knight');
    });
  });
}
