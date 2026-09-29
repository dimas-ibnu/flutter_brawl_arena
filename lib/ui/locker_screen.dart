import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cosmetics.dart';
import '../data/cosmetics_store.dart';
import '../data/roster.dart';
import '../game/fighter_art.dart';
import '../game/stage_art.dart';
import 'theme.dart';

/// Pick skins for each fighter and the stage palette. Choices are saved at
/// once. Every item is unlocked in the MVP; rewarded ads come later.
class LockerScreen extends StatefulWidget {
  const LockerScreen({
    super.key,
    required this.roster,
    required this.store,
    this.onTap,
  });

  final List<RosterEntry> roster;
  final CosmeticsStore store;
  final VoidCallback? onTap;

  @override
  State<LockerScreen> createState() => _LockerScreenState();
}

class _LockerScreenState extends State<LockerScreen> {
  late RosterEntry _fighter = widget.roster.first;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final skin = store.equippedSkin(_fighter.id);
            final palette = store.equippedPalette;
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        key: const Key('locker-preview'),
                        painter: _LockerPreview(_fighter, skin, palette),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const Text(
                            'Locker',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SegmentedButton<String>(
                        segments: [
                          for (final e in widget.roster)
                            ButtonSegment(value: e.id, label: Text(e.name)),
                        ],
                        selected: {_fighter.id},
                        onSelectionChanged: (ids) {
                          widget.onTap?.call();
                          setState(
                            () => _fighter = widget.roster.firstWhere(
                              (e) => e.id == ids.first,
                            ),
                          );
                        },
                      ),
                      const _Heading('Skin'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in store.catalog.skinsFor(_fighter.id))
                            ChoiceChip(
                              key: Key('skin-${s.id}'),
                              avatar: _Swatch([
                                s.rim ?? BrawlColors.player,
                                s.weaponColor ?? s.rim ?? BrawlColors.player,
                              ]),
                              label: Text(s.name),
                              selected: s.id == skin.id,
                              onSelected: (_) {
                                widget.onTap?.call();
                                store.equipSkin(s);
                              },
                            ),
                        ],
                      ),
                      const _Heading('Stage'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in store.catalog.palettes)
                            ChoiceChip(
                              key: Key('palette-${p.id}'),
                              avatar: _Swatch(p.sky.sublist(1)),
                              label: Text(p.name),
                              selected: p.id == palette.id,
                              onSelected: (_) {
                                widget.onTap?.call();
                                store.equipPalette(p);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cosmetics only change how things look, never how a '
                        'fighter plays.',
                        style: TextStyle(color: BrawlColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.colors);

  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [...colors, colors.last]),
    ),
  );
}

/// The fighter in its skin, standing on a slice of the chosen stage.
class _LockerPreview extends CustomPainter {
  _LockerPreview(this.entry, this.skin, this.palette)
    : _backdrop = StageBackdrop(palette);

  final RosterEntry entry;
  final Skin skin;
  final StagePalette palette;
  final StageBackdrop _backdrop;

  @override
  void paint(Canvas canvas, Size size) {
    _backdrop.paint(canvas, size);
    final w = entry.def.width.toDouble();
    final h = entry.def.height.toDouble();
    final scale = math.min(size.height * 0.55 / h, size.width / (w * 4));
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.78);
    canvas.scale(scale);
    paintPlatform(canvas, -w * 3, w * 3, 0, palette);
    paintFighter(
      canvas,
      feet: Offset.zero,
      width: w,
      height: h,
      rim: BrawlColors.player,
      weapon: weaponArtFor(entry.id),
      skin: skin,
      pose: const FighterPose(speedX: -3),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LockerPreview old) =>
      old.skin.id != skin.id ||
      old.palette.id != palette.id ||
      old.entry.id != entry.id;
}
