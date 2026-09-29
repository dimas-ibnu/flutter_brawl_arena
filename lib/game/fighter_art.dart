import 'dart:math' as math;
import 'dart:ui';

import '../data/cosmetics.dart';

/// Pose details that change how a fighter is drawn. Purely visual.
class FighterPose {
  const FighterPose({
    this.facing = 1,
    this.runPhase = 0,
    this.airborne = false,
    this.reach,
    this.windUp = false,
    this.stunned = false,
    this.speedX = 0,
  });

  /// 1 = facing right, -1 = facing left.
  final int facing;

  /// Leg swing while running, in radians (0 = standing).
  final double runPhase;
  final bool airborne;

  /// Where the weapon points while an attack is out, relative to the feet.
  /// Null = weapon held at rest.
  final Offset? reach;

  /// Weapon pulled back during an attack's wind-up.
  final bool windUp;

  /// Leaning back from a hit.
  final bool stunned;

  /// Horizontal speed, so capes and scarves trail behind.
  final double speedX;
}

/// PRD art style: a solid dark silhouette with a colored rim light, so two
/// fighters stay easy to tell apart against a bright backdrop.
const silhouetteColor = Color(0xFF0B0B12);

/// Draws a fighter with its feet at [feet]. [width] and [height] are the
/// hurtbox size in the same units as [canvas]. [weapon] is 'sword' or
/// 'spear'. [rim] is used unless [skin] sets its own rim light.
///
/// Returns where the weapon tip ended up, for weapon trails.
Offset paintFighter(
  Canvas canvas, {
  required Offset feet,
  required double width,
  required double height,
  required Color rim,
  required String weapon,
  Skin? skin,
  FighterPose pose = const FighterPose(),
  double opacity = 1,
}) {
  final f = pose.facing.toDouble();
  final headR = width * 0.27;
  final hip = feet.translate(0, -height * 0.42);
  final shoulder = feet.translate(f * width * 0.08, -height * 0.74);
  final headC = feet.translate(f * width * 0.12, -height + headR);

  // Legs: swing while running, tuck in the air.
  final swing = math.sin(pose.runPhase) * width * 0.45;
  final tuck = pose.airborne ? height * 0.12 : 0.0;
  final footA = feet.translate(swing + f * width * 0.12, -tuck);
  final footB = feet.translate(-swing - f * width * 0.12, -tuck * 0.5);

  // Weapon hand: toward the attack, pulled back in wind-up, else at rest.
  final Offset hand;
  if (pose.reach != null) {
    hand = feet + pose.reach!;
  } else if (pose.windUp) {
    hand = shoulder.translate(-f * width * 0.7, -height * 0.12);
  } else {
    hand = shoulder.translate(f * width * 0.5, height * 0.22);
  }
  final weaponShape = _WeaponShape(
    weapon,
    shoulder,
    hand,
    width,
    skin?.weaponLength ?? 1,
  );

  // Capes and scarves flow away from the direction of travel.
  final flow = (-f * 0.6 - pose.speedX / 12).clamp(-1.4, 1.4);
  final lift = pose.airborne ? -0.35 : 0.0;
  final accessories = skin?.accessories ?? const <Accessory>[];

  canvas.save();
  if (pose.stunned) {
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(-f * 0.25);
    canvas.translate(-feet.dx, -feet.dy);
  }

  final alpha = (opacity * 255).round();
  final rimColor = (skin?.rim ?? rim).withAlpha((alpha * 0.9).round());
  final bodyColor = (skin?.body ?? silhouetteColor).withAlpha(alpha);

  void silhouette(Paint p, double grow) {
    final limb = Paint()
      ..color = p.color
      ..maskFilter = p.maskFilter
      ..strokeWidth = width * 0.26 + grow * 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(hip, footA, limb);
    canvas.drawLine(hip, footB, limb);
    canvas.drawLine(shoulder, hand, limb..strokeWidth = width * 0.2 + grow * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          shoulder.translate(-width * 0.34 - grow, -height * 0.06 - grow),
          hip.translate(width * 0.3 + grow, grow),
        ),
        Radius.circular(width * 0.25),
      ),
      p,
    );
    canvas.drawCircle(headC, headR + grow, p);
    weaponShape.paint(canvas, p, grow);
  }

  // 1. Rim light glow around everything.
  final glow = Paint()
    ..color = rimColor
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  silhouette(glow, 3);
  for (final a in accessories) {
    _paintAccessory(
      canvas,
      a,
      glow,
      headC,
      headR,
      shoulder,
      hip,
      width,
      height,
      f,
      flow,
      lift,
      grow: 3,
    );
  }

  // 2. Capes hang behind the body.
  for (final a in accessories.where((a) => a.type == AccessoryType.cape)) {
    _paintAccessory(
      canvas,
      a,
      Paint()..color = a.color.withAlpha(alpha),
      headC,
      headR,
      shoulder,
      hip,
      width,
      height,
      f,
      flow,
      lift,
    );
  }

  // 3. The body.
  silhouette(Paint()..color = bodyColor, 0);

  // 4. A colored, glowing weapon on top.
  final weaponColor = skin?.weaponColor;
  if (weaponColor != null) {
    if ((skin?.weaponGlow ?? 0) > 0) {
      weaponShape.paint(
        canvas,
        Paint()
          ..color = weaponColor.withAlpha((alpha * 0.8).round())
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, skin!.weaponGlow),
        2,
      );
    }
    weaponShape.paint(canvas, Paint()..color = weaponColor.withAlpha(alpha), 0);
  }

  // 5. Head and neck accessories in front.
  for (final a in accessories.where((a) => a.type != AccessoryType.cape)) {
    _paintAccessory(
      canvas,
      a,
      Paint()..color = a.color.withAlpha(alpha),
      headC,
      headR,
      shoulder,
      hip,
      width,
      height,
      f,
      flow,
      lift,
    );
  }

  canvas.restore();
  return weaponShape.tip;
}

