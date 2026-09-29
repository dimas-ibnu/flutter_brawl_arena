import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cosmetics.dart';
import '../data/cosmetics_store.dart';
import '../data/fighter_data.dart';
import '../data/roster.dart';
import '../game/sounds.dart';
import '../net/online_service.dart';
import 'fighter_select_screen.dart';
import 'game_screen.dart';
import 'locker_screen.dart';
import 'online_lobby_screen.dart';
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
    this.online,
  });

  /// Null when Firebase isn't configured: Play Online explains the setup.
  final OnlineService? online;

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
          onOnline: () {
            _click();
            final service = online;
            if (service == null) {
              showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('Online play is not set up'),
                  content: Text(
                    'This build has no Firebase project yet. Follow '
                    'README_ONLINE.md (flutterfire configure), then rebuild.',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _select(
                  onPicked: (context, player) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OnlineLobbyScreen(
                          service: service,
                          player: player,
                          roster: roster,
                          cosmetics: cosmetics,
                          sounds: sounds,
                          showTouchControls: showTouchControls,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
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

  /// Fighter select. [onPicked] replaces the default (a match vs the bot).
  Widget _select({
    void Function(BuildContext context, RosterEntry player)? onPicked,
  }) => Builder(
    builder: (context) => ListenableBuilder(
      listenable: cosmetics,
      builder: (context, _) => FighterSelectScreen(
        roster: roster,
        onTap: _click,
        skinFor: cosmetics.equippedSkin,
        opponentLabel: onPicked == null
            ? 'Opponent: random bot (Normal)'
            : 'Opponent: another player online',
        onFight: (player) {
          _click();
          if (onPicked != null) {
            onPicked(context, player);
            return;
          }
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
