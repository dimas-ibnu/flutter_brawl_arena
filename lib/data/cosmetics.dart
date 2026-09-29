import 'dart:convert';
import 'dart:ui';

/// Path of the cosmetics data inside the app bundle.
const cosmeticsAsset = 'assets/data/cosmetics.json';

/// How a cosmetic is obtained. Everything is unlocked in the MVP; rewarded
/// ads (PRD Phase 4) will gate the [ad] ones.
enum Unlock { free, ad }

/// Accessory shapes drawn in code (lib/game/fighter_art.dart).
enum AccessoryType { cape, horns, scarf, crown }

/// Spark shapes for hit effects.
enum SparkShape { dot, star, shard }

class Accessory {
  const Accessory(this.type, this.color, {this.size = 1});

  final AccessoryType type;
  final Color color;

  /// 1 = normal size.
  final double size;
}

/// A fighter skin. Purely visual: it never reaches the simulation, so skins
/// can't change match stats, and online players always stay in sync.
/// Null fields fall back to the defaults (slot rim color, black body...).
class Skin {
  const Skin({
    required this.id,
    required this.name,
    required this.fighterId,
    this.isDefault = false,
    this.unlock = Unlock.free,
    this.rim,
    this.body,
    this.weaponColor,
    this.weaponGlow = 0,
    this.weaponLength = 1,
    this.trailColor,
    this.trailLength = 0,
    this.sparkColor,
    this.sparkShape = SparkShape.dot,
    this.koColor,
    this.accessories = const [],
  });

  final String id;
  final String name;
  final String fighterId;
  final bool isDefault;
  final Unlock unlock;

  /// Rim light; null = the slot color (blue for you, orange for the bot).
  final Color? rim;

  /// Silhouette color; null = the standard near-black.
  final Color? body;

  /// Weapon color (null = body color), glow radius and length multiplier.
  final Color? weaponColor;
  final double weaponGlow;
  final double weaponLength;

  /// Streak behind the weapon during attacks; length in frames (0 = none).
  final Color? trailColor;
  final int trailLength;

  final Color? sparkColor;
  final SparkShape sparkShape;
  final Color? koColor;
  final List<Accessory> accessories;
}

/// Colors for the Flat Arena backdrop and platform.
class StagePalette {
  const StagePalette({
    required this.id,
    required this.name,
    required this.sky,
    required this.sun,
    required this.mountains,
    required this.mist,
    required this.platformTop,
    required this.platformEdge,
    required this.platformUnder,
    this.isDefault = false,
    this.unlock = Unlock.free,
  });

  final String id;
  final String name;
  final bool isDefault;
  final Unlock unlock;

  /// Four colors, top of the sky to the horizon.
  final List<Color> sky;
  final Color sun;

  /// Three ranges, far to near.
  final List<Color> mountains;
  final Color mist;
  final Color platformTop;
  final Color platformEdge;

  /// Two colors, top to bottom of the rock under the platform.
  final List<Color> platformUnder;
}

class CosmeticsCatalog {
  CosmeticsCatalog({required this.skins, required this.palettes});

  final List<Skin> skins;
  final List<StagePalette> palettes;

  List<Skin> skinsFor(String fighterId) => [
    for (final s in skins)
      if (s.fighterId == fighterId) s,
  ];

  Skin defaultSkinFor(String fighterId) {
    final options = skinsFor(fighterId);
    return options.firstWhere((s) => s.isDefault, orElse: () => options.first);
  }

  /// The skin with [id] for [fighterId], or that fighter's default when the
  /// id is unknown or belongs to another fighter.
  Skin skin(String fighterId, String? id) {
    for (final s in skinsFor(fighterId)) {
      if (s.id == id) return s;
    }
    return defaultSkinFor(fighterId);
  }

  StagePalette get defaultPalette =>
      palettes.firstWhere((p) => p.isDefault, orElse: () => palettes.first);

  StagePalette palette(String? id) =>
      palettes.firstWhere((p) => p.id == id, orElse: () => defaultPalette);
}

