import 'package:shared_preferences/shared_preferences.dart';

/// Whether the page's expensive visual effects are stripped.
///
/// On by default: on TV hardware the blur/shadow/animation work is the
/// difference between a usable UI and a stuttering one. It is switchable
/// because it does change how the site looks -- backdrop blurs and card
/// shadows are part of the design -- so anyone running this on a fast box
/// can have the full look back.
class PerfModeStore {
  static const _key = 'perf_mode_enabled';

  static Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> save(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {
      // Non-fatal: the choice just won't persist.
    }
  }
}
