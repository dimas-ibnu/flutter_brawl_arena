import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fighter_data.dart';
import '../game/brawl_game.dart';
import 'touch_controls.dart';

/// The match: the Flame game with the touch controls layered on top.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.showTouchControls});

  final bool showTouchControls;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<BrawlGame> _game = _load();

  static Future<BrawlGame> _load() async {
    final fighters = parseFighters(await rootBundle.loadString(fightersAsset));
    return BrawlGame(fighters: [fighters['knight']!, fighters['ranger']!]);
  }

  @override
  Widget build(BuildContext context) {
    // Material gives the button labels a proper text style.
    return Material(
      color: const Color(0xFF14161C),
      child: FutureBuilder<BrawlGame>(
        future: _game,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load fighters: ${snapshot.error}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }
          final game = snapshot.data;
          if (game == null) return const SizedBox.shrink();
          return Stack(
            children: [
              GameWidget(game: game),
              if (widget.showTouchControls)
                TouchControls(input: game.touchInput),
              ValueListenableBuilder<int?>(
                valueListenable: game.result,
                builder: (context, winner, _) => winner == null
                    ? const SizedBox.shrink()
                    : MatchResultOverlay(
                        winner: winner,
                        names: game.fighterNames,
                        onRematch: game.restart,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Placeholder result panel until the real results screen (PRD step 11).
/// Slot 0 is the player.
class MatchResultOverlay extends StatelessWidget {
  const MatchResultOverlay({
    super.key,
    required this.winner,
    required this.names,
    required this.onRematch,
  });

  /// Winner's slot, or -1 for a draw.
  final int winner;
  final List<String> names;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    final title = winner < 0 ? 'Draw' : '${names[winner]} wins!';
    final subtitle = winner < 0
        ? 'Same stocks and damage'
        : (winner == 0 ? 'You win' : 'You lose');
    return ColoredBox(
      color: const Color(0xAA000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('rematch'),
              onPressed: onRematch,
              child: const Text('Rematch'),
            ),
          ],
        ),
      ),
    );
  }
}
