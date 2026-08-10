import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rivestream/services/cursor_motion.dart';
import 'package:rivestream/services/remote_control.dart';

void main() {
  const view = Size(1920, 1080);

  CursorStep step(Offset from, RemoteKey key, {int repeat = 0}) =>
      CursorMotion.next(cursor: from, view: view, key: key, repeat: repeat);

  group('cursor movement', () {
    test('moves in the pressed direction', () {
      const start = Offset(960, 540);
      expect(step(start, RemoteKey.up).position.dy, lessThan(start.dy));
      expect(step(start, RemoteKey.down).position.dy, greaterThan(start.dy));
      expect(step(start, RemoteKey.left).position.dx, lessThan(start.dx));
      expect(step(start, RemoteKey.right).position.dx, greaterThan(start.dx));
    });

    test('stays inside the viewport', () {
      final atTop = step(const Offset(960, 0), RemoteKey.up, repeat: 30);
      expect(atTop.position.dy, greaterThanOrEqualTo(0));

      final atRight = step(const Offset(1919, 540), RemoteKey.right, repeat: 30);
      expect(atRight.position.dx, lessThanOrEqualTo(view.width - 1));
    });

    test('accelerates while the key is held', () {
      const start = Offset(960, 540);
      final tap = step(start, RemoteKey.right).position.dx - start.dx;
      final held = step(start, RemoteKey.right, repeat: 30).position.dx - start.dx;
      expect(held, greaterThan(tap));
      expect(tap, CursorMotion.stepMin);
      expect(held, CursorMotion.stepMax);
    });

    test('center press neither moves nor scrolls', () {
      const start = Offset(300, 300);
      final result = step(start, RemoteKey.center);
      expect(result.position, start);
      expect(result.scrolls, isFalse);
    });

    test('a zero-sized viewport is a no-op rather than a divide-by-zero', () {
      final result = CursorMotion.next(
        cursor: Offset.zero,
        view: Size.zero,
        key: RemoteKey.down,
        repeat: 0,
      );
      expect(result.position, Offset.zero);
      expect(result.scrolls, isFalse);
    });
  });

  group('edge scrolling', () {
    // This is the reported bug: the pointer sat at the edge and the page
    // never scrolled.
    test('scrolls down when pushing past the bottom edge', () {
      final result = step(const Offset(960, 1079), RemoteKey.down);
      expect(result.scrollY, greaterThan(0));
      expect(result.scrollX, 0);
    });

    test('scrolls up when pushing past the top edge', () {
      final result = step(const Offset(960, 0), RemoteKey.up);
      expect(result.scrollY, lessThan(0));
    });

    test('scrolls horizontally at the left and right edges', () {
      expect(step(const Offset(0, 540), RemoteKey.left).scrollX, lessThan(0));
      expect(step(const Offset(1919, 540), RemoteKey.right).scrollX, greaterThan(0));
    });

    test('does not scroll from the middle of the screen', () {
      for (final key in [RemoteKey.up, RemoteKey.down, RemoteKey.left, RemoteKey.right]) {
        expect(step(const Offset(960, 540), key).scrolls, isFalse, reason: '$key');
      }
    });

    test('does not scroll against the direction of travel', () {
      // Sitting at the bottom edge but moving up must not scroll down.
      expect(step(const Offset(960, 1079), RemoteKey.up).scrollY, lessThanOrEqualTo(0));
    });

    test('a large accelerated step still triggers the scroll it flies over', () {
      // Regression guard: with a fixed 64px band, a 110px step could jump
      // from outside the band straight to the clamped edge, scrolling never.
      final start = Offset(960, view.height - CursorMotion.stepMax - 10);
      final result = step(start, RemoteKey.down, repeat: 30);
      expect(result.scrollY, greaterThan(0));
    });

    test('scroll deltas are viewport fractions, never pixel counts', () {
      final result = step(const Offset(960, 1079), RemoteKey.down, repeat: 30);
      expect(result.scrollY.abs(), lessThanOrEqualTo(1.0));
      expect(result.scrollY.abs(), greaterThan(0));
    });

    test('scrolling accelerates with the key held, like movement does', () {
      final tap = step(const Offset(960, 1079), RemoteKey.down).scrollY;
      final held = step(const Offset(960, 1079), RemoteKey.down, repeat: 30).scrollY;
      expect(held, greaterThan(tap));
      expect(tap, CursorMotion.scrollFractionMin);
      expect(held, CursorMotion.scrollFractionMax);
    });
  });
}
