import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/ad_block_prefs.dart';
import '../services/cursor_motion.dart';
import '../services/nav_mode.dart';
import '../services/perf_prefs.dart';
import '../services/remote_control.dart';
import '../services/tv_bridge_script.dart';
import '../widgets/app_splash.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../widgets/focus_highlight.dart';
import '../widgets/offline_view.dart';
import '../widgets/tv_webview.dart';
import '../widgets/virtual_cursor.dart';
import 'settings_screen.dart';

enum _LoadState { loading, ready, error }

/// Owns the app's top-level state machine: splash -> webview, offline/retry,
/// remote D-pad input, Back handling with an exit confirmation, and the
/// screen wake lock.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _loadTimeout = Duration(seconds: 20);

  InAppWebViewController? _controller;
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  /// Overlay state lives in notifiers, not in setState.
  ///
  /// Every cursor step used to call setState, which rebuilds this whole
  /// subtree -- including the InAppWebView widget. Under hybrid composition
  /// a Flutter repaint forces the platform view to be recomposited, so
  /// holding a direction on the D-pad was making the app repaint the entire
  /// WebView surface tens of times a second. These notifiers keep each
  /// overlay's rebuild inside its own ValueListenableBuilder.
  final ValueNotifier<int> _progress = ValueNotifier<int>(0);
  bool _videoPlaying = false;
  bool _fullscreen = false;
  Timer? _timeoutTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  NavMode _navMode = NavMode.cursor;
  bool _adBlockEnabled = true;
  bool _perfMode = true;
  final ValueNotifier<CursorView> _cursorView =
      ValueNotifier<CursorView>(const CursorView());
  Size _viewSize = Size.zero;
  Timer? _cursorIdleTimer;
  Timer? _hoverTimer;
  Offset? _pendingHover;

  /// Focused element rect in viewport fractions, for tab mode's highlight.
  final ValueNotifier<Rect?> _focusRect = ValueNotifier<Rect?>(null);

  /// True while a Flutter dialog/route is on top. Keys are still intercepted
  /// natively in that state, but Dart routes them into Flutter's focus
  /// system instead of into the page.
  bool _overlayActive = false;

  /// Guards the blank-page recovery so it self-heals at most once per load
  /// instead of looping on a site that is genuinely down.
  int _blankRecoveries = 0;

  /// The page must be empty on every poll across this window (2s x 10 = 20s)
  /// before recovery runs.
  static const int _blankPollsBeforeRecovery = 10;
  Timer? _blankPollTimer;

  /// True while a text field inside the page has focus. Interception is
  /// handed back to the platform so the Android TV on-screen keyboard can
  /// receive the D-pad; Back returns control here.
  bool _textInputActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armTimeout();

    RemoteControl.instance
      ..onKey = _handleRemoteKey
      ..start();
    NavModeStore.load().then((mode) {
      if (mounted) setState(() => _navMode = mode);
    });
    AdBlockStore.load().then((enabled) {
      if (mounted) setState(() => _adBlockEnabled = enabled);
    });
    PerfModeStore.load().then((enabled) {
      if (mounted) setState(() => _perfMode = enabled);
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline && _state != _LoadState.error) {
        _showError('No network connection.');
      } else if (!offline && _state == _LoadState.error) {
        _retry();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeoutTimer?.cancel();
    _cursorIdleTimer?.cancel();
    _blankPollTimer?.cancel();
    _connectivitySub?.cancel();
    _hoverTimer?.cancel();
    RemoteControl.instance.onKey = null;
    _progress.dispose();
    _cursorView.dispose();
    _focusRect.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (_videoPlaying) WakelockPlus.enable();
    }
  }

  // ---------------------------------------------------------------------
  // Key interception gating
  // ---------------------------------------------------------------------

  /// Keys are intercepted natively at essentially all times, and Dart
  /// decides where they go. Passing them through to the view hierarchy
  /// instead is not reliable: the WebView is a platform view and usually
  /// holds Android focus, so a Flutter dialog would never see them -- the
  /// original bug. The one exception is an active text field, where the
  /// system IME legitimately needs the keys.
  void _syncInterception() {
    RemoteControl.instance.setInterceptEnabled(!_textInputActive);
  }

  Future<T?> _withOverlay<T>(Future<T?> Function() action) async {
    setState(() => _overlayActive = true);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _overlayActive = false);
    }
  }

  // ---------------------------------------------------------------------
  // Remote input
  // ---------------------------------------------------------------------

  void _handleRemoteKey(RemoteKey key, int repeat) {
    // A Flutter overlay (dialog, settings, offline retry) is on top: drive
    // its focus traversal directly rather than letting the press reach the
    // page underneath.
    if (_overlayActive || _state != _LoadState.ready) {
      _handleFlutterKey(key);
      return;
    }
    if (_navMode == NavMode.tab) {
      _handleTabKey(key);
    } else {
      _handleCursorKey(key, repeat);
    }
  }

  void _handleFlutterKey(RemoteKey key) {
    final focus = FocusManager.instance.primaryFocus;
    // Linear traversal, not focusInDirection(). Every Flutter overlay here
    // is a single row or column of buttons, so widget order *is* the visual
    // order. Directional traversal picks by geometry and got it wrong on
    // the four-button exit dialog -- one Right press jumped from Cancel
    // straight past Refresh to Settings.
    switch (key) {
      case RemoteKey.up:
      case RemoteKey.left:
        focus?.previousFocus();
      case RemoteKey.down:
      case RemoteKey.right:
        focus?.nextFocus();
      case RemoteKey.center:
        final ctx = focus?.context;
        if (ctx != null) {
          Actions.maybeInvoke<ActivateIntent>(ctx, const ActivateIntent());
        }
    }
  }

  Future<void> _handleTabKey(RemoteKey key) async {
    if (key == RemoteKey.center) {
      final focused = _decodeJsObject(
        await _eval('window.__riveFocusedRect ? window.__riveFocusedRect() : null'),
      );
      // An <iframe> is a separate cross-origin document: .click() on it does
      // nothing to the player inside, so tap its centre for real instead.
      final tag = focused?['tag'];
      if (focused != null && (tag == 'IFRAME' || tag == 'INPUT' || tag == 'TEXTAREA')) {
        final cx = ((focused['x'] as num) + (focused['w'] as num) / 2).toDouble();
        final cy = ((focused['y'] as num) + (focused['h'] as num) / 2).toDouble();
        if (!await RemoteControl.instance.tapAt(cx, cy)) {
          await _eval('window.__riveClickFocused && window.__riveClickFocused();');
        }
      } else {
        _applyFocusRect(
          await _eval('window.__riveClickFocused ? window.__riveClickFocused() : null'),
        );
      }
      await _syncTextInputState();
      return;
    }

    final dir = switch (key) {
      RemoteKey.up => 'up',
      RemoteKey.down => 'down',
      RemoteKey.left => 'left',
      RemoteKey.right => 'right',
      RemoteKey.center => '',
    };

    final moved = await _eval("window.__riveMoveFocus ? window.__riveMoveFocus('$dir') : null");
    if (moved != null) {
      _applyFocusRect(moved);
    } else {
      // Nothing focusable that way: scroll the container holding the current
      // focus instead, so the remote can still reach content further down
      // rather than getting stuck at the last element.
      const amount = CursorMotion.scrollFractionMin;
      final dx = key == RemoteKey.left ? -amount : (key == RemoteKey.right ? amount : 0.0);
      final dy = key == RemoteKey.up ? -amount : (key == RemoteKey.down ? amount : 0.0);
      await _eval(
        'window.__riveScrollFocusContainer && window.__riveScrollFocusContainer($dx, $dy);',
      );
      // The focused element has moved on screen; refresh the highlight.
      _applyFocusRect(await _eval('window.__riveFocusedRect ? window.__riveFocusedRect() : null'));
    }
    await _syncTextInputState();
  }

  /// Focuses a sensible starting element when tab mode becomes active.
  Future<void> _initTabFocus() async {
    _applyFocusRect(await _eval('window.__riveFocusFirst ? window.__riveFocusFirst() : null'));
  }

  /// The page reports the focused element as viewport fractions; store it so
  /// [FocusHighlight] can draw over the WebView.
  void _applyFocusRect(dynamic result) {
    final data = _decodeJsObject(result);
    if (data == null) {
      _focusRect.value = null;
      return;
    }
    double value(String k) => (data[k] as num?)?.toDouble() ?? 0;
    final rect = Rect.fromLTWH(value('x'), value('y'), value('w'), value('h'));
    _focusRect.value = rect;
  }

  /// `evaluateJavascript` hands back either a decoded Map or the raw JSON
  /// string depending on platform and value type, so accept both.
  Map<String, dynamic>? _decodeJsObject(dynamic result) {
    if (result == null) return null;
    if (result is Map) return result.cast<String, dynamic>();
    if (result is String) {
      if (result.isEmpty || result == 'null') return null;
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _handleCursorKey(RemoteKey key, int repeat) async {
    if (_viewSize == Size.zero) return;
    final cursor = _cursorView.value.position ??
        Offset(_viewSize.width / 2, _viewSize.height / 2);

    if (key == RemoteKey.center) {
      await _clickAt(cursor);
      return;
    }

    final motion = CursorMotion.next(
      cursor: cursor,
      view: _viewSize,
      key: key,
      repeat: repeat,
    );

    _cursorView.value = _cursorView.value
        .copyWith(position: motion.position, visible: true);
    _restartCursorIdleTimer();

    // Scroll first, then re-hover: the scroll moves different content under
    // a stationary pointer, so the hover target must be recomputed after.
    if (motion.scrolls) {
      final at = _toFraction(motion.position);
      await _eval(
        'window.__riveScrollBy && '
        'window.__riveScrollBy(${at.dx}, ${at.dy}, ${motion.scrollX}, ${motion.scrollY});',
      );
    }
    _queueHover(motion.position);
  }

  /// Coalesces hover dispatch while a direction is held.
  ///
  /// A held D-pad key repeats many times a second, and each hover costs a
  /// platform-channel round trip plus JS that runs elementFromPoint and
  /// dispatches four mouse events -- all of which force layout in the page.
  /// The cursor itself still moves at full rate (it is drawn by Flutter);
  /// only the page is told about the final resting position of each burst.
  void _queueHover(Offset p) {
    _pendingHover = p;
    _hoverTimer ??= Timer(const Duration(milliseconds: 70), () {
      _hoverTimer = null;
      final target = _pendingHover;
      _pendingHover = null;
      if (target != null && mounted) _hoverAt(target);
    });
  }

  /// Fades the pointer out when it hasn't moved for a while, so it isn't
  /// parked on top of whatever the user settled down to watch.
  void _restartCursorIdleTimer() {
    _cursorIdleTimer?.cancel();
    _cursorIdleTimer = Timer(const Duration(seconds: 4), () {
      _cursorView.value = _cursorView.value.copyWith(visible: false);
    });
  }

  Offset _toFraction(Offset p) => Offset(
        (p.dx / _viewSize.width).clamp(0.0, 1.0),
        (p.dy / _viewSize.height).clamp(0.0, 1.0),
      );

  Future<void> _hoverAt(Offset p) async {
    final f = _toFraction(p);
    // Native hover reaches embedded frames; the JS pass additionally paints
    // the hover ring on the actionable element in the top document.
    await RemoteControl.instance.hoverAt(f.dx, f.dy);
    await _eval('window.__riveHoverAt && window.__riveHoverAt(${f.dx}, ${f.dy});');
  }

  Future<void> _clickAt(Offset p) async {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _pendingHover = null;
    final f = _toFraction(p);
    _cursorView.value =
        _cursorView.value.copyWith(pressed: true, visible: true);
    // Only embedded frames need the native tap. A JS-synthesised click
    // cannot reach inside a cross-origin <iframe> -- which is where the
    // site's Embed Mode player lives, so its play button never responded --
    // but it works fine everywhere else and is already proven on this site.
    // Restricting the native path to iframes keeps ordinary clicking on the
    // code that is known to work.
    final hit = await _eval(
      "window.__riveHitKind ? window.__riveHitKind(${f.dx}, ${f.dy}) : 'other'",
    );
    final kind = hit is String ? hit.replaceAll('"', '') : 'other';
    // A text field needs a real touch for the same reason an iframe does:
    // a JS-synthesised focus() never raises the Android keyboard.
    final needsRealTouch = kind == 'iframe' || kind == 'text';
    final tapped =
        needsRealTouch && await RemoteControl.instance.tapAt(f.dx, f.dy);
    if (!tapped) {
      await _eval('window.__riveClickAt && window.__riveClickAt(${f.dx}, ${f.dy});');
    }
    if (!mounted) return;
    _cursorView.value = _cursorView.value.copyWith(pressed: false);
    _restartCursorIdleTimer();
    await _syncTextInputState();
  }

  /// If that press landed on a text field, hand the D-pad back to the
  /// platform so the Android TV on-screen keyboard can use it. Back
  /// reclaims it (see [_handleBack]).
  /// Detects a focused text field and makes it genuinely typeable.
  ///
  /// A field can take focus without any real touch -- this site focuses its
  /// search box from JavaScript as soon as the search view opens. In that
  /// state the page has a caret but the WebView never became the focused
  /// Android view, so there is no InputConnection and the IME either does
  /// not appear or appears attached to nothing and swallows the D-pad.
  ///
  /// Synthesising a real tap on the field is what fixes it: WebView then
  /// takes view focus, builds the InputConnection and raises the keyboard
  /// itself, exactly as it would for a finger.
  Future<void> _syncTextInputState() async {
    final data = _decodeJsObject(
      await _eval('window.__riveFocusedRect ? window.__riveFocusedRect() : null'),
    );
    final active = data != null && data['editable'] == true;
    if (!mounted || active == _textInputActive) return;

    if (active) {
      final x = (data['x'] as num?)?.toDouble() ?? 0;
      final y = (data['y'] as num?)?.toDouble() ?? 0;
      final w = (data['w'] as num?)?.toDouble() ?? 0;
      final h = (data['h'] as num?)?.toDouble() ?? 0;
      final cx = x + w / 2;
      final cy = y + h / 2;
      final onScreen = w > 0 && h > 0 && cx > 0 && cx < 1 && cy > 0 && cy < 1;
      if (!onScreen) return; // Can't tap it, so don't hand over the remote.
      await RemoteControl.instance.tapAt(cx, cy);
    }

    setState(() => _textInputActive = active);
    _syncInterception();
    // Immersive-sticky hides the system bars and fights the IME window on
    // some TV builds, so step out of it while typing and restore after.
    await SystemChrome.setEnabledSystemUIMode(
      active ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
    await RemoteControl.instance.setKeyboardVisible(active);
  }

  Future<dynamic> _eval(String source) async {
    try {
      return await _controller?.evaluateJavascript(source: source);
    } catch (_) {
      // The page can be mid-navigation; a dropped input is not worth
      // surfacing to the user.
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Load state
  // ---------------------------------------------------------------------

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_loadTimeout, () {
      if (_state == _LoadState.loading) {
        _showError('The page is taking too long to load.');
      }
    });
  }

  void _showError(String message) {
    _timeoutTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _state = _LoadState.error;
      _errorMessage = message;
      // Whatever was focused in the page is gone now.
      _textInputActive = false;
    });
    _syncInterception();
  }

  Future<void> _retry() async {
    setState(() {
      _state = _LoadState.loading;
      _textInputActive = false;
    });
    _progress.value = 0;
    _syncInterception();
    _armTimeout();
    await _eval(kResetSiteStorageScript);
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((r) => r == ConnectivityResult.none)) {
      _showError('No network connection.');
      return;
    }
    await _controller?.reload();
  }

  /// Verifies the page actually rendered, then recovers if it never does.
  ///
  /// This polls instead of sampling once. `onLoadStop` fires very early on
  /// this site -- measured on device, `document.documentElement` is still
  /// null at that point -- so a single delayed check caught the document
  /// mid-initialisation and "recovered" a perfectly healthy page, reloading
  /// it and throwing the user back to the home screen mid-navigation.
  ///
  /// The wedged-service-worker case this exists for leaves the document
  /// empty *indefinitely*, so requiring emptiness across the whole window
  /// separates the two without any false positives. As soon as content
  /// appears the poll stops for good.
  void _scheduleBlankPageCheck() {
    _blankPollTimer?.cancel();
    var polls = 0;
    _blankPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _state != _LoadState.ready) {
        timer.cancel();
        return;
      }
      final result = await _eval(kPageEmptyProbe);
      final empty = result == true || result == 'true';
      if (!empty) {
        // The page is alive; never reload this load again.
        timer.cancel();
        _blankRecoveries = 0;
        return;
      }
      if (++polls < _blankPollsBeforeRecovery) return;
      timer.cancel();
      if (_blankRecoveries == 0) {
        _blankRecoveries++;
        await _eval(kResetSiteStorageScript);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        setState(() => _state = _LoadState.loading);
        _armTimeout();
        await _controller?.reload();
        return;
      }
      _showError('RiveStream loaded but showed nothing.');
    });
  }

  void _onVideoPlayingChanged(bool playing) {
    _videoPlaying = playing;
    if (playing) {
      WakelockPlus.enable();
    } else if (!_fullscreen) {
      WakelockPlus.disable();
    }
  }

  void _onFullscreenChanged(bool fullscreen) {
    if (!mounted || fullscreen == _fullscreen) return;
    setState(() => _fullscreen = fullscreen);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (fullscreen) {
      WakelockPlus.enable();
    } else if (!_videoPlaying) {
      WakelockPlus.disable();
    }
  }

  // ---------------------------------------------------------------------
  // Back / exit
  // ---------------------------------------------------------------------

  Future<void> _handleBack() async {
    if (_overlayActive) return;

    // Dismiss the on-screen keyboard and take the D-pad back before Back
    // means anything else.
    if (_textInputActive) {
      await _eval('document.activeElement && document.activeElement.blur();');
      setState(() => _textInputActive = false);
      _syncInterception();
      await RemoteControl.instance.setKeyboardVisible(false);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }

    // While fullscreen, Back means "leave fullscreen", matching every other
    // TV video app.
    if (_fullscreen) {
      await _eval('window.__riveExitFullscreen && window.__riveExitFullscreen();');
      return;
    }
    if (_controller != null && await _controller!.canGoBack()) {
      await _controller!.goBack();
      return;
    }
    await _confirmExit();
  }

  Future<void> _confirmExit() async {
    final choice = await _withOverlay(() => showExitConfirmDialog(context));
    switch (choice) {
      case ExitChoice.exit:
        await SystemNavigator.pop();
      case ExitChoice.refresh:
        await _reloadPage();
      case ExitChoice.settings:
        await _openSettings();
      case ExitChoice.cancel:
      case null:
        break;
    }
  }

  /// Reloads the site from the exit dialog. The player is a same-URL SPA
  /// view, so this is also the way back to a usable state when a stream
  /// wedges without changing the address.
  Future<void> _reloadPage() async {
    if (!mounted) return;
    setState(() {
      _state = _LoadState.loading;
      _textInputActive = false;
      _blankRecoveries = 0;
    });
    _progress.value = 0;
    _focusRect.value = null;
    _syncInterception();
    _armTimeout();
    await _controller?.reload();
  }

  Future<void> _openSettings() async {
    await _withOverlay(() => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              onClearSiteStorage: () async {
                await _eval(kResetSiteStorageScript);
              },
              perfMode: _perfMode,
              onPerfModeChanged: (enabled) {
                setState(() {
                  _perfMode = enabled;
                  _state = _LoadState.loading;
                  _blankRecoveries = 0;
                });
                _focusRect.value = null;
                PerfModeStore.save(enabled);
                _armTimeout();
              },
              adBlockEnabled: _adBlockEnabled,
              onAdBlockChanged: (enabled) {
                setState(() {
                  _adBlockEnabled = enabled;
                  _state = _LoadState.loading;
                  _blankRecoveries = 0;
                });
                _focusRect.value = null;
                AdBlockStore.save(enabled);
                _armTimeout();
              },
              navMode: _navMode,
              onNavModeChanged: (mode) {
                setState(() => _navMode = mode);
                _focusRect.value = null;
                NavModeStore.save(mode);
                if (mode == NavMode.tab) {
                  _initTabFocus();
                } else {
                  _restartCursorIdleTimer();
                }
              },
            ),
          ),
        ));
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF14121A),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            if (size != _viewSize) {
              _viewSize = size;
              // Keep the pointer inside the viewport if the size changed.
              final c = _cursorView.value.position;
              if (c != null) {
                _cursorView.value = _cursorView.value.copyWith(
                  position: Offset(
                    c.dx.clamp(0.0, size.width - 1),
                    c.dy.clamp(0.0, size.height - 1),
                  ),
                );
              }
            }
            return Stack(
              children: [
                TvWebView(
                  // Recreates the WebView when ad blocking is toggled: the
                  // rules and injected scripts are fixed at creation time.
                  key: ValueKey('$_adBlockEnabled/$_perfMode'),
                  adBlockEnabled: _adBlockEnabled,
                  perfMode: _perfMode,
                  onControllerReady: (c) => _controller = c,
                  onLoadStop: () {
                    _timeoutTimer?.cancel();
                    if (mounted && _state != _LoadState.error) {
                      setState(() {
                        _state = _LoadState.ready;
                        // A fresh document has no focused field.
                        _textInputActive = false;
                      });
                      _syncInterception();
                      if (_navMode == NavMode.cursor) {
                        _restartCursorIdleTimer();
                      } else {
                        _initTabFocus();
                      }
                      _scheduleBlankPageCheck();
                    }
                  },
                  onLoadError: _showError,
                  onProgressChanged: (p) => _progress.value = p,
                  onVideoPlayingChanged: _onVideoPlayingChanged,
                  onFullscreenChanged: _onFullscreenChanged,
                ),
                // Each overlay listens to its own notifier and sits behind a
                // RepaintBoundary, so a cursor step repaints a 34px square
                // instead of the whole screen. Under hybrid composition a
                // Flutter repaint drags the WebView surface with it, so
                // keeping these layers independent is what stops D-pad
                // movement from costing full-screen recomposition.
                if (_state == _LoadState.ready && !_fullscreen)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _progress,
                        builder: (context, progress, _) {
                          if (progress >= 100) return const SizedBox.shrink();
                          return LinearProgressIndicator(
                            value: progress / 100,
                            minHeight: 3,
                            backgroundColor: Colors.transparent,
                            valueColor:
                                const AlwaysStoppedAnimation(Color(0xFFFF2E92)),
                          );
                        },
                      ),
                    ),
                  ),
                if (_navMode == NavMode.tab &&
                    _state == _LoadState.ready &&
                    !_overlayActive)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<Rect?>(
                        valueListenable: _focusRect,
                        builder: (context, rect, _) => rect == null
                            ? const SizedBox.shrink()
                            : FocusHighlight(rect: rect),
                      ),
                    ),
                  ),
                if (_navMode == NavMode.cursor &&
                    _state == _LoadState.ready &&
                    !_overlayActive)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<CursorView>(
                        valueListenable: _cursorView,
                        builder: (context, cursor, _) {
                          final position = cursor.position;
                          if (position == null) return const SizedBox.shrink();
                          return AnimatedOpacity(
                            opacity: cursor.visible ? 1 : 0,
                            duration: const Duration(milliseconds: 350),
                            child: Stack(
                              children: [
                                VirtualCursor(
                                  position: position,
                                  pressed: cursor.pressed,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (_state == _LoadState.loading) const AppSplash(),
                if (_state == _LoadState.error)
                  OfflineView(
                    message: _errorMessage,
                    onRetry: _retry,
                    onSettings: _openSettings,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
