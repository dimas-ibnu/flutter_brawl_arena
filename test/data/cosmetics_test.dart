import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:brawl_arena/data/cosmetics.dart';
import 'package:brawl_arena/game/brawl_game.dart';
import 'package:brawl_arena/ui/app.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cosmetics.dart';
import '../helpers/roster.dart';

Map<String, dynamic> _json() =>
    jsonDecode(File(cosmeticsAsset).readAsStringSync()) as Map<String, dynamic>;

CosmeticsCatalog _parse(Map<String, dynamic> json) =>
    parseCosmetics(jsonEncode(json), fighterIds: {'knight', 'ranger'});

void main() {
  group('catalog', () {
    test('every fighter has a default skin and more to pick from', () {
      for (final id in ['knight', 'ranger']) {
        final skins = testCatalog.skinsFor(id);
        expect(skins.length, greaterThanOrEqualTo(4), reason: id);
        expect(testCatalog.defaultSkinFor(id).isDefault, isTrue);
      }
    });

    test('the default skins keep the standard look', () {
      final classic = testCatalog.defaultSkinFor('knight');
      expect(classic.rim, isNull, reason: 'uses the slot color');
      expect(classic.body, isNull);
      expect(classic.accessories, isEmpty);
    });

    test('skin fields are read from the JSON', () {
      final neon = testCatalog.skin('knight', 'knight_neon');
      expect(neon.name, 'Neon Knight');
      expect(neon.rim, const Color(0xFFFF3DF5));
      expect(neon.weaponGlow, 10);
      expect(neon.trailLength, 8);
      expect(neon.sparkShape, SparkShape.star);
      expect(neon.unlock, Unlock.ad);
      expect(neon.accessories.single.type, AccessoryType.cape);
    });

    test('unknown or wrong-fighter ids fall back to the default', () {
      expect(testCatalog.skin('knight', 'nope').isDefault, isTrue);
      expect(testCatalog.skin('knight', 'ranger_jade').fighterId, 'knight');
      expect(testCatalog.palette('nope').id, 'sunset');
    });

    test('all four accessory types are used by some skin', () {
      final used = {
        for (final s in testCatalog.skins)
          for (final a in s.accessories) a.type,
      };
      expect(used, AccessoryType.values.toSet());
    });

    test('there are stage palettes with a default', () {
      expect(testCatalog.palettes.length, greaterThanOrEqualTo(3));
      expect(testCatalog.defaultPalette.id, 'sunset');
    });
  });

  group('validation', () {
    test('a bad color is reported with its skin', () {
      final json = _json();
      (json['skins'] as Map)['knight_neon']['rim'] = '#XYZ';
      expect(
        () => _parse(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('knight_neon'),
          ),
        ),
      );
    });

    test('a skin for a fighter that does not exist is rejected', () {
      final json = _json();
      (json['skins'] as Map)['knight_neon']['fighter'] = 'wizard';
      expect(() => _parse(json), throwsFormatException);
    });

    test('an unknown accessory is rejected', () {
      final json = _json();
      (json['skins'] as Map)['knight_neon']['accessories'] = [
        {'type': 'jetpack', 'color': '#FFFFFF'},
      ];
      expect(() => _parse(json), throwsFormatException);
    });

    test('a fighter with no skins is rejected', () {
      final json = _json();
      (json['skins'] as Map).removeWhere(
        (_, v) => (v as Map)['fighter'] == 'ranger',
      );
      expect(() => _parse(json), throwsFormatException);
    });

    test('colors parse as #RRGGBB and #AARRGGBB', () {
      expect(parseColor('#FF8800'), const Color(0xFFFF8800));
      expect(parseColor('#80FF8800'), const Color(0x80FF8800));
    });
  });

  group('store', () {
    test('equipped items are saved and read back', () async {
      final store = await testStore();
      expect(store.equippedSkin('knight').isDefault, isTrue);
      await store.equipSkin(testCatalog.skin('knight', 'knight_ember'));
      await store.equipPalette(testCatalog.palette('midnight'));
      expect(store.equippedSkin('knight').id, 'knight_ember');
      expect(store.equippedSkin('ranger').isDefault, isTrue);
      expect(store.equippedPalette.id, 'midnight');

      final reopened = await testStore({
        'cosmetics.skin.knight': 'knight_ember',
        'cosmetics.stagePalette': 'midnight',
      });
      expect(reopened.equippedSkin('knight').id, 'knight_ember');
      expect(reopened.equippedPalette.id, 'midnight');
    });

    test('a saved id that no longer exists falls back safely', () async {
      final store = await testStore({'cosmetics.skin.knight': 'deleted_skin'});
      expect(store.equippedSkin('knight').isDefault, isTrue);
    });

    test('equipping notifies listeners', () async {
      final store = await testStore();
      var changes = 0;
      store.addListener(() => changes++);
      await store.equipPalette(testCatalog.palette('toxic'));
      expect(changes, 1);
    });
  });

  test('the bot never wears the player skin in a mirror match', () {
    final rng = math.Random(1);
    final player = testCatalog.skin('ranger', 'ranger_jade');
    for (var i = 0; i < 50; i++) {
      final bot = BrawlApp.botSkin(
        testCatalog,
        'ranger',
        avoid: player,
        rng: rng,
      );
      expect(bot.id, isNot(player.id));
      expect(bot.fighterId, 'ranger');
    }
  });

  test('every skin and palette draws without errors', () {
    for (final palette in testCatalog.palettes) {
      for (final p in testCatalog.skinsFor('knight')) {
        for (final o in testCatalog.skinsFor('ranger')) {
          final game = BrawlGame(
            player: rosterEntry('knight'),
            opponent: rosterEntry('ranger'),
            seed: 1,
            playerSkin: p,
            opponentSkin: o,
            palette: palette,
          )..onGameResize(Vector2(874, 402));
          for (var t = 0; t < 90; t++) {
            game.update(1 / 60);
          }
          final recorder = PictureRecorder();
          game.render(Canvas(recorder));
          recorder.endRecording();
        }
      }
    }
  });
}
