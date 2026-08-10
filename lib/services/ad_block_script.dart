/// In-page ad/popup suppression, injected at document start.
///
/// This is the second half of the ad blocker. The [ContentBlocker] rules in
/// ad_block_rules.dart stop ad *requests*; this script handles what those
/// rules structurally cannot:
///
///  * popups/new tabs opened from JS (`window.open`, synthetic anchor
///    clicks, `target="_blank"`) — the classic streaming-site popunder,
///  * ads injected directly into the document rather than fetched,
///  * leftover empty ad containers,
///  * navigation hijacks (`window.location =` to an ad redirector).
///
/// It runs at document start so it wins the race against inline ad scripts.
const String kAdBlockScript = r"""
(function () {
  if (window.__riveAdBlockInit) return;
  window.__riveAdBlockInit = true;

  var HOME_HOSTS = ['rivestream.app'];

  // This script is injected into every frame, including the third-party
  // player embeds. Almost none of it is safe to run in those: the site's
  // Embed Mode nests cloudorchestranova.com -> vsembed.ru, and inside those
  // documents *everything* is "off-site" by the isSameSite() test below, so
  // the anchor/navigation guards would block the player's own controls, and
  // the overlay sweep would delete the player container (it is a fullscreen
  // high-z-index div with no <video> in it until playback starts).
  //
  // Only the window.open stub runs everywhere -- that is the actual
  // popunder defence, and it is inert for legitimate player code.
  var isTopFrame = (function () {
    try { return window.top === window.self; } catch (e) { return false; }
  })();

  function isSameSite(url) {
    try {
      var u = new URL(url, location.href);
      if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
      return HOME_HOSTS.some(function (h) {
        return u.hostname === h || u.hostname.endsWith('.' + h);
      });
    } catch (e) { return false; }
  }

  // ---------------------------------------------------------------
  // 1. Kill window.open outright.
  // Returns a inert stub rather than null: ad scripts frequently call
  // .focus()/.close() on the result and would otherwise throw, which can
  // abort the surrounding (legitimate) script.
  // ---------------------------------------------------------------
  function makeStubWindow() {
    var stub = {
      closed: true,
      focus: function () {}, blur: function () {}, close: function () {},
      postMessage: function () {}, alert: function () {}, print: function () {},
      moveTo: function () {}, resizeTo: function () {}, scrollTo: function () {},
      opener: null, location: { href: 'about:blank', replace: function () {}, assign: function () {} },
      document: { write: function () {}, writeln: function () {}, close: function () {}, body: null }
    };
    stub.self = stub; stub.window = stub; stub.top = stub;
    return stub;
  }
  try {
    Object.defineProperty(window, 'open', {
      configurable: false, writable: false,
      value: function () { return makeStubWindow(); }
    });
  } catch (e) { window.open = function () { return makeStubWindow(); }; }

  // Everything past this point is main-document only.
  if (!isTopFrame) return;

  // ---------------------------------------------------------------
  // 2. Neutralize target="_blank" and off-site anchor clicks.
  // Capture-phase so it runs before the page's own handlers.
  // ---------------------------------------------------------------
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    if (!a) return;
    var href = a.getAttribute('href');
    if (!href || href.indexOf('javascript:') === 0 || href.charAt(0) === '#') return;
    if (a.target === '_blank' || a.target === '_new') a.removeAttribute('target');
    if (!isSameSite(href)) {
      // Off-site anchor: on a TV there is nowhere for it to go, and on a
      // streaming site it is overwhelmingly an ad redirect.
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  }, true);

  // ---------------------------------------------------------------
  // 3. Block the synthetic-anchor popunder: ad scripts build a detached
  // <a target="_blank"> and call .click() on it programmatically.
  // A real user click always carries isTrusted === true.
  // ---------------------------------------------------------------
  var nativeClick = HTMLElement.prototype.click;
  HTMLElement.prototype.click = function () {
    if (this.tagName === 'A') {
      var href = this.getAttribute('href');
      if (this.target === '_blank' || (href && !isSameSite(href))) return;
    }
    return nativeClick.apply(this, arguments);
  };

  // ---------------------------------------------------------------
  // 4. Block off-site top-level navigation hijacks.
  // ---------------------------------------------------------------
  ['assign', 'replace'].forEach(function (method) {
    var original = Location.prototype[method];
    try {
      Location.prototype[method] = function (url) {
        if (!isSameSite(url)) return;
        return original.apply(this, arguments);
      };
    } catch (e) {}
  });

  // ---------------------------------------------------------------
  // 5. Stop ad <script>/<iframe> elements from being inserted at all.
  // ---------------------------------------------------------------
  var AD_URL_RE = new RegExp(
    'doubleclick|googlesyndication|googleadservices|googletagmanager|' +
    'adservice|adnxs|adsterra|popads|popcash|propellerads|onclick(algo|max)|' +
    'exoclick|exosrv|juicyads|hilltopads|clickadu|adcash|ad-?maven|' +
    'trafficjunky|trafficstars|taboola|outbrain|mgid|revcontent|criteo|' +
    'pubmatic|rubiconproject|openx|amazon-adsystem|zeropark|voluum|' +
    '/ads?/|/adserver|/adsbygoogle|/popunder|/prebid|/gpt\\.js',
    'i'
  );

  function isAdNode(node) {
    if (!node || node.nodeType !== 1) return false;
    var tag = node.tagName;
    if (tag !== 'SCRIPT' && tag !== 'IFRAME' && tag !== 'EMBED' && tag !== 'OBJECT') return false;
    var src = node.src || node.getAttribute('src') || node.getAttribute('data') || '';
    return !!src && AD_URL_RE.test(src);
  }

  ['appendChild', 'insertBefore', 'replaceChild'].forEach(function (method) {
    var original = Node.prototype[method];
    Node.prototype[method] = function (node) {
      if (isAdNode(node)) return node;
      return original.apply(this, arguments);
    };
  });

  // ---------------------------------------------------------------
  // 6. Cosmetic pass: remove leftover ad containers and full-screen
  // overlay interstitials, now and on every DOM mutation.
  // ---------------------------------------------------------------
  var COSMETIC = [
    '[id^="ad-"]', '[id^="ads-"]', '[id^="ad_"]', '[id*="-ad-"]', '[id*="advert"]',
    '[class^="ad-"]', '[class*=" ad-"]', '[class*="advert"]',
    '[class*="banner-ad"]', '[class*="ad-banner"]', '[class*="ad-container"]',
    '[class*="ad-wrapper"]', '[class*="ad-slot"]', '[class*="sponsored"]',
    '[data-ad-slot]', '[data-ad-client]', '[data-adunit]',
    'ins.adsbygoogle', '.ad-unit', '.adsbox', '.ad-placeholder', '#ad-overlay'
  ].join(',');

  // Selector-based removal only. This is a single compound querySelectorAll,
  // which the engine answers from its selector index -- cheap.
  function sweepCheap() {
    try {
      document.querySelectorAll(COSMETIC).forEach(function (el) { el.remove(); });
      document.querySelectorAll('iframe[src],embed[src],object[data]').forEach(function (el) {
        var src = el.getAttribute('src') || el.getAttribute('data') || '';
        if (src && AD_URL_RE.test(src)) el.remove();
      });
    } catch (e) {}
  }

  // Full-viewport fixed overlays that aren't the video player: interstitial
  // ads, which on a remote-only device are untappable and would trap the
  // user with no way to dismiss them.
  //
  // Kept separate and run rarely because it is the expensive half:
  // getComputedStyle() forces a style recalculation, and this used to run it
  // on every `body > div` on every DOM mutation. On a React app that
  // re-renders constantly that is a style recalc per frame, which is exactly
  // the kind of thing that makes a TV stutter.
  function sweepOverlays() {
    try {
      var vw = innerWidth, vh = innerHeight;
      var kids = document.body ? document.body.children : [];
      for (var i = 0; i < kids.length; i++) {
        var el = kids[i];
        if (el.tagName !== 'DIV') continue;
        var r = el.getBoundingClientRect();
        // Cheap geometry test first; only elements that actually cover the
        // screen are worth a getComputedStyle call.
        if (r.width < vw * 0.95 || r.height < vh * 0.95) continue;
        var cs = getComputedStyle(el);
        if (cs.position !== 'fixed') continue;
        if (parseInt(cs.zIndex || '0', 10) <= 1000) continue;
        if (el.querySelector('video')) continue;
        el.remove();
      }
    } catch (e) {}
  }

  // Debounced: coalesce a burst of mutations into one pass well after the
  // burst ends, rather than one pass per animation frame during it.
  var sweepTimer = null;
  function queueSweep() {
    if (sweepTimer) return;
    sweepTimer = setTimeout(function () {
      sweepTimer = null;
      sweepCheap();
    }, 600);
  }

  if (document.readyState !== 'loading') sweepCheap();
  document.addEventListener('DOMContentLoaded', sweepCheap);
  new MutationObserver(queueSweep).observe(document.documentElement, {
    childList: true, subtree: true
  });
  // The expensive overlay scan runs on a slow fixed cadence instead of
  // reacting to mutations at all.
  setInterval(sweepOverlays, 3000);

  // ---------------------------------------------------------------
  // 7. Defuse common anti-adblock probes so the site doesn't show a
  // "disable your ad blocker" wall in place of the content.
  // ---------------------------------------------------------------
  window.adsbygoogle = window.adsbygoogle || [];
  window.adsbygoogle.loaded = true;
  window.google_jobrunner = function () {};
  window.__ADBLOCK_DETECTED__ = false;
  window.canRunAds = true;
  window.isAdBlockActive = false;
})();
""";

