import 'package:shared_preferences/shared_preferences.dart';

/// Whether ad blocking is on, persisted across launches.
///
/// This is user-switchable on purpose. rivestream.app plays through a list
/// of third-party stream aggregators, and an individual server failing
/// ("Video Load Error. Try other servers") looks identical whether the
/// cause is that server being down or a blocking rule catching something
/// the player needed. Being able to turn blocking off and retry is both the
/// workaround and the diagnosis.
class AdBlockStore {
  static const _key = 'ad_block_enabled';

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
