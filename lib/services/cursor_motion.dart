import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'remote_control.dart';

/// The outcome of one D-pad press in pointer mode: where the cursor lands,
/// and how far the page should scroll underneath it.
class CursorStep {
  const CursorStep({required this.position, this.scrollX = 0, this.scrollY = 0});

  /// New cursor position, clamped to the viewport, in logical pixels.
  final Offset position;

  /// Scroll deltas as *fractions of the viewport*, not pixels. The page's
  /// CSS pixels and Flutter's logical pixels do not correspond (a desktop
  /// user agent usually gets a wide default layout viewport), so fractions
  /// are the only thing meaningful on both sides of the JS bridge.
  final double scrollX;
  final double scrollY;

  bool get scrolls => scrollX != 0 || scrollY != 0;
}

/// Pure geometry for pointer-mode movement. Kept out of the widget so the
/// edge-scroll behaviour can be tested without a WebView.
class CursorMotion {
  /// Movement per press, in logical pixels. Holding a direction eases from
  /// [stepMin] to [stepMax] so the pointer can cross a 1080p screen quickly
  /// while still landing precisely on a single tap.
  static const double stepMin = 26;
  static const double stepMax = 110;

  /// How close to the edge the pointer must be before presses start
  /// scrolling the page instead of only moving the pointer.
  static const double edgeMargin = 64;

  /// Scroll distance per press, as a fraction of the viewport.
  static const double scrollFractionMin = 0.18;
  static const double scrollFractionMax = 0.45;

  /// Repeat count at which acceleration reaches its maximum.
  static const int accelerationRepeats = 12;

  static double _ease(int repeat) => (repeat / accelerationRepeats).clamp(0.0, 1.0);

  static double stepFor(int repeat) {
    final t = _ease(repeat);
    // Quadratic: slow and precise at first, fast once clearly held down.
    return stepMin + (stepMax - stepMin) * t * t;
  }

  static double scrollFractionFor(int repeat) {
    final t = _ease(repeat);
    return scrollFractionMin + (scrollFractionMax - scrollFractionMin) * t;
  }

  static CursorStep next({
    required Offset cursor,
    required Size view,
    required RemoteKey key,
    required int repeat,
  }) {
    if (key == RemoteKey.center || view.isEmpty) {
      return CursorStep(position: cursor);
    }

    final step = stepFor(repeat);
    final moved = switch (key) {
      RemoteKey.up => cursor.translate(0, -step),
      RemoteKey.down => cursor.translate(0, step),
      RemoteKey.left => cursor.translate(-step, 0),
      RemoteKey.right => cursor.translate(step, 0),
      RemoteKey.center => cursor,
    };

    // The band must be at least one step wide, otherwise a large
    // accelerated step can jump straight from outside the band to the
    // clamped edge without ever satisfying the scroll test.
    final margin = math.max(edgeMargin, step);
    final fraction = scrollFractionFor(repeat);

    double scrollX = 0;
    double scrollY = 0;
    switch (key) {
      case RemoteKey.up:
        if (moved.dy < margin) scrollY = -fraction;
      case RemoteKey.down:
        if (moved.dy > view.height - margin) scrollY = fraction;
      case RemoteKey.left:
        if (moved.dx < margin) scrollX = -fraction;
      case RemoteKey.right:
        if (moved.dx > view.width - margin) scrollX = fraction;
      case RemoteKey.center:
        break;
    }

    return CursorStep(
      position: Offset(
        moved.dx.clamp(0.0, view.width - 1),
        moved.dy.clamp(0.0, view.height - 1),
      ),
      scrollX: scrollX,
      scrollY: scrollY,
    );
  }
}
