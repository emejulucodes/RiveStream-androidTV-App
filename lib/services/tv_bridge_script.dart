/// Injected into every page load of rivestream.app so that a website built
/// for mouse/touch input becomes usable with an Android TV remote.
///
/// IMPORTANT: this script does NOT listen for key events. Key handling was
/// originally done here with a `keydown` listener and did not work on real
/// hardware: the WebView is a platform view, so Android delivers D-pad
/// events to whichever native view has focus, and the page's listener
/// generally never fired. Keys are now intercepted in MainActivity and
/// forwarded to Dart, which calls the functions below. See MainActivity.kt.
///
/// Coordinates crossing this bridge are *fractions* of the viewport (0..1),
/// never pixels. Flutter's logical pixels and the page's CSS pixels do not
/// correspond: measured on a 1920x1080 TV, the desktop user agent gives the
/// page a 960x540 layout viewport. Fractions are the only mapping that
/// survives whatever scale the page ends up at.
///
/// Measured page structure (rivestream.app, Next.js) that the code below is
/// built around:
///   * The document itself does NOT scroll (scrollHeight == clientHeight).
///     The main scroller is an inner `div` ~4400px tall.
///   * There are ~14 nested scrollers, including per-row horizontal
///     carousels ~3500px wide and a vertical navbar rail.
///   * Movie cards are real `<a>` elements, so they are focusable; the
///     navbar is ~14 icon links of about 21x27px with no text.
const String kTvBridgeScript = r"""
(function () {
  if (window.__rivestreamTvInit) return;
  window.__rivestreamTvInit = true;

  var style = document.createElement('style');
  style.textContent =
    '*:focus { outline: 3px solid #FF2E92 !important; outline-offset: 2px !important; }' +
    '.rive-cursor-hover { outline: 3px solid #FF2E92 !important; outline-offset: 2px !important; }' +
    'html, body { cursor: none !important; }';
  document.head.appendChild(style);

  function isVisible(el) {
    try {
      var r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return false;
      var cs = window.getComputedStyle(el);
      return !(cs.visibility === 'hidden' || cs.display === 'none' || cs.opacity === '0');
    } catch (e) { return false; }
  }

  // `iframe` is included so an embedded player is reachable at all; it is
  // activated by a native tap rather than a synthetic click (see Dart side).
  var FOCUSABLE_SELECTOR =
    'a[href], button, input, select, textarea, video, iframe, ' +
    '[tabindex]:not([tabindex="-1"]), [contenteditable="true"], [role="button"]';

  function focusableElements() {
    return Array.prototype.filter.call(
      document.querySelectorAll(FOCUSABLE_SELECTOR),
      function (el) { return !el.disabled && isVisible(el); }
    );
  }

  function toPixels(fx, fy) {
    return { x: Math.round(fx * window.innerWidth), y: Math.round(fy * window.innerHeight) };
  }

  function fire(el, type, x, y, extra) {
    var init = {
      bubbles: true, cancelable: true, view: window,
      clientX: x, clientY: y, button: 0, buttons: extra === 'down' ? 1 : 0
    };
    try { el.dispatchEvent(new MouseEvent(type, init)); } catch (e) {}
  }

  // Reports the focused element back to Dart as viewport fractions, so the
  // highlight can be drawn by Flutter on top of the WebView. Relying on the
  // CSS `:focus` outline alone is not enough -- on this site the focusable
  // navbar icons live inside a clipped scroller, so the outline is cropped
  // or too small to see from a couch.
  function describe(el) {
    if (!el) return null;
    var r = el.getBoundingClientRect();
    return JSON.stringify({
      x: r.left / window.innerWidth,
      y: r.top / window.innerHeight,
      w: r.width / window.innerWidth,
      h: r.height / window.innerHeight,
      // Dart needs the tag to know when a synthetic click is useless: an
      // <iframe> holds a separate, cross-origin document, so activating it
      // requires a real touch event dispatched natively instead.
      tag: el.tagName,
      editable: (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' ||
                 el.isContentEditable === true),
      label: (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 60)
    });
  }

  function scrollableAxes(el) {
    var cs;
    try { cs = getComputedStyle(el); } catch (e) { return { x: false, y: false }; }
    var oy = cs.overflowY, ox = cs.overflowX;
    return {
      y: (oy === 'auto' || oy === 'scroll' || oy === 'overlay') && el.scrollHeight > el.clientHeight + 1,
      x: (ox === 'auto' || ox === 'scroll' || ox === 'overlay') && el.scrollWidth > el.clientWidth + 1
    };
  }

  // Brings `el` into view by nudging each scrollable ancestor the *minimum*
  // amount needed, innermost first.
  //
  // scrollIntoView() is deliberately not used: with `block:'center',
  // inline:'center'` it recentres every ancestor at once, which on this page
  // means the horizontal carousel, the tall main container and the navbar
  // rail all jump simultaneously; and `behavior:'smooth'` queues an
  // animation per keypress, so held presses turn into a pile-up.
  function revealMinimally(el) {
    var pad = 28;
    var node = el.parentElement;
    while (node && node !== document.body && node !== document.documentElement) {
      var axes = scrollableAxes(node);
      if (axes.x || axes.y) {
        var pr = node.getBoundingClientRect();
        var er = el.getBoundingClientRect();
        if (axes.y) {
          if (er.top < pr.top + pad) node.scrollTop -= (pr.top + pad - er.top);
          else if (er.bottom > pr.bottom - pad) node.scrollTop += (er.bottom - (pr.bottom - pad));
        }
        if (axes.x) {
          if (er.left < pr.left + pad) node.scrollLeft -= (pr.left + pad - er.left);
          else if (er.right > pr.right - pad) node.scrollLeft += (er.right - (pr.right - pad));
        }
      }
      node = node.parentElement;
    }
    // Finally the document, for the rare page that scrolls at the top level.
    var er2 = el.getBoundingClientRect();
    if (er2.top < pad) window.scrollBy(0, er2.top - pad);
    else if (er2.bottom > window.innerHeight - pad) {
      window.scrollBy(0, er2.bottom - (window.innerHeight - pad));
    }
  }

  // Spatial ("directional") navigation rather than DOM order. DOM order on
  // this site runs navbar -> hero -> every card of every row, so stepping
  // sequentially jumps across the screen unpredictably. Picking the nearest
  // element in the pressed direction is what makes a grid of cards behave
  // the way a TV user expects.
  function pickInDirection(dir) {
    var items = focusableElements();
    if (!items.length) return null;
    var cur = document.activeElement;
    if (!cur || cur === document.body || items.indexOf(cur) === -1) return pickInitial();

    var cr = cur.getBoundingClientRect();
    var ccx = cr.left + cr.width / 2, ccy = cr.top + cr.height / 2;
    var horizontal = (dir === 'left' || dir === 'right');
    var best = null, bestScore = Infinity;

    items.forEach(function (el) {
      if (el === cur) return;
      var r = el.getBoundingClientRect();
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      var dx = cx - ccx, dy = cy - ccy;

      var primary, secondary, overlap;
      if (horizontal) {
        if (dir === 'left' ? dx > -4 : dx < 4) return;
        primary = Math.abs(dx);
        secondary = Math.abs(dy);
        overlap = Math.min(r.bottom, cr.bottom) - Math.max(r.top, cr.top);
        // Leaving the current row sideways is almost never intended.
        if (overlap <= 0) secondary += 1000;
      } else {
        if (dir === 'up' ? dy > -4 : dy < 4) return;
        primary = Math.abs(dy);
        secondary = Math.abs(dx);
        overlap = Math.min(r.right, cr.right) - Math.max(r.left, cr.left);
        // Prefer staying in roughly the same column, but allow changing.
        if (overlap <= 0) secondary += 250;
      }
      var score = primary + secondary * 2;
      if (score < bestScore) { bestScore = score; best = el; }
    });
    return best;
  }

  function pickInitial() {
    var items = focusableElements();
    if (!items.length) return null;
    var inView = items.filter(function (el) {
      var r = el.getBoundingClientRect();
      return r.bottom > 0 && r.top < window.innerHeight &&
             r.right > 0 && r.left < window.innerWidth;
    });
    var pool = inView.length ? inView : items;
    // Prefer something substantial (a card) over a 21x27 navbar icon.
    var big = pool.filter(function (el) {
      var r = el.getBoundingClientRect();
      return r.width * r.height >= 1500;
    });
    var chosen = (big.length ? big : pool).slice();
    chosen.sort(function (a, b) {
      var ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
      return (ra.top - rb.top) || (ra.left - rb.left);
    });
    return chosen[0];
  }

  function isMostlyInView(el) {
    var r = el.getBoundingClientRect();
    var area = r.width * r.height;
    if (area <= 0) return false;
    var ix = Math.max(0, Math.min(r.right, window.innerWidth) - Math.max(r.left, 0));
    var iy = Math.max(0, Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0));
    return (ix * iy) / area >= 0.5;
  }

  function focusAndDescribe(el) {
    if (!el) return null;
    var previous = document.activeElement;
    try { el.focus({ preventScroll: true }); } catch (e) {}
    revealMinimally(el);
    // A candidate can be in the right direction yet impossible to bring on
    // screen -- e.g. a card in a carousel that is already scrolled to its
    // end. Stranding the highlight off-screen looks like the remote has
    // stopped responding, so undo and let the caller scroll instead.
    if (!isMostlyInView(el)) {
      try {
        if (previous && previous.focus) previous.focus({ preventScroll: true });
      } catch (e) {}
      return null;
    }
    return describe(el);
  }

  window.__riveFocusFirst = function () {
    return focusAndDescribe(pickInitial());
  };

  // Returns the newly focused element's rect, or null if the press could not
  // move focus (Dart then falls back to scrolling the page).
  window.__riveMoveFocus = function (dir) {
    return focusAndDescribe(pickInDirection(dir));
  };

  window.__riveFocusedRect = function () {
    var el = document.activeElement;
    if (!el || el === document.body) return null;
    return describe(el);
  };

  window.__riveClickFocused = function () {
    var el = document.activeElement;
    if (!el || el === document.body) return null;
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return describe(el);
    var r = el.getBoundingClientRect();
    var x = r.left + r.width / 2, y = r.top + r.height / 2;
    fire(el, 'mousedown', x, y, 'down');
    fire(el, 'mouseup', x, y);
    if (typeof el.click === 'function') el.click();
    return describe(el);
  };

  // ---------------------------------------------------------------
  // POINTER MODE: hover/click at an arbitrary point.
  // A real hover is dispatched (not just a click) because many menus
  // only reveal their contents on mouseover.
  // ---------------------------------------------------------------
  var lastHovered = null;

  window.__riveHoverAt = function (fx, fy) {
    var p = toPixels(fx, fy);
    var el = document.elementFromPoint(p.x, p.y);
    if (!el) return;
    if (el !== lastHovered) {
      if (lastHovered) {
        fire(lastHovered, 'mouseout', p.x, p.y);
        fire(lastHovered, 'mouseleave', p.x, p.y);
        lastHovered.classList.remove('rive-cursor-hover');
      }
      fire(el, 'mouseover', p.x, p.y);
      fire(el, 'mouseenter', p.x, p.y);
      var actionable = el.closest ? el.closest(FOCUSABLE_SELECTOR) : null;
      if (actionable) actionable.classList.add('rive-cursor-hover');
      lastHovered = actionable || el;
    }
    fire(el, 'mousemove', p.x, p.y);
  };

  // True when the point lands on an embedded frame. For a cross-origin
  // <iframe>, elementFromPoint returns the frame element itself -- the
  // parent document cannot see inside it -- which is precisely why a
  // synthetic click there does nothing and Dart must tap natively instead.
  // Classifies what is under a point so Dart knows whether a synthetic
  // click will do, or whether the press has to be a real touch event.
  //
  //   'iframe' -- cross-origin document, unreachable from the top frame.
  //   'text'   -- a text-entry field. Focusing one from JavaScript does
  //               NOT raise the Android keyboard: WebView only asks for the
  //               IME when it handles a genuine touch itself, exactly as a
  //               browser ignores a programmatic focus() on mobile. So a
  //               text field needs a real tap too, or the user gets a
  //               focused input and no way to type into it.
  //   'other'  -- the synthetic click path is fine.
  window.__riveHitKind = function (fx, fy) {
    var p = toPixels(fx, fy);
    var el = document.elementFromPoint(p.x, p.y);
    if (!el) return 'other';
    if (el.tagName === 'IFRAME' || (el.closest && el.closest('iframe'))) {
      return 'iframe';
    }
    var field = el.closest
      ? el.closest('input, textarea, [contenteditable="true"]')
      : null;
    if (field) {
      if (field.tagName === 'INPUT') {
        var type = (field.getAttribute('type') || 'text').toLowerCase();
        // Buttons/checkboxes are <input> too but take no typed text.
        var noKeyboard = ['button', 'submit', 'reset', 'checkbox', 'radio',
                          'range', 'color', 'file', 'image'];
        if (noKeyboard.indexOf(type) !== -1) return 'other';
      }
      return 'text';
    }
    return 'other';
  };

  window.__riveClickAt = function (fx, fy) {
    var p = toPixels(fx, fy);
    var el = document.elementFromPoint(p.x, p.y);
    if (!el) return;
    var target = (el.closest && el.closest(FOCUSABLE_SELECTOR)) || el;
    try { target.focus({ preventScroll: true }); } catch (e) {}
    fire(el, 'mousedown', p.x, p.y, 'down');
    fire(el, 'mouseup', p.x, p.y);
    fire(el, 'click', p.x, p.y);
    if (target !== el && typeof target.click === 'function') target.click();
  };

  // Scrolls whatever is actually scrollable under a point.
  //
  // window.scrollBy() alone is not enough: on this site the document does
  // not scroll at all -- the real scroller is an inner container, and the
  // rows are separate horizontal scrollers. So walk up from the element at
  // that point and scroll the first ancestor that both can scroll on this
  // axis AND still has room left in that direction; the "room left" test is
  // what lets an exhausted inner container hand off to the page behind it.
  function canScroll(el, dx, dy) {
    if (!el || el.nodeType !== 1) return false;
    var axes = scrollableAxes(el);
    if (dy !== 0 && axes.y) {
      if (dy < 0 && el.scrollTop > 1) return true;
      if (dy > 0 && el.scrollTop + el.clientHeight < el.scrollHeight - 1) return true;
    }
    if (dx !== 0 && axes.x) {
      if (dx < 0 && el.scrollLeft > 1) return true;
      if (dx > 0 && el.scrollLeft + el.clientWidth < el.scrollWidth - 1) return true;
    }
    return false;
  }

  window.__riveScrollBy = function (fx, fy, fdx, fdy) {
    var dx = Math.round(fdx * window.innerWidth);
    var dy = Math.round(fdy * window.innerHeight);
    if (!dx && !dy) return false;

    var p = toPixels(fx, fy);
    var el = document.elementFromPoint(p.x, p.y);
    while (el && el !== document.body && el !== document.documentElement) {
      if (canScroll(el, dx, dy)) {
        el.scrollBy({ left: dx, top: dy, behavior: 'auto' });
        return true;
      }
      el = el.parentElement;
    }
    var se = document.scrollingElement || document.documentElement;
    var beforeY = se.scrollTop, beforeX = se.scrollLeft;
    window.scrollBy({ left: dx, top: dy, behavior: 'auto' });
    return se.scrollTop !== beforeY || se.scrollLeft !== beforeX;
  };

  // Scrolls the largest scroller containing the focused element. Used by tab
  // mode when a press finds no element in that direction, so the remote can
  // still reach content that has not been rendered/reached yet.
  window.__riveScrollFocusContainer = function (fdx, fdy) {
    var dx = Math.round(fdx * window.innerWidth);
    var dy = Math.round(fdy * window.innerHeight);
    var el = document.activeElement;
    var node = (el && el !== document.body) ? el.parentElement : null;
    while (node && node !== document.body && node !== document.documentElement) {
      if (canScroll(node, dx, dy)) {
        node.scrollBy({ left: dx, top: dy, behavior: 'auto' });
        return true;
      }
      node = node.parentElement;
    }
    return window.__riveScrollBy(0.5, 0.5, fdx, fdy);
  };

  window.__riveIsTextInputFocused = function () {
    var el = document.activeElement;
    if (!el) return false;
    return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable === true;
  };

  // ---------------------------------------------------------------
  // Video play/pause state -> Flutter, used to hold the wake lock.
  // ---------------------------------------------------------------
  function bindVideo(video) {
    if (video.__rivestreamBound) return;
    video.__rivestreamBound = true;
    video.addEventListener('play', function () {
      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onVideoPlayState', true);
    });
    ['pause', 'ended'].forEach(function (evt) {
      video.addEventListener(evt, function () {
        if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onVideoPlayState', false);
      });
    });
  }
  // Debounced like the ad-block sweep: this used to re-query every <video>
  // in the document on every DOM mutation, which on a constantly
  // re-rendering React page is a whole-document query per frame.
  var bindTimer = null;
  function queueBind() {
    if (bindTimer) return;
    bindTimer = setTimeout(function () {
      bindTimer = null;
      document.querySelectorAll('video').forEach(bindVideo);
    }, 500);
  }
  document.querySelectorAll('video').forEach(bindVideo);
  new MutationObserver(queueBind).observe(document.documentElement, {
    childList: true, subtree: true
  });
})();
""";

/// True when the document rendered nothing at all.
///
/// This is deliberately strict -- body missing, or body with zero child
/// elements -- so slow hydration is never mistaken for a failure. It catches
/// a real failure seen on device: rivestream.app registers a workbox service
/// worker, and once its cache is in a bad state the navigation request never
/// resolves. The load still "succeeds" (onLoadStop fires, readyState stays
/// `loading`, documentElement is null), so nothing would otherwise surface
/// the problem and the user just sees a black screen forever.
const String kPageEmptyProbe =
    '(function(){var b=document.body;'
    'if(!b)return true;return b.children.length===0;})()';

/// Drops the site's service worker and cache storage, so the next load goes
/// to the network instead of through a wedged worker.
const String kResetSiteStorageScript = r"""
(function () {
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(function (regs) {
        regs.forEach(function (r) { try { r.unregister(); } catch (e) {} });
      });
    }
  } catch (e) {}
  try {
    if (window.caches && caches.keys) {
      caches.keys().then(function (keys) {
        keys.forEach(function (k) { try { caches.delete(k); } catch (e) {} });
      });
    }
  } catch (e) {}
})();
""";
