import 'dart:math' as math;
import 'dart:ui';

/// Flat Arena backdrop: a vivid sunset behind the dark silhouettes (PRD art
/// style). Drawn once per screen size into a [Picture], then reused.
class StageBackdrop {
  Picture? _picture;
  Size? _size;

  void paint(Canvas canvas, Size size) {
    if (_picture == null || _size != size) {
      _picture = _record(size);
      _size = size;
    }
    canvas.drawPicture(_picture!);
  }

  static Picture _record(Size size) {
    final recorder = PictureRecorder();
    final c = Canvas(recorder);
    final w = size.width;
    final h = size.height;

    // Sky: deep violet down to a warm orange horizon.
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          Offset(0, h * 0.75),
          const [
            Color(0xFF1B1446),
            Color(0xFF5B2A86),
            Color(0xFFD9467A),
            Color(0xFFFFA24C),
          ],
          const [0, 0.35, 0.7, 1],
        ),
    );

    // Stars in the dark upper sky.
    final rng = math.Random(3);
    final star = Paint()..color = const Color(0xCCFFFFFF);
    for (var i = 0; i < 60; i++) {
      c.drawCircle(
        Offset(rng.nextDouble() * w, rng.nextDouble() * h * 0.35),
        rng.nextDouble() * 1.4 + 0.3,
        star,
      );
    }

    // Sun with a soft glow.
    final sun = Offset(w * 0.68, h * 0.52);
    c.drawCircle(
      sun,
      h * 0.3,
      Paint()
        ..shader = Gradient.radial(sun, h * 0.3, const [
          Color(0x66FFE08A),
          Color(0x00FFE08A),
        ]),
    );
    c.drawCircle(sun, h * 0.12, Paint()..color = const Color(0xFFFFE7A3));

    // Mountain ranges, far to near, each darker and more saturated.
    _mountains(c, size, seed: 1, base: 0.62, peak: 0.2, color: 0xFFB0507F);
    _mountains(c, size, seed: 2, base: 0.7, peak: 0.16, color: 0xFF7A2E6E);
    _mountains(c, size, seed: 3, base: 0.8, peak: 0.12, color: 0xFF3F1B52);

    // Floating rocks in the distance.
    final rock = Paint()..color = const Color(0xFF4B2360);
    for (final (x, y, r) in [(0.14, 0.38, 0.05), (0.86, 0.3, 0.035)]) {
      _floatingRock(c, Offset(w * x, h * y), h * r, rock);
    }

    // Mist near the bottom.
    c.drawRect(
      Rect.fromLTWH(0, h * 0.7, w, h * 0.3),
      Paint()
        ..shader = Gradient.linear(Offset(0, h * 0.7), Offset(0, h), const [
          Color(0x00261238),
          Color(0xFF261238),
        ]),
    );
    return recorder.endRecording();
  }

  static void _mountains(
    Canvas c,
    Size size, {
    required int seed,
    required double base,
    required double peak,
    required int color,
  }) {
    final rng = math.Random(seed);
    final path = Path()..moveTo(0, size.height);
    const steps = 9;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final y = size.height * (base - peak * (0.35 + rng.nextDouble() * 0.65));
      path.lineTo(x, y);
      if (i < steps) {
        path.lineTo(
          x + size.width / steps / 2,
          size.height * (base - peak * rng.nextDouble() * 0.3),
        );
      }
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    c.drawPath(path, Paint()..color = Color(color));
  }

  static void _floatingRock(Canvas c, Offset top, double r, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(top.dx - r * 2, top.dy)
        ..lineTo(top.dx + r * 2, top.dy)
        ..lineTo(top.dx + r * 0.6, top.dy + r * 1.6)
        ..lineTo(top.dx, top.dy + r * 2.6)
        ..lineTo(top.dx - r * 0.8, top.dy + r * 1.4)
        ..close(),
      p,
    );
  }
}

/// The main platform: a stone slab with a glowing moss edge and a rocky
/// underside tapering to a point. [left], [right] and [top] are in world units.
void paintPlatform(Canvas canvas, double left, double right, double top) {
  final width = right - left;
  final under = Path()
    ..moveTo(left, top)
    ..lineTo(right, top)
    ..lineTo(right - width * 0.08, top + 60)
    ..lineTo(right - width * 0.3, top + 150)
    ..lineTo(left + width * 0.55, top + 260)
    ..lineTo(left + width * 0.28, top + 150)
    ..lineTo(left + width * 0.06, top + 70)
    ..close();
  canvas.drawPath(
    under,
    Paint()
      ..shader = Gradient.linear(Offset(0, top), Offset(0, top + 260), const [
        Color(0xFF2A1B3D),
        Color(0xFF120B1C),
      ]),
  );
  canvas.drawRect(
    Rect.fromLTRB(left, top, right, top + 22),
    Paint()..color = const Color(0xFF3B2A52),
  );
  canvas.drawRect(
    Rect.fromLTRB(left, top - 4, right, top + 4),
    Paint()
      ..color = const Color(0xFF7CF0B0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
  canvas.drawRect(
    Rect.fromLTRB(left, top - 2, right, top + 2),
    Paint()..color = const Color(0xFFB8FFD6),
  );
}