/// Parses assets/data/cosmetics.json. [fighterIds] are the fighters that
/// exist; every one of them must have at least one skin.
CosmeticsCatalog parseCosmetics(
  String json, {
  required Set<String> fighterIds,
}) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final skins = [
    for (final MapEntry(:key, :value)
        in (root['skins'] as Map<String, dynamic>).entries)
      _skin(key, value as Map<String, dynamic>, fighterIds),
  ];
  for (final id in fighterIds) {
    if (!skins.any((s) => s.fighterId == id)) {
      throw FormatException('Fighter "$id" has no skin');
    }
  }
  final palettes = [
    for (final MapEntry(:key, :value)
        in (root['stagePalettes'] as Map<String, dynamic>).entries)
      _palette(key, value as Map<String, dynamic>),
  ];
  if (palettes.isEmpty) throw const FormatException('No stage palettes');
  return CosmeticsCatalog(skins: skins, palettes: palettes);
}

Skin _skin(String id, Map<String, dynamic> j, Set<String> fighterIds) {
  final fighter = j['fighter'] as String;
  if (!fighterIds.contains(fighter)) {
    throw FormatException('Skin "$id" is for unknown fighter "$fighter"');
  }
  final weapon = j['weapon'] as Map<String, dynamic>?;
  final trail = j['trail'] as Map<String, dynamic>?;
  final sparks = j['sparks'] as Map<String, dynamic>?;
  return Skin(
    id: id,
    name: j['name'] as String,
    fighterId: fighter,
    isDefault: j['default'] as bool? ?? false,
    unlock: _unlock(j['unlock']),
    rim: _colorOrNull(j['rim'], id),
    body: _colorOrNull(j['body'], id),
    weaponColor: _colorOrNull(weapon?['color'], id),
    weaponGlow: (weapon?['glow'] as num?)?.toDouble() ?? 0,
    weaponLength: (weapon?['length'] as num?)?.toDouble() ?? 1,
    trailColor: _colorOrNull(trail?['color'], id),
    trailLength: (trail?['length'] as num?)?.toInt() ?? 0,
    sparkColor: _colorOrNull(sparks?['color'], id),
    sparkShape: _byName(SparkShape.values, sparks?['shape'], SparkShape.dot),
    koColor: _colorOrNull(j['ko'], id),
    accessories: [
      for (final a in (j['accessories'] as List<dynamic>? ?? []))
        _accessory(a as Map<String, dynamic>, id),
    ],
  );
}

Accessory _accessory(Map<String, dynamic> a, String skinId) {
  final type = AccessoryType.values.where((t) => t.name == a['type']);
  if (type.isEmpty) {
    throw FormatException(
      'Skin "$skinId" has unknown accessory "${a['type']}"',
    );
  }
  return Accessory(
    type.first,
    parseColor(a['color'] as String, skinId),
    size: (a['size'] as num?)?.toDouble() ?? 1,
  );
}

StagePalette _palette(String id, Map<String, dynamic> j) {
  List<Color> colors(String key, int count) {
    final list = [for (final c in j[key] as List) parseColor(c as String, id)];
    if (list.length != count) {
      throw FormatException('Palette "$id": "$key" needs $count colors');
    }
    return list;
  }

  return StagePalette(
    id: id,
    name: j['name'] as String,
    isDefault: j['default'] as bool? ?? false,
    unlock: _unlock(j['unlock']),
    sky: colors('sky', 4),
    sun: parseColor(j['sun'] as String, id),
    mountains: colors('mountains', 3),
    mist: parseColor(j['mist'] as String, id),
    platformTop: parseColor(j['platformTop'] as String, id),
    platformEdge: parseColor(j['platformEdge'] as String, id),
    platformUnder: colors('platformUnder', 2),
  );
}

Unlock _unlock(Object? v) => _byName(Unlock.values, v, Unlock.free);

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

Color? _colorOrNull(Object? v, String owner) =>
    v == null ? null : parseColor(v as String, owner);

/// "#RRGGBB" or "#AARRGGBB".
Color parseColor(String hex, [String owner = '']) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(h, radix: 16);
  if (value == null || (h.length != 6 && h.length != 8)) {
    throw FormatException('Bad color "$hex" in "$owner"');
  }
  return Color(h.length == 6 ? 0xFF000000 | value : value);
}
