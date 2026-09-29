import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cosmetics.dart';
import '../data/cosmetics_store.dart';
import '../data/fighter_data.dart';
import '../data/roster.dart';
import '../game/sounds.dart';
import 'fighter_select_screen.dart';
import 'game_screen.dart';
import 'locker_screen.dart';
import 'theme.dart';
import 'title_screen.dart';

/// MVP flow from the PRD: Title → Fighter select → Match → Results
/// (rematch, or back to fighter select). The Locker (cosmetics) hangs off
/// the title screen.
class BrawlApp extends StatelessWidget {
  const BrawlApp({
    super.key,
    required this.roster,
    required this.cosmetics,
    required this.sounds,
    required this.showTouchControls,
  });

  final List<RosterEntry> roster;
  final CosmeticsStore cosmetics;
  final GameSounds sounds;
  final bool showTouchControls;

  static Future<List<RosterEntry>> loadRoster() async =>
      parseRoster(await rootBundle.loadString(fightersAsset));

  static Future<CosmeticsStore> loadCosmetics(List<RosterEntry> roster) async {
    final catalog = parseCosmetics(
      await rootBundle.loadString(cosmeticsAsset),
      fighterIds: {for (final e in roster) e.id},
    );
    return CosmeticsStore.open(catalog);
  }

  void _click() => sounds.play(Sfx.uiClick);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brawl Arena',
      debugShowCheckedModeBanner: false,
      theme: brawlTheme(),
      home: Builder(
        builder: (context) => TitleScreen(
          onPlay: () {
            _click();
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => _select()));
          },
          onLocker: () {
            _click();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LockerScreen(
                  roster: roster,
                  store: cosmetics,
                  onTap: _click,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _select() => Builder(
    builder: (context) => ListenableBuilder(
      listenable: cosmetics,
      builder: (context, _) => FighterSelectScreen(
        roster: roster,
        onTap: _click,
        skinFor: cosmetics.equippedSkin,
        onFight: (player) {
          _click();
          final rng = math.Random();
          final opponent = roster[rng.nextInt(roster.length)];
          final playerSkin = cosmetics.equippedSkin(player.id);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GameScreen(
                player: player,
                opponent: opponent,
                seed: rng.nextInt(1 << 31) + 1,
                sounds: sounds,
                showTouchControls: showTouchControls,
                playerSkin: playerSkin,
                opponentSkin: botSkin(
                  cosmetics.catalog,
                  opponent.id,
                  avoid: playerSkin,
                  rng: rng,
                ),
                palette: cosmetics.equippedPalette,
              ),
            ),
          );
        },
      ),
    ),
  );

  /// The bot wears a random skin, never the same one as the player in a
  /// mirror match, so the two fighters look different.
  static Skin botSkin(
    CosmeticsCatalog catalog,
    String fighterId, {
    required Skin avoid,
    required math.Random rng,
  }) {
    final options = [
      for (final s in catalog.skinsFor(fighterId))
        if (s.id != avoid.id) s,
    ];
    if (options.isEmpty) return catalog.defaultSkinFor(fighterId);
    return options[rng.nextInt(options.length)];
  }
}
