import 'dart:io';

import 'package:brawl_arena/data/fighter_data.dart';
import 'package:brawl_arena/data/roster.dart';

final List<RosterEntry> testRoster = parseRoster(
  File(fightersAsset).readAsStringSync(),
);
RosterEntry rosterEntry(String id) => testRoster.firstWhere((e) => e.id == id);
