import 'package:flutter/material.dart';

/// Immutable pointer state, held in a ValueNotifier so cursor movement
/// repaints only the cursor instead of rebuilding the WebView subtree.
@immutable
class CursorView {
  const CursorView({this.position, this.pressed = false, this.visible = true});

  final Offset? position;
  final bool pressed;
  final bool visible;

  CursorView copyWith({Offset? position, bool? pressed, bool? visible}) =>
      CursorView(
        position: position ?? this.position,
        pressed: pressed ?? this.pressed,
        visible: visible ?? this.visible,
      );

  @override
  bool operator ==(Object other) =>
      other is CursorView &&
      other.position == position &&
      other.pressed == pressed &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(position, pressed, visible);
}

/// The on-screen pointer for [NavMode.cursor], drawn by Flutter rather than
/// by the page.
///
/// Drawing it here (instead of injecting a DOM element) keeps it perfectly
/// smooth and always on top: it never gets clipped by page overflow, hidden
/// behind a stacking context, or wiped out when the site re-renders.
class VirtualCursor extends StatelessWidget {
  const VirtualCursor({super.key, required this.position, this.pressed = false});

  final Offset position;
  final bool pressed;

  static const double size = 34;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        child: AnimatedScale(
          scale: pressed ? 0.8 : 1.0,
          duration: const Duration(milliseconds: 90),
          alignment: Alignment.topLeft,
          child: CustomPaint(
            size: const Size(size, size),
            painter: _CursorPainter(),
          ),
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Classic arrow pointer, sized for a 10-foot viewing distance.
    final arrow = Path()
      ..moveTo(0, 0)
      ..lineTo(0, h * 0.76)
      ..lineTo(w * 0.22, h * 0.58)
      ..lineTo(w * 0.36, h * 0.92)
      ..lineTo(w * 0.52, h * 0.85)
      ..lineTo(w * 0.38, h * 0.52)
      ..lineTo(w * 0.64, h * 0.50)
      ..close();

    // Drop shadow so the pointer stays visible over bright poster art.
    canvas.drawPath(
      arrow.shift(const Offset(1.5, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF14121A),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
