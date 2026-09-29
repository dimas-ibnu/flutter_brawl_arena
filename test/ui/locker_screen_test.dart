import 'package:brawl_arena/ui/locker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cosmetics.dart';
import '../helpers/roster.dart';

void main() {
  Future<void> pump(WidgetTester tester, store) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LockerScreen(roster: testRoster, store: store),
      ),
    );
  }

  testWidgets('shows the first fighter skins and the stage palettes', (
    tester,
  ) async {
    final store = await testStore();
    await pump(tester, store);
    for (final s in testCatalog.skinsFor('knight')) {
      expect(find.byKey(Key('skin-${s.id}')), findsOneWidget);
    }
    for (final p in testCatalog.palettes) {
      expect(find.byKey(Key('palette-${p.id}')), findsOneWidget);
    }
    expect(tester.takeException(), isNull, reason: 'layout fits');
  });

  testWidgets('tapping a skin equips and saves it', (tester) async {
    final store = await testStore();
    await pump(tester, store);
    await tester.tap(find.byKey(const Key('skin-knight_ember')));
    await tester.pump();
    expect(store.equippedSkin('knight').id, 'knight_ember');
  });

  testWidgets('switching fighter shows that fighter skins', (tester) async {
    final store = await testStore();
    await pump(tester, store);
    await tester.tap(find.text('Ranger'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skin-ranger_jade')), findsOneWidget);
    expect(find.byKey(const Key('skin-knight_neon')), findsNothing);

    await tester.tap(find.byKey(const Key('skin-ranger_shadow')));
    await tester.pump();
    expect(store.equippedSkin('ranger').id, 'ranger_shadow');
    expect(store.equippedSkin('knight').isDefault, isTrue);
  });

  testWidgets('tapping a palette equips it', (tester) async {
    final store = await testStore();
    await pump(tester, store);
    await tester.ensureVisible(find.byKey(const Key('palette-toxic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('palette-toxic')));
    await tester.pump();
    expect(store.equippedPalette.id, 'toxic');
  });
}
