import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cosmetics.dart';

/// Which skin each fighter wears and which stage palette is on, saved on
/// the device. Accounts and ad unlocks (PRD Phase 4) will move this to
/// Firebase; the rest of the game only talks to this class.
class CosmeticsStore extends ChangeNotifier {
  CosmeticsStore(this.catalog, this._prefs);

  final CosmeticsCatalog catalog;
  final SharedPreferences _prefs;

  static Future<CosmeticsStore> open(CosmeticsCatalog catalog) async =>
      CosmeticsStore(catalog, await SharedPreferences.getInstance());

  static String _skinKey(String fighterId) => 'cosmetics.skin.$fighterId';
  static const _paletteKey = 'cosmetics.stagePalette';

  /// Everything is unlocked in the MVP. Rewarded ads will unlock
  /// [Unlock.ad] items here.
  bool owns(Unlock unlock) => true;

  Skin equippedSkin(String fighterId) =>
      catalog.skin(fighterId, _prefs.getString(_skinKey(fighterId)));

  StagePalette get equippedPalette =>
      catalog.palette(_prefs.getString(_paletteKey));

  Future<void> equipSkin(Skin skin) async {
    await _prefs.setString(_skinKey(skin.fighterId), skin.id);
    notifyListeners();
  }

  Future<void> equipPalette(StagePalette palette) async {
    await _prefs.setString(_paletteKey, palette.id);
    notifyListeners();
  }
}
