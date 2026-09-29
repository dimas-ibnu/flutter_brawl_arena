import 'dart:convert';

import '../sim/defs.dart';
import 'fighter_data.dart';

/// A fighter as the menus show it: the simulation data plus display text.
class RosterEntry {
  const RosterEntry({
    required this.id,
    required this.def,
    required this.weapon,
    required this.style,
  });

  final String id;
  final FighterDef def;
  final String weapon;
  final String style;

  String get name => def.name;
}

/// Every fighter in assets/data/fighters.json, in file order.
List<RosterEntry> parseRoster(String json) {
  final defs = parseFighters(json);
  final raw = jsonDecode(json) as Map<String, dynamic>;
  return [
    for (final MapEntry(:key, :value) in raw.entries)
      RosterEntry(
        id: key,
        def: defs[key]!,
        weapon: (value as Map<String, dynamic>)['weapon'] as String? ?? '',
        style: value['style'] as String? ?? '',
      ),
  ];
}
