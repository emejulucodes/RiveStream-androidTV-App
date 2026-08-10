import 'package:shared_preferences/shared_preferences.dart';

/// How the remote's D-pad drives the page.
enum NavMode {
  /// A virtual mouse pointer moved by the D-pad, clicking whatever is under
  /// it. Works on any layout, including hover menus and non-focusable
  /// click targets, which is why it is the default for a site that was
  /// never built for remotes.
  cursor,

  /// Steps focus through the page's focusable elements in DOM order.
  /// Faster when the page is a simple list/grid, but blind to anything
  /// that isn't a link, button or input.
  tab;

  String get label => switch (this) {
        NavMode.cursor => 'Pointer',
        NavMode.tab => 'Tab focus',
      };

  String get description => switch (this) {
        NavMode.cursor => 'Move an on-screen pointer with the D-pad',
        NavMode.tab => 'Jump between links and buttons',
      };

  NavMode get toggled => this == NavMode.cursor ? NavMode.tab : NavMode.cursor;
}

/// Persists the chosen [NavMode] so the setting survives app restarts.
class NavModeStore {
  static const _key = 'nav_mode';

  static Future<NavMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_key);
      return NavMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => NavMode.cursor,
      );
    } catch (_) {
      return NavMode.cursor;
    }
  }

  static Future<void> save(NavMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Non-fatal: the app still works, the choice just won't persist.
    }
  }
}
