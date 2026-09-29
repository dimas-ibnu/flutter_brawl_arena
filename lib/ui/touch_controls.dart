import 'package:flutter/material.dart';

import '../input/touch_input.dart';
import '../sim/input_frame.dart';

/// On-screen controls from the PRD: a floating stick under the left thumb and
/// jump / light / heavy / dodge / weapon under the right.
///
/// Every control is its own [Listener], so several fingers work at once.
class TouchControls extends StatelessWidget {
  const TouchControls({super.key, required this.input});

  final TouchInput input;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.45,
            heightFactor: 1,
            child: VirtualStick(input: input),
          ),
        ),
        _button(Button.light, 'Light', right: 110, bottom: 36, size: 88),
        _button(Button.jump, 'Jump', right: 214, bottom: 28, size: 72),
        _button(Button.heavy, 'Heavy', right: 24, bottom: 122, size: 72),
        _button(Button.dodge, 'Dodge', right: 124, bottom: 150, size: 64),
        _button(Button.weapon, 'Weapon', right: 24, bottom: 36, size: 60),
      ],
    );
  }

  Widget _button(
    Button button,
    String label, {
    required double right,
    required double bottom,
    required double size,
  }) => Positioned(
    right: right,
    bottom: bottom,
    child: TouchButton(
      key: Key('touch-${button.name}'),
      input: input,
      button: button,
      label: label,
      size: size,
    ),
  );
}

/// A stick that appears where the thumb lands and follows it.
class VirtualStick extends StatefulWidget {
  const VirtualStick({super.key, required this.input});

  final TouchInput input;

  static const double radius = 64;

  @override
  State<VirtualStick> createState() => _VirtualStickState();
}

class _VirtualStickState extends State<VirtualStick> {
  int? _pointer;
  Offset? _origin;
  Offset _knob = Offset.zero;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    setState(() {
      _pointer = e.pointer;
      _origin = e.localPosition;
      _knob = Offset.zero;
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    var delta = e.localPosition - _origin!;
    if (delta.distance > VirtualStick.radius) {
      delta = delta * (VirtualStick.radius / delta.distance);
    }
    widget.input.setStick(
      delta.dx / VirtualStick.radius,
      delta.dy / VirtualStick.radius,
    );
    setState(() => _knob = delta);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    widget.input.setStick(0, 0);
    setState(() {
      _pointer = null;
      _origin = null;
      _knob = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('touch-stick'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: CustomPaint(
        size: Size.infinite,
        painter: _StickPainter(origin: _origin, knob: _knob),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter({required this.origin, required this.knob});

  final Offset? origin;
  final Offset knob;

  @override
  void paint(Canvas canvas, Size size) {
    final active = origin != null;
    // Idle: a faint hint where the thumb usually rests.
    final center = origin ?? Offset(120, size.height - 120);
    canvas.drawCircle(
      center,
      VirtualStick.radius,
      Paint()
        ..color = Colors.white.withValues(alpha: active ? 0.18 : 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center + knob,
      28,
      Paint()..color = Colors.white.withValues(alpha: active ? 0.5 : 0.2),
    );
  }

  @override
  bool shouldRepaint(_StickPainter old) =>
      old.origin != origin || old.knob != knob;
}

/// Holds its [button] down for as long as any finger is on it.
class TouchButton extends StatefulWidget {
  const TouchButton({
    super.key,
    required this.input,
    required this.button,
    required this.label,
    required this.size,
  });

  final TouchInput input;
  final Button button;
  final String label;
  final double size;

  @override
  State<TouchButton> createState() => _TouchButtonState();
}

class _TouchButtonState extends State<TouchButton> {
  int _fingers = 0;

  void _down(PointerDownEvent _) {
    widget.input.press(widget.button);
    setState(() => _fingers++);
  }

  void _up(PointerEvent _) {
    widget.input.release(widget.button);
    setState(() => _fingers--);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _fingers > 0;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: pressed ? 0.35 : 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: widget.size / 5.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
