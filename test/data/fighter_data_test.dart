import 'dart:convert';
import 'dart:io';

import 'package:brawl_arena/data/fighter_data.dart';
import 'package:brawl_arena/sim/defs.dart';
import 'package:brawl_arena/sim/fixed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fighters.dart';
import '../helpers/roster.dart';

void main() {
  test('both MVP fighters load with every move', () {
    expect(testFighters.keys, containsAll(['knight', 'ranger']));
    for (final def in testFighters.values) {
      expect(def.moves.keys.toSet(), MoveKind.values.toSet(), reason: def.name);
    }
    expect(knightDef.name, 'Knight');
    expect(rangerDef.name, 'Ranger');
  });

  test('decimals become the matching fixed-point values', () {
    expect(knightDef.gravity, Fx.fromDouble(0.6));
    expect(knightDef.airAccel, Fx.fromDouble(0.4));
    expect(knightDef.move(MoveKind.neutralLight).launchY, Fx.fromDouble(-0.6));
  });

  test('optional fields default sensibly', () {
    final jab = knightDef.move(MoveKind.neutralLight);
    expect(jab.selfVx, Fx.zero);
    expect(jab.launchAway, isFalse);
    expect(jab.endsOnLanding, isFalse);
    expect(knightDef.move(MoveKind.neutralAir).endsOnLanding, isTrue);
  });

  test('every move has sane numbers', () {
    for (final def in testFighters.values) {
      def.moves.forEach((kind, m) {
        final where = '${def.name} ${kind.name}';
        expect(m.startup, greaterThan(0), reason: where);
        expect(m.active, greaterThan(0), reason: where);
        expect(m.recovery, greaterThanOrEqualTo(0), reason: where);
        expect(m.damage, greaterThan(0), reason: where);
        expect(m.width > Fx.zero && m.height > Fx.zero, isTrue, reason: where);
      });
    }
  });

  test('a missing move is reported by name', () {
    final json =
        jsonDecode(File(fightersAsset).readAsStringSync())
            as Map<String, dynamic>;
    ((json['knight'] as Map<String, dynamic>)['moves'] as Map).remove(
      'groundPound',
    );
    expect(
      () => parseFighters(jsonEncode(json)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('groundPound'),
        ),
      ),
    );
  });

  test('the roster lists fighters in file order with display text', () {
    expect([for (final e in testRoster) e.id], ['knight', 'ranger']);
    expect(rosterEntry('knight').weapon, 'Sword');
    expect(rosterEntry('ranger').weapon, 'Spear');
    expect(rosterEntry('ranger').style, isNotEmpty);
    expect(rosterEntry('knight').def.name, 'Knight');
  });
}