/// Bridges the page's HTML5 Fullscreen API state back to Flutter.
///
/// The native `onEnterFullscreen`/`onExitFullscreen` callbacks only fire for
/// the WebView's own custom-view path (typically a `<video>` going
/// fullscreen). Sites that fullscreen a *container element* — a custom
/// player chrome wrapping the video, which is what most modern web players
/// do — change `document.fullscreenElement` without necessarily triggering
/// that native path, so Flutter would never learn about it. This listens
/// for `fullscreenchange` directly and reports both directions, and exposes
/// an exit hook for the remote's Back button.
const String kFullscreenBridgeScript = r"""
(function () {
  if (window.__riveFullscreenInit) return;
  window.__riveFullscreenInit = true;

  function report() {
    var active = !!(document.fullscreenElement || document.webkitFullscreenElement);
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('onFullscreenChange', active);
    }
  }

  ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (evt) {
    document.addEventListener(evt, report, false);
  });

  // Called from Dart when the remote's Back button is pressed while the
  // page is fullscreen.
  window.__riveExitFullscreen = function () {
    try {
      if (document.exitFullscreen) document.exitFullscreen();
      else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
      var v = document.querySelector('video');
      if (v && v.webkitExitFullscreen) v.webkitExitFullscreen();
    } catch (e) {}
  };

  // Some players only expose a fullscreen control on hover, which a D-pad
  // can never produce. Expose a programmatic entry point as a fallback.
  window.__riveRequestFullscreen = function () {
    try {
      var v = document.querySelector('video');
      var target = v ? (v.closest('[class*="player"]') || v) : document.documentElement;
      if (target.requestFullscreen) target.requestFullscreen();
      else if (target.webkitRequestFullscreen) target.webkitRequestFullscreen();
    } catch (e) {}
  };
})();
""";
