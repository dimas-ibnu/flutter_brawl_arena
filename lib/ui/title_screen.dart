import 'package:flutter/material.dart';

import '../game/stage_art.dart';
import 'theme.dart';

class TitleScreen extends StatelessWidget {
  const TitleScreen({
    super.key,
    required this.onPlay,
    this.onLocker,
    this.onOnline,
  });

  final VoidCallback onPlay;
  final VoidCallback? onLocker;
  final VoidCallback? onOnline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _BackdropPainter()),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BRAWL ARENA',
                    style: TextStyle(
                      color: BrawlColors.text,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      shadows: [Shadow(blurRadius: 16, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Knock them off the stage',
                    style: TextStyle(color: BrawlColors.muted, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const Key('play'),
                    onPressed: onPlay,
                    child: const Text('Play vs Bot'),
                  ),
                  if (onOnline != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      key: const Key('online'),
                      onPressed: onOnline,
                      icon: const Icon(Icons.public),
                      label: const Text('Play Online'),
                    ),
                  ],
                  if (onLocker != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('locker'),
                      onPressed: onLocker,
                      icon: const Icon(Icons.checkroom),
                      label: const Text('Locker'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final _backdrop = StageBackdrop();

  @override
  void paint(Canvas canvas, Size size) => _backdrop.paint(canvas, size);

  @override
  bool shouldRepaint(_BackdropPainter old) => false;
}
