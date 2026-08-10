import 'package:flutter_test/flutter_test.dart';
import 'package:rivestream/services/nav_mode.dart';
import 'package:rivestream/services/remote_control.dart';

void main() {
  group('NavMode', () {
    test('defaults are the two supported modes', () {
      expect(NavMode.values, [NavMode.cursor, NavMode.tab]);
    });

    test('toggling round-trips', () {
      expect(NavMode.cursor.toggled, NavMode.tab);
      expect(NavMode.tab.toggled, NavMode.cursor);
      expect(NavMode.cursor.toggled.toggled, NavMode.cursor);
    });

    test('every mode has a label and description for the settings screen', () {
      for (final mode in NavMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.description, isNotEmpty);
      }
    });

    test('persisted name is stable -- changing it would silently reset users', () {
      // NavModeStore keys off `mode.name`, so these strings are effectively
      // stored data, not just identifiers.
      expect(NavMode.cursor.name, 'cursor');
      expect(NavMode.tab.name, 'tab');
    });
  });

  group('RemoteKey', () {
    test('covers every key MainActivity forwards', () {
      // Must stay in sync with keyName() in MainActivity.kt.
      expect(
        RemoteKey.values.map((k) => k.name).toSet(),
        {'up', 'down', 'left', 'right', 'center'},
      );
    });
  });
}
