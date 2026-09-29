import 'dart:io';

import 'package:brawl_arena/data/cosmetics.dart';
import 'package:brawl_arena/data/cosmetics_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'roster.dart';

final CosmeticsCatalog testCatalog = parseCosmetics(
  File(cosmeticsAsset).readAsStringSync(),
  fighterIds: {for (final e in testRoster) e.id},
);

/// A store backed by in-memory preferences.
Future<CosmeticsStore> testStore([Map<String, Object> saved = const {}]) async {
  SharedPreferences.setMockInitialValues(saved);
  return CosmeticsStore(testCatalog, await SharedPreferences.getInstance());
}
