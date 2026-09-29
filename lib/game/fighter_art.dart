import 'dart:math' as math;
import 'dart:ui';

/// Pose details that change how a fighter is drawn. Purely visual.
class FighterPose {
  const FighterPose({
    this.facing = 1,
    this.runPhase = 0,
    this.airborne = false,
    this.reach,
    this.windUp = false,
    this.stunned = false,
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
}

/// PRD art style: a solid dark silhouette with a colored rim light, so two
/// fighters stay easy to tell apart against a bright backdrop.
const silhouetteColor = Color(0xFF0B0B12);

/// Draws a fighter with its feet at [feet]. [width] and [height] are the
/// hurtbox size in the same units as [canvas]. [weapon] is 'sword' or
/// 'spear'.
void paintFighter(
  Canvas canvas, {
  required Offset feet,
  required double width,
  required double height,
  required Color rim,
  required String weapon,
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

  canvas.save();
  if (pose.stunned) {
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(-f * 0.25);
    canvas.translate(-feet.dx, -feet.dy);
  }

  void body(Paint p, double grow) {
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
    _paintWeapon(canvas, weapon, shoulder, hand, width, p, grow);
  }

  final alpha = (opacity * 255).round();
  body(
    Paint()
      ..color = rim.withAlpha((alpha * 0.9).round())
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    3,
  );
  body(Paint()..color = silhouetteColor.withAlpha(alpha), 0);
  canvas.restore();
}

void _paintWeapon(
  Canvas canvas,
  String weapon,
  Offset shoulder,
  Offset hand,
  double width,
  Paint p,
  double grow,
) {
  var dir = hand - shoulder;
  if (dir.distance == 0) dir = const Offset(1, 0);
  final unit = dir / dir.distance;
  final stroke = Paint()
    ..color = p.color
    ..maskFilter = p.maskFilter
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (weapon == 'spear') {
    final tip = hand + unit * width * 1.7;
    final butt = hand - unit * width * 0.9;
    canvas.drawLine(butt, tip, stroke..strokeWidth = width * 0.1 + grow * 2);
    final side = Offset(-unit.dy, unit.dx) * width * 0.16;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx + unit.dx * width * 0.5, tip.dy + unit.dy * width * 0.5)
        ..lineTo(tip.dx + side.dx, tip.dy + side.dy)
        ..lineTo(tip.dx - side.dx, tip.dy - side.dy)
        ..close(),
      Paint()
        ..color = p.color
        ..maskFilter = p.maskFilter,
    );
  } else {
    final tip = hand + unit * width * 1.2;
    canvas.drawLine(hand, tip, stroke..strokeWidth = width * 0.2 + grow * 2);
    final guard = Offset(-unit.dy, unit.dx) * width * 0.28;
    canvas.drawLine(
      hand + guard,
      hand - guard,
      stroke..strokeWidth = width * 0.12 + grow * 2,
    );
  }
}

/// The weapon a roster fighter carries in the MVP.
String weaponArtFor(String fighterId) =>
    fighterId == 'ranger' ? 'spear' : 'sword';
