import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cosmetics.dart';
import '../data/roster.dart';
import '../game/fighter_art.dart';
import 'theme.dart';

/// PRD fighter select: a card per fighter with its outline, weight, speed
/// and weapon. Tap to pick, then Fight! The bot picks its fighter at random.
class FighterSelectScreen extends StatefulWidget {
  const FighterSelectScreen({
    super.key,
    required this.roster,
    required this.onFight,
    this.onTap,
    this.skinFor,
    this.opponentLabel = 'Opponent: random bot (Normal)',
  });

  final String opponentLabel;

  /// The equipped skin to preview on each card (null = default look).
  final Skin Function(String fighterId)? skinFor;

  final List<RosterEntry> roster;
  final ValueChanged<RosterEntry> onFight;

  /// Called on every card tap (for the click sound).
  final VoidCallback? onTap;

  @override
  State<FighterSelectScreen> createState() => _FighterSelectScreenState();
}

class _FighterSelectScreenState extends State<FighterSelectScreen> {
  RosterEntry? _picked;

  @override
  Widget build(BuildContext context) {
    final maxWeight = widget.roster
        .map((e) => e.def.weight)
        .reduce((a, b) => a > b ? a : b);
    final maxSpeed = widget.roster
        .map((e) => e.def.walkSpeed.toDouble())
        .reduce((a, b) => a > b ? a : b);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Choose your fighter',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    for (final entry in widget.roster)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _FighterCard(
                            entry: entry,
                            skin: widget.skinFor?.call(entry.id),
                            picked: _picked?.id == entry.id,
                            weightFraction: entry.def.weight / maxWeight,
                            speedFraction:
                                entry.def.walkSpeed.toDouble() / maxSpeed,
                            onTap: () {
                              widget.onTap?.call();
                              setState(() => _picked = entry);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.opponentLabel,
                    style: const TextStyle(color: BrawlColors.muted),
                  ),
                  const SizedBox(width: 20),
                  FilledButton(
                    key: const Key('fight'),
                    onPressed: _picked == null
                        ? null
                        : () => widget.onFight(_picked!),
                    child: const Text('Fight!'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FighterCard extends StatelessWidget {
  const _FighterCard({
    required this.entry,
    required this.skin,
    required this.picked,
    required this.weightFraction,
    required this.speedFraction,
    required this.onTap,
  });

  final RosterEntry entry;
  final Skin? skin;
  final bool picked;
  final double weightFraction;
  final double speedFraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('card-${entry.id}'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: BrawlColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: picked ? BrawlColors.accent : Colors.white12,
            width: picked ? 3 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _PreviewPainter(entry, skin, picked),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // Scales down on short landscape phone screens.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.style,
                        style: const TextStyle(color: BrawlColors.muted),
                      ),
                      const SizedBox(height: 10),
                      _Stat('Weight', weightFraction),
                      _Stat('Speed', speedFraction),
                      const SizedBox(height: 6),
                      Text('Weapon: ${entry.weapon}'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.fraction);

  final String label;
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: Colors.white12,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.entry, this.skin, this.picked);

  final RosterEntry entry;
  final Skin? skin;
  final bool picked;

  @override
  void paint(Canvas canvas, Size size) {
    final w = entry.def.width.toDouble();
    final h = entry.def.height.toDouble();
    // Fit the body and its weapon (about 4 body-widths across) in the box.
    final scale = math.min(size.height * 0.8 / h, size.width / (w * 3.4));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width * 0.4, size.height * 0.88);
    canvas.scale(scale);
    paintFighter(
      canvas,
      feet: Offset.zero,
      width: w,
      height: h,
      rim: picked ? BrawlColors.accent : BrawlColors.player,
      weapon: weaponArtFor(entry.id),
      skin: skin,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.picked != picked || old.skin?.id != skin?.id;
}
