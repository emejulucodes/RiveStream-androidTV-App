import 'package:flutter/services.dart';

/// D-pad keys forwarded from MainActivity.dispatchKeyEvent.
enum RemoteKey { up, down, left, right, center }

/// Dart end of the native key-interception channel.
///
/// See MainActivity.kt for why key handling lives at the Activity level
/// rather than in the Flutter widget tree or in page JavaScript.
class RemoteControl {
  RemoteControl._();
  static final RemoteControl instance = RemoteControl._();

  static const MethodChannel _channel =
      MethodChannel('com.emejulucodes.rivestream/remote');

  /// Called for every intercepted key press. [repeat] is Android's repeat
  /// count: 0 on the initial press, incrementing while the key is held,
  /// which callers use to accelerate cursor movement.
  void Function(RemoteKey key, int repeat)? onKey;

  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onKey') return null;
      final args = (call.arguments as Map).cast<String, dynamic>();
      final key = switch (args['key'] as String?) {
        'up' => RemoteKey.up,
        'down' => RemoteKey.down,
        'left' => RemoteKey.left,
        'right' => RemoteKey.right,
        'center' => RemoteKey.center,
        _ => null,
      };
      if (key != null) {
        onKey?.call(key, (args['repeat'] as int?) ?? 0);
      }
      return null;
    });
  }

  /// Injects a real touch tap into the WebView at a point given as a
  /// fraction of the window. Returns false if the platform could not
  /// dispatch it, so the caller can fall back to a synthetic DOM click.
  ///
  /// Needed because a JS-synthesised click cannot reach inside a
  /// cross-origin `<iframe>` -- see dispatchTap in MainActivity.kt.
  Future<bool> tapAt(double fx, double fy) => _invokePoint('tapAt', fx, fy);

  /// Moves a real mouse pointer over the page, so hover-only UI inside
  /// embedded frames reveals itself.
  Future<bool> hoverAt(double fx, double fy) => _invokePoint('hoverAt', fx, fy);

  Future<bool> _invokePoint(String method, double fx, double fy) async {
    try {
      final ok = await _channel.invokeMethod<bool>(method, {'fx': fx, 'fy': fy});
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks the platform to show or hide the on-screen keyboard. A real tap
  /// on a field usually does this by itself; this is the fallback for when
  /// WebView-as-platform-view leaves focus somewhere unexpected.
  Future<void> setKeyboardVisible(bool visible) async {
    try {
      await _channel.invokeMethod(visible ? 'showKeyboard' : 'hideKeyboard');
    } on PlatformException {
      // Nothing to do -- the tap itself may still have raised the IME.
    } on MissingPluginException {
      // Not running on Android.
    }
  }

  /// Enables/disables native interception. Disable while a Flutter dialog
  /// or route is on top so its buttons get normal focus traversal; the
  /// native side then leaves key events completely untouched.
  Future<void> setInterceptEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setInterceptEnabled', enabled);
    } on MissingPluginException {
      // Not running on Android (e.g. unit tests) -- nothing to toggle.
    }
  }
}
