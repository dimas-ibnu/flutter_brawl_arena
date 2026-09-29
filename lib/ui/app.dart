import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fighter_data.dart';
import '../data/roster.dart';
import '../game/sounds.dart';
import 'fighter_select_screen.dart';
import 'game_screen.dart';
import 'theme.dart';
import 'title_screen.dart';

/// MVP flow from the PRD: Title → Fighter select → Match → Results
/// (rematch, or back to fighter select).
class BrawlApp extends StatelessWidget {
  const BrawlApp({
    super.key,
    required this.roster,
    required this.sounds,
    required this.showTouchControls,
  });

  final List<RosterEntry> roster;
  final GameSounds sounds;
  final bool showTouchControls;

  /// Loads the fighter data (and sounds) before the app starts.
  static Future<List<RosterEntry>> loadRoster() async =>
      parseRoster(await rootBundle.loadString(fightersAsset));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brawl Arena',
      debugShowCheckedModeBanner: false,
      theme: brawlTheme(),
      home: Builder(
        builder: (context) => TitleScreen(
          onPlay: () {
            sounds.play(Sfx.uiClick);
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => _select(context)));
          },
        ),
      ),
    );
  }

  Widget _select(BuildContext context) => Builder(
    builder: (context) => FighterSelectScreen(
      roster: roster,
      onTap: () => sounds.play(Sfx.uiClick),
      onFight: (player) {
        sounds.play(Sfx.uiClick);
        final rng = math.Random();
        final opponent = roster[rng.nextInt(roster.length)];
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GameScreen(
              player: player,
              opponent: opponent,
              seed: rng.nextInt(1 << 31) + 1,
              sounds: sounds,
              showTouchControls: showTouchControls,
            ),
          ),
        );
      },
    ),
  );
}
