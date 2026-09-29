import 'dart:io';

import 'package:brawl_arena/data/fighter_data.dart';
import 'package:brawl_arena/sim/defs.dart';

/// The real fighter data from assets/data/fighters.json, so tests check the
/// numbers the game ships with.
final Map<String, FighterDef> testFighters = parseFighters(
  File(fightersAsset).readAsStringSync(),
);
final FighterDef knightDef = testFighters['knight']!;
final FighterDef rangerDef = testFighters['ranger']!;
