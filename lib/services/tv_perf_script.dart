/// Strips the page's most expensive visual effects.
///
/// This is the biggest lever available to a WebView wrapper, because the
/// wrapper cannot make the site's own rendering cheaper any other way. A TV
/// box has a fraction of the GPU fill rate and memory bandwidth of a phone,
/// and rivestream.app is built for desktop: blurred backdrops, drop shadows
/// on every card, and transitions on hover across large poster grids. Each
/// of those forces the compositor to re-rasterize big screen areas.
///
/// What this removes and why:
///   * `backdrop-filter` / `filter: blur()` -- by far the worst offender.
///     A backdrop blur makes the compositor read back and blur everything
///     behind the element every frame it changes.
///   * animations and transitions -- continuous repaints. On a 10-foot UI
///     driven by a D-pad, hover/scale transitions add nothing anyway.
///   * `box-shadow` / `text-shadow` -- forces expensive off-thread painting
///     on large elements.
///   * `will-change` -- the site hints it on many elements, and each hint
///     promotes a new compositor layer, costing GPU memory. On a TV with
///     limited video memory, too many layers is worse than none.
///   * smooth scrolling -- animated scroll means a repaint per frame for
///     the whole scroller; instant scroll is one repaint.
///
/// `content-visibility: auto` is applied to off-screen sections so the
/// engine skips layout and paint for rows scrolled out of view entirely --
/// on a page with thousands of poster tiles this is a large win, and it is
/// exactly what the property exists for.
const String kTvPerfScript = r"""
(function () {
  if (window.__rivePerfInit) return;
  window.__rivePerfInit = true;

  function install() {
    if (!document.head && !document.documentElement) return;
    if (document.getElementById('rive-perf-style')) return;

    var css = [
      // Kill animation/transition work outright.
      '*,*::before,*::after{',
      '  animation-duration:0s!important;animation-delay:0s!important;',
      '  transition-duration:0s!important;transition-delay:0s!important;',
      '}',
      'html{scroll-behavior:auto!important}',
      // Expensive paint effects. Images and video keep their own filters so
      // posters still look right; it is the decorative blur that is costly.
      '*:not(img):not(video){',
      '  backdrop-filter:none!important;-webkit-backdrop-filter:none!important;',
      '  box-shadow:none!important;text-shadow:none!important;',
      '  will-change:auto!important;',
      '}',
      // Blurred hero/background layers: these are the single most expensive
      // thing on the page and are purely decorative.
      '[class*="blur"],[class*="Blur"],[style*="blur"]{filter:none!important}',
      // Let the engine skip off-screen rows entirely. contain-intrinsic-size
      // keeps the scrollbar stable by reserving a plausible height.
      '[class*="ListSection"],[class*="listSection"],[class*="Section"] > [class*="row"]{',
      '  content-visibility:auto;contain-intrinsic-size:auto 320px;',
      '}',
      // The site renders its own cursor affordances we never use.
      'html,body{cursor:none!important}'
    ].join('');

    var style = document.createElement('style');
    style.id = 'rive-perf-style';
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
  }

  install();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install);
  }

  // Decoding a full-resolution poster on the main thread janks scrolling.
  // `decoding=async` hands it to a background thread, and `loading=lazy`
  // stops off-screen posters being fetched and decoded at all. Applied on a
  // slow cadence so it never competes with rendering.
  function tuneImages() {
    try {
      var imgs = document.querySelectorAll('img:not([data-rive-tuned])');
      for (var i = 0; i < imgs.length && i < 120; i++) {
        var img = imgs[i];
        img.setAttribute('data-rive-tuned', '1');
        img.decoding = 'async';
        if (!img.loading || img.loading === 'eager') img.loading = 'lazy';
      }
    } catch (e) {}
  }
  tuneImages();
  setInterval(tuneImages, 2500);
})();
""";
