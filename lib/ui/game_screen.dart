import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../data/cosmetics.dart';
import '../data/roster.dart';
import '../game/stage_art.dart';
import '../game/brawl_game.dart';
import '../game/sounds.dart';
import '../net/net_match.dart';
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
    this.localSlot = 0,
    this.online,
  });

  /// Online matches: which slot this device plays, and the connection.
  final int localSlot;
  final NetMatch? online;

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
    localSlot: widget.localSlot,
    online: widget.online,
  );

  bool get _online => widget.online != null;

  @override
  void dispose() {
    _game.leaveOnline();
    super.dispose();
  }

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
                    // Online matches can't restart; Quit leaves the match.
                    onRestart: _online ? null : () => _click(_game.restart),
                    onQuit: () => _click(_leave),
                    note: _online
                        ? 'Online matches keep running while this is open.'
                        : null,
                  )
                : const SizedBox.shrink(),
          ),
          ValueListenableBuilder<int?>(
            valueListenable: _game.result,
            builder: (context, winner, _) => winner == null
                ? const SizedBox.shrink()
                : MatchResultOverlay(
                    winner: winner,
                    localSlot: widget.localSlot,
                    names: [for (final e in _game.entries) e.name],
                    onRematch: _online ? null : () => _click(_game.restart),
                    onChangeFighter: () => _click(_leave),
                  ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _game.connectionProblem,
            builder: (context, problem, _) => problem == null
                ? const SizedBox.shrink()
                : ConnectionProblemOverlay(
                    message: problem,
                    onLeave: () => _click(_leave),
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
    this.note,
  });

  final ValueNotifier<bool> muted;
  final VoidCallback onResume;

  /// Null hides Restart (online).
  final VoidCallback? onRestart;
  final VoidCallback onQuit;
  final String? note;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      const Text(
        'Paused',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
      ),
      if (note != null) ...[
        const SizedBox(height: 4),
        Text(note!, style: const TextStyle(color: BrawlColors.muted)),
      ],
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
          if (onRestart != null) ...[
            OutlinedButton(
              key: const Key('restart'),
              onPressed: onRestart,
              child: const Text('Restart'),
            ),
            const SizedBox(width: 8),
          ],
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
    this.localSlot = 0,
  });

  /// Winner's slot, or -1 for a draw.
  final int winner;

  /// The slot this device plays (0 against the bot; 0 or 1 online).
  final int localSlot;

  /// Fighter names by slot.
  final List<String> names;

  /// Null hides Rematch (online).
  final VoidCallback? onRematch;
  final VoidCallback onChangeFighter;

  @override
  Widget build(BuildContext context) {
    final won = winner == localSlot;
    final title = winner < 0 ? 'Draw' : (won ? 'You win!' : 'You lose');
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
            color: won ? BrawlColors.accent : Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: BrawlColors.muted)),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRematch != null) ...[
              FilledButton(
                key: const Key('rematch'),
                onPressed: onRematch,
                child: const Text('Rematch'),
              ),
              const SizedBox(width: 12),
            ],
            OutlinedButton(
              key: const Key('change-fighter'),
              onPressed: onChangeFighter,
              child: Text(onRematch == null ? 'Leave' : 'Change fighter'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Online only: the match can't go on (opponent left, connection lost,
/// out of sync).
class ConnectionProblemOverlay extends StatelessWidget {
  const ConnectionProblemOverlay({
    super.key,
    required this.message,
    required this.onLeave,
  });

  final String message;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      const Icon(Icons.wifi_off, size: 40),
      const SizedBox(height: 8),
      Text(
        message,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('leave'),
        onPressed: onLeave,
        child: const Text('Leave'),
      ),
    ],
  );
}