class _WeaponShape {
  _WeaponShape(this.kind, Offset shoulder, this.hand, this.width, double len)
    : unit = _unit(hand - shoulder),
      length = len;

  final String kind;
  final Offset hand;
  final double width;
  final Offset unit;
  final double length;

  static Offset _unit(Offset d) =>
      d.distance == 0 ? const Offset(1, 0) : d / d.distance;

  Offset get tip => kind == 'spear'
      ? hand + unit * width * (1.7 * length + 0.5)
      : hand + unit * width * 1.2 * length;

  void paint(Canvas canvas, Paint p, double grow) {
    final stroke = Paint()
      ..color = p.color
      ..maskFilter = p.maskFilter
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (kind == 'spear') {
      final head = hand + unit * width * 1.7 * length;
      final butt = hand - unit * width * 0.9;
      canvas.drawLine(butt, head, stroke..strokeWidth = width * 0.1 + grow * 2);
      final side = Offset(-unit.dy, unit.dx) * (width * 0.16 + grow);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(head.dx + side.dx, head.dy + side.dy)
          ..lineTo(head.dx - side.dx, head.dy - side.dy)
          ..close(),
        Paint()
          ..color = p.color
          ..maskFilter = p.maskFilter,
      );
    } else {
      canvas.drawLine(hand, tip, stroke..strokeWidth = width * 0.2 + grow * 2);
      final guard = Offset(-unit.dy, unit.dx) * width * 0.28;
      canvas.drawLine(
        hand + guard,
        hand - guard,
        stroke..strokeWidth = width * 0.12 + grow * 2,
      );
    }
  }
}

void _paintAccessory(
  Canvas canvas,
  Accessory a,
  Paint paint,
  Offset headC,
  double headR,
  Offset shoulder,
  Offset hip,
  double width,
  double height,
  double f,
  double flow,
  double lift, {
  double grow = 0,
}) {
  final s = a.size;
  final p = Paint()
    ..color = paint.color
    ..maskFilter = paint.maskFilter;
  switch (a.type) {
    case AccessoryType.cape:
      final top = shoulder.translate(-f * width * 0.1, -height * 0.02);
      final length = height * 0.62 * s;
      final back = flow * width * 1.1;
      canvas.drawPath(
        Path()
          ..moveTo(top.dx - width * 0.3 - grow, top.dy - grow)
          ..lineTo(top.dx + width * 0.3 + grow, top.dy - grow)
          ..quadraticBezierTo(
            top.dx + back * 0.5,
            top.dy + length * 0.6,
            top.dx + back + width * 0.25,
            top.dy + length * (1 + lift) + grow,
          )
          ..lineTo(top.dx + back - width * 0.35, top.dy + length * (0.9 + lift))
          ..close(),
        p,
      );
    case AccessoryType.horns:
      for (final side in [-1.0, 1.0]) {
        final base = headC.translate(side * headR * 0.55, -headR * 0.6);
        canvas.drawPath(
          Path()
            ..moveTo(base.dx - headR * 0.25 - grow, base.dy + grow)
            ..quadraticBezierTo(
              base.dx + side * headR * 0.9,
              base.dy - headR * 0.4,
              base.dx + side * headR * 0.7,
              base.dy - headR * 1.3 * s - grow,
            )
            ..lineTo(base.dx + headR * 0.25 + grow, base.dy + grow)
            ..close(),
          p,
        );
      }
    case AccessoryType.crown:
      final y = headC.dy - headR * 0.75;
      final w = headR * 1.3 * s;
      final h = headR * 0.8 * s;
      final x = headC.dx;
      canvas.drawPath(
        Path()
          ..moveTo(x - w / 2 - grow, y + grow)
          ..lineTo(x - w / 2 - grow, y - h)
          ..lineTo(x - w / 4, y - h * 0.45)
          ..lineTo(x, y - h - grow)
          ..lineTo(x + w / 4, y - h * 0.45)
          ..lineTo(x + w / 2 + grow, y - h)
          ..lineTo(x + w / 2 + grow, y + grow)
          ..close(),
        p,
      );
    case AccessoryType.scarf:
      final neck = headC.translate(0, headR * 1.05);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: neck,
            width: headR * 2.1 + grow * 2,
            height: headR * 0.6 + grow * 2,
          ),
          Radius.circular(headR * 0.3),
        ),
        p,
      );
      final tailEnd = neck.translate(
        flow * width * 1.2 * s,
        height * (0.16 + lift * 0.3),
      );
      canvas.drawLine(
        neck,
        tailEnd,
        Paint()
          ..color = p.color
          ..maskFilter = p.maskFilter
          ..strokeWidth = headR * 0.45 + grow * 2
          ..strokeCap = StrokeCap.round,
      );
  }
}

/// The weapon a roster fighter carries in the MVP.
String weaponArtFor(String fighterId) =>
    fighterId == 'ranger' ? 'spear' : 'sword';
