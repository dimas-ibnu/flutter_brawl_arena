import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../data/cosmetics.dart';
import '../data/roster.dart';
import '../game/stage_art.dart';
import '../game/brawl_game.dart';
import '../game/sounds.dart';
import 'theme.dart';
import 'touch_controls.dart';

/// The match: the Flame game, touch controls, a pause button, and the pause
/// and results panels on top.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.player,
    required this.opponent,
    required this.seed,
    required this.sounds,
    required this.showTouchControls,
    this.playerSkin,
    this.opponentSkin,
    this.palette = sunsetPalette,
  });

  final Skin? playerSkin;
  final Skin? opponentSkin;
  final StagePalette palette;

  final RosterEntry player;
  final RosterEntry opponent;
  final int seed;
  final GameSounds sounds;
  final bool showTouchControls;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final BrawlGame _game = BrawlGame(
    player: widget.player,
    opponent: widget.opponent,
    seed: widget.seed,
    playerSkin: widget.playerSkin,
    opponentSkin: widget.opponentSkin,
    palette: widget.palette,
    sounds: widget.sounds,
    showKeyboardHints: !widget.showTouchControls,
  );

  void _click(VoidCallback then) {
    widget.sounds.play(Sfx.uiClick);
    then();
  }

  void _leave() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrawlColors.background,
      child: Stack(
        children: [
          GameWidget(game: _game),
          if (widget.showTouchControls) TouchControls(input: _game.touchInput),
          Positioned(
            top: 44,
            left: 0,
            right: 0,
            child: Center(
              child: IconButton(
                key: const Key('pause'),
                tooltip: 'Pause',
                onPressed: () => _click(() => _game.setPaused(true)),
                icon: const Icon(Icons.pause_circle, size: 34),
                color: Colors.white70,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _game.pauseMenuOpen,
            builder: (context, paused, _) => paused
                ? PauseOverlay(
                    muted: widget.sounds.muted,
                    onResume: () => _click(() => _game.setPaused(false)),
                    onRestart: () => _click(_game.restart),
                    onQuit: () => _click(_leave),
                  )
                : const SizedBox.shrink(),
          ),
          ValueListenableBuilder<int?>(
            valueListenable: _game.result,
            builder: (context, winner, _) => winner == null
                ? const SizedBox.shrink()
                : MatchResultOverlay(
                    winner: winner,
                    names: [widget.player.name, widget.opponent.name],
                    onRematch: () => _click(_game.restart),
                    onChangeFighter: () => _click(_leave),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xB3000000),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        decoration: BoxDecoration(
          color: BrawlColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}

/// PRD pause menu: resume, restart, quit. Also a mute switch.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.muted,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  final ValueNotifier<bool> muted;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      const Text(
        'Paused',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('resume'),
        onPressed: onResume,
        child: const Text('Resume'),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('restart'),
            onPressed: onRestart,
            child: const Text('Restart'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('quit'),
            onPressed: onQuit,
            child: const Text('Quit'),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: muted,
            builder: (context, isMuted, _) => IconButton(
              key: const Key('mute'),
              tooltip: isMuted ? 'Sound on' : 'Sound off',
              onPressed: () => muted.value = !isMuted,
              icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Results: who won, then Rematch or back to fighter select. Slot 0 is the
/// player.
class MatchResultOverlay extends StatelessWidget {
  const MatchResultOverlay({
    super.key,
    required this.winner,
    required this.names,
    required this.onRematch,
    required this.onChangeFighter,
  });

  /// Winner's slot, or -1 for a draw.
  final int winner;
  final List<String> names;
  final VoidCallback onRematch;
  final VoidCallback onChangeFighter;

  @override
  Widget build(BuildContext context) {
    final title = winner < 0 ? 'Draw' : (winner == 0 ? 'You win!' : 'You lose');
    final subtitle = winner < 0
        ? 'Same stocks and damage'
        : '${names[winner]} wins the match';
    return _Panel(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: winner == 0 ? BrawlColors.accent : Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: BrawlColors.muted)),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('rematch'),
              onPressed: onRematch,
              child: const Text('Rematch'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: const Key('change-fighter'),
              onPressed: onChangeFighter,
              child: const Text('Change fighter'),
            ),
          ],
        ),
      ],
    );
  }
}
