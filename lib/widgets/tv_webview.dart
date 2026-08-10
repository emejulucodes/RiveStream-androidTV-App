import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/ad_block_rules.dart';
import '../services/ad_block_script.dart';
import '../services/tv_bridge_script.dart';
import '../services/tv_perf_script.dart';
import '../services/webview_polyfills.dart';

const String kHomeUrl = 'https://www.rivestream.app';

// A desktop Chrome UA: rivestream.app's mobile layout assumes a touch
// pointer (hover menus, small tap targets) which does not translate well
// to a 10-foot D-pad UI, so the desktop layout is requested instead.
const String kDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Wraps [InAppWebView] with the settings, scripts and callbacks needed to
/// run rivestream.app acceptably on an Android TV: JS/DOM storage/autoplay
/// enabled, disk caching, a desktop UA, D-pad spatial navigation, network-
/// and DOM-level ad blocking, popup/new-tab suppression, fullscreen video
/// handling, and video-state/progress/error reporting to the parent.
class TvWebView extends StatefulWidget {
  const TvWebView({
    super.key,
    required this.onControllerReady,
    required this.onLoadStop,
    required this.onLoadError,
    required this.onProgressChanged,
    required this.onVideoPlayingChanged,
    required this.onFullscreenChanged,
    required this.adBlockEnabled,
    required this.perfMode,
  });

  final ValueChanged<InAppWebViewController> onControllerReady;
  final VoidCallback onLoadStop;
  final ValueChanged<String> onLoadError;
  final ValueChanged<int> onProgressChanged;
  final ValueChanged<bool> onVideoPlayingChanged;
  final ValueChanged<bool> onFullscreenChanged;

  /// When false, neither the network rules nor the in-page ad/popup script
  /// are installed. Changing it requires the WebView to be recreated, which
  /// HomeShell does by keying this widget on the flag.
  final bool adBlockEnabled;

  /// Strips the page's costly visual effects. See tv_perf_script.dart.
  final bool perfMode;

  @override
  State<TvWebView> createState() => _TvWebViewState();
}

class _TvWebViewState extends State<TvWebView> {
  // Ad/popup suppression is injected AT_DOCUMENT_START so it is installed
  // before any inline ad script on the page can run; the D-pad navigation
  // helper needs a populated DOM, so it goes in AT_DOCUMENT_END.
  UnmodifiableListView<UserScript> get _userScripts => UnmodifiableListView([
    // First: the site crashes outright on APIs WebView lacks, so the shims
    // must exist before any page script runs.
    UserScript(
      source: kWebViewPolyfillScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    // Perf CSS goes in at document start so the browser never spends a
    // frame compositing the effects it strips.
    if (widget.perfMode)
      UserScript(
        source: kTvPerfScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    if (widget.adBlockEnabled)
      UserScript(
        source: kAdBlockScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    UserScript(
      source: kFullscreenBridgeScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: kTvBridgeScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(kHomeUrl)),
      initialUserScripts: _userScripts,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        // Popups are blocked outright, so scripts must not be allowed to
        // open windows on their own either.
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        domStorageEnabled: true,
        databaseEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        userAgent: kDesktopUserAgent,
        cacheEnabled: true,
        cacheMode: CacheMode.LOAD_DEFAULT,
        useHybridComposition: true,
        useShouldOverrideUrlLoading: true,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        transparentBackground: false,
        disableDefaultErrorPage: true,
        hardwareAcceleration: true,
        // Network-level ad blocking.
        contentBlockers: widget.adBlockEnabled ? buildAdBlockRules() : const [],

        // --- TV performance tuning -------------------------------------
        // Ask Android to keep the renderer process at an important
        // priority. Without this a TV launcher's memory pressure can
        // demote the renderer, which shows up as the page freezing for a
        // second at a time during playback.
        rendererPriorityPolicy: RendererPriorityPolicy(
          rendererRequestedPriority: RendererPriority.RENDERER_PRIORITY_IMPORTANT,
          waivedWhenNotVisible: true,
        ),
        // Rasterising a screen's worth of extra content off-view costs GPU
        // memory that a TV box does not have to spare.
        offscreenPreRaster: false,
        // No scrollbars on a 10-foot UI: they are an extra composited
        // layer that repaints on every scroll.
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        overScrollMode: OverScrollMode.NEVER,
        // These each add a Dart round-trip per resource or per XHR when on.
        // They are off by default; stated explicitly so nothing turns them
        // on by accident later.
        useOnLoadResource: false,
        useShouldInterceptAjaxRequest: false,
        useShouldInterceptFetchRequest: false,
        // The site is already dark; letting WebView also run a darkening
        // pass is pure wasted work per frame.
        algorithmicDarkeningAllowed: false,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'onVideoPlayState',
          callback: (args) {
            final playing = args.isNotEmpty && args.first == true;
            widget.onVideoPlayingChanged(playing);
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onFullscreenChange',
          callback: (args) {
            final fullscreen = args.isNotEmpty && args.first == true;
            widget.onFullscreenChanged(fullscreen);
          },
        );
        widget.onControllerReady(controller);
      },
      onLoadStop: (controller, url) async {
        // Re-inject defensively: covers same-document/SPA transitions where
        // a brand new document (and thus a fresh initialUserScripts pass)
        // may not fire. All three are idempotent via their init guards.
        await controller.evaluateJavascript(source: kWebViewPolyfillScript);
        if (widget.perfMode) {
          await controller.evaluateJavascript(source: kTvPerfScript);
        }
        if (widget.adBlockEnabled) {
          await controller.evaluateJavascript(source: kAdBlockScript);
        }
        await controller.evaluateJavascript(source: kFullscreenBridgeScript);
        await controller.evaluateJavascript(source: kTvBridgeScript);
        widget.onLoadStop();
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? true) {
          widget.onLoadError(error.description);
        }
      },
      onProgressChanged: (controller, progress) => widget.onProgressChanged(progress),
      onConsoleMessage: (controller, message) {
        // Surfaces the injected scripts' own diagnostics in `flutter run`
        // output; the page renders into a hybrid-composition surface that
        // screenshots can't capture, so logging is the only way to see
        // what the D-pad bridge is actually doing on a device.
        if (kDebugMode) debugPrint('[web] ${message.message}');
      },
      // Native fullscreen path: fires when the page hands a video (or other
      // element) to the WebView's custom-view host.
      onEnterFullscreen: (controller) => widget.onFullscreenChanged(true),
      onExitFullscreen: (controller) => widget.onFullscreenChanged(false),
      // Refuse every request to open a new window/tab. Returning false tells
      // the WebView not to create one; the URL is dropped rather than being
      // loaded in the current view, since a request to open a *new* window
      // on a streaming site is almost always a popunder ad.
      onCreateWindow: (controller, createWindowAction) async => false,
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url?.toString();
        // Same-site and in-page navigation proceeds normally. Off-site
        // top-level navigation is treated as a redirect ad and cancelled,
        // except for the sign-in providers in the allowlist.
        if (action.isForMainFrame && !isNavigationAllowed(url)) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
