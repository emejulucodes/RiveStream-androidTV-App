/// Fills in browser APIs that Chrome has but Android WebView does not.
///
/// Injected at document start, before any of the site's own code runs.
///
/// The site is written for a full browser, so when it touches an API that
/// WebView omits the exception propagates into React and Next.js replaces
/// the whole page with "Application error: a client-side exception has
/// occurred". A missing API is therefore not a degraded feature here -- it
/// is a hard crash of the entire player page.
///
/// Confirmed on device (Android TV, WebView 16):
///   * Pressing Watch threw `ReferenceError: MediaMetadata is not defined`
///     and killed the player page. WebView exposes `navigator.mediaSession`
///     but not the `MediaMetadata` constructor, so the usual
///     `if ('mediaSession' in navigator)` feature check passes and the code
///     then throws on `new MediaMetadata(...)`.
///
/// These shims are intentionally inert: media session metadata drives the
/// OS now-playing UI, which Android TV does not surface for a WebView
/// anyway, so accepting and discarding the values loses nothing while
/// keeping the page alive.
const String kWebViewPolyfillScript = r"""
(function () {
  if (window.__rivePolyfillsInit) return;
  window.__rivePolyfillsInit = true;

  // --- Media Session API -------------------------------------------------
  if (typeof window.MediaMetadata === 'undefined') {
    window.MediaMetadata = function MediaMetadata(init) {
      init = init || {};
      this.title = init.title || '';
      this.artist = init.artist || '';
      this.album = init.album || '';
      this.artwork = init.artwork || [];
    };
  }

  try {
    var session = navigator.mediaSession;
    if (!session) {
      Object.defineProperty(navigator, 'mediaSession', {
        configurable: true,
        value: {
          metadata: null,
          playbackState: 'none',
          setActionHandler: function () {},
          setPositionState: function () {},
          setCameraActive: function () {},
          setMicrophoneActive: function () {}
        }
      });
    } else {
      // Present but incomplete: fill in only the missing methods, since
      // calling an absent one throws just as hard as a missing constructor.
      if (typeof session.setActionHandler !== 'function') {
        session.setActionHandler = function () {};
      }
      if (typeof session.setPositionState !== 'function') {
        session.setPositionState = function () {};
      }
    }
  } catch (e) {}
})();
""";
