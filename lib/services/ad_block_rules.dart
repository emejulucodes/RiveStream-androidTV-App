import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Network-level ad/tracker blocking.
///
/// These rules are handed to the WebView as [ContentBlocker]s, which the
/// plugin enforces by matching each outgoing request URL against the
/// `urlFilter` regex *before* the request is made. Blocking here (rather
/// than only hiding elements with CSS) is what stops ad scripts from ever
/// executing, which is the only reliable way to kill popunders, redirect
/// ads and anti-adblock scripts on a site you don't control.
///
/// The host list is hand-maintained and deliberately conservative about
/// false positives: matching too broadly on a video-heavy site breaks
/// playback (players are often served from CDNs whose names look ad-like).
/// It is not a full EasyList-equivalent — see [kKnownLimitations] below.

/// Ad, tracker, analytics and popunder-network hosts.
/// Matched as "this domain or any subdomain of it".
const List<String> kBlockedHosts = [
  // --- Major ad exchanges / servers ---
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'google-analytics.com',
  'googletagmanager.com',
  'googletagservices.com',
  'adservice.google.com',
  'amazon-adsystem.com',
  'adnxs.com',
  'rubiconproject.com',
  'pubmatic.com',
  'openx.net',
  'criteo.com',
  'criteo.net',
  'casalemedia.com',
  'smartadserver.com',
  'adform.net',
  'sharethrough.com',
  'taboola.com',
  'outbrain.com',
  'revcontent.com',
  'mgid.com',
  'adroll.com',
  'media.net',
  'indexww.com',
  'sovrn.com',
  'gumgum.com',
  'teads.tv',
  'spotxchange.com',
  'yieldmo.com',
  'bidswitch.net',
  'agkn.com',
  '3lift.com',
  'districtm.io',
  'contextweb.com',
  'admanmedia.com',
  'adtelligent.com',
  'adkernel.com',

  // --- Popunder / redirect / "streaming site" ad networks ---
  // These are the networks most responsible for new-tab and redirect ads.
  'popads.net',
  'popcash.net',
  'popmyads.com',
  'propellerads.com',
  'propellerclick.com',
  'onclickalgo.com',
  'onclickmax.com',
  'onclckmn.com',
  'clickadu.com',
  'adsterra.com',
  'adsterracdn.com',
  'hilltopads.net',
  'hilltopads.com',
  'exoclick.com',
  'exosrv.com',
  'juicyads.com',
  'trafficjunky.net',
  'trafficstars.com',
  'tsyndicate.com',
  'adcash.com',
  'adnium.com',
  'ad-maven.com',
  'admaven.com',
  'galaksion.com',
  'adspyglass.com',
  'zeropark.com',
  'voluumtrk.com',
  'bodelen.com',
  'mybestcontent.com',
  'onesignal.com',
  'pushwoosh.com',
  'pushnami.com',
  'sekindo.com',
  'vidoomy.com',
  'aniview.com',
  'springserve.com',
  'poptm.com',
  'partnerads.ysm.yahoo.com',

  // --- Trackers / analytics / fingerprinting ---
  'scorecardresearch.com',
  'quantserve.com',
  'quantcount.com',
  'hotjar.com',
  'mixpanel.com',
  'segment.io',
  'segment.com',
  'amplitude.com',
  'fullstory.com',
  'mouseflow.com',
  'crazyegg.com',
  'clicktale.net',
  'inspectlet.com',
  'luckyorange.com',
  'yandex.ru',
  'mc.yandex.ru',
  'matomo.cloud',
  'branch.io',
  'appsflyer.com',
  'adjust.com',
  'kochava.com',
  'chartbeat.com',
  'parsely.com',
  'newrelic.com',
  'bugsnag.com',
  'sentry-cdn.com',
  'facebook.net',
  'connect.facebook.net',
  'pixel.facebook.com',
  'bat.bing.com',
  'clarity.ms',
  'ads-twitter.com',
  'analytics.tiktok.com',
  'snapchat.com/pixel',
];

/// Path/filename patterns that identify ad payloads regardless of host.
///
/// Every pattern is anchored on a path or word boundary. Naive substrings
/// like `ad` are deliberately avoided: they match innocent words such as
/// "loader.js", "upload", "download" and "header", which would break the
/// site's own assets.
const List<String> kBlockedPathPatterns = [
  r'/ads?/',
  r'/adserver',
  r'/adserve',
  r'/ad-?frame',
  r'/ad-?banner',
  r'/ad-?script',
  r'/ad-?manager',
  r'/adsbygoogle',
  r'/advert(s|ising|isement)?[./_-]',
  r'/banner-?ad',
  r'/popunder',
  r'/pop-?under',
  r'/popads',
  r'/interstitial',
  r'/prebid',
  r'/gpt\.js',
  r'/gtag/js',
  r'/analytics\.js',
  r'/ga\.js',
  r'/fbevents\.js',
  r'/pixel\.gif',
  r'/track(ing|er)?\.(js|gif|png)',
  r'/beacon\.(js|gif)',
  r'/sponsor(ed|ship)?[./_-]',
  r'/taboola',
  r'/outbrain',
];

/// CSS selectors for ad containers left behind after the network requests
/// are blocked (empty iframes, reserved ad slots that would otherwise show
/// as dead space or a broken-image box on a 10-foot screen).
const List<String> kCosmeticSelectors = [
  '[id^="ad-"]',
  '[id^="ads-"]',
  '[id^="ad_"]',
  '[id*="-ad-"]',
  '[id*="advert"]',
  '[class^="ad-"]',
  '[class*=" ad-"]',
  '[class*="advert"]',
  '[class*="banner-ad"]',
  '[class*="ad-banner"]',
  '[class*="ad-container"]',
  '[class*="ad-wrapper"]',
  '[class*="ad-slot"]',
  '[class*="sponsored"]',
  '[data-ad-slot]',
  '[data-ad-client]',
  '[data-adunit]',
  'ins.adsbygoogle',
  'iframe[src*="doubleclick"]',
  'iframe[src*="googlesyndication"]',
  'iframe[src*="adserver"]',
  'iframe[src*="/ads/"]',
  '.ad-unit',
  '.adsbox',
  '.ad-placeholder',
  '#ad-overlay',
];


/// One regex matching any blocked host, and one matching any blocked path.
///
/// These are deliberately combined rather than emitted as one rule per
/// entry. The Android side walks the whole rule list and runs
/// `Matcher.matches()` for every rule on *every* network request; a video
/// session is thousands of segment requests, so ~160 separate regexes per
/// request is real, continuous CPU. A single alternation lets the regex
/// engine share that work, taking it to two evaluations per request.
String get combinedHostPattern {
  final hosts = kBlockedHosts.map((h) => h.replaceAll('.', r'\.')).join('|');
  // The trailing group is required, not cosmetic: `Matcher.matches()` only
  // succeeds when the pattern consumes the entire URL, so a pattern that
  // stops at the host would silently never fire.
  return r'^https?://([a-z0-9-]+\.)*(?:' '$hosts' r')([:/].*)?';
}

String get combinedPathPattern {
  final paths = kBlockedPathPatterns.map((p) => '(?:$p)').join('|');
  return '.*(?:$paths).*';
}

/// Builds the full content-blocker rule set passed to the WebView.
List<ContentBlocker> buildAdBlockRules() {
  return [
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: combinedHostPattern),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ),
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: combinedPathPattern),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ),
    // No CSS_DISPLAY_NONE rule here on purpose. It needs a `urlFilter`, and
    // the only one that covers a whole page is `.*` -- which matches every
    // single request, and the Android implementation reacts by scheduling a
    // fresh `evaluateJavascript` injection for each one. While a video is
    // streaming that is hundreds of injections into the top document. The
    // cosmetic hiding is done instead by the sweep in ad_block_script.dart,
    // which runs once per DOM mutation rather than once per byte fetched.
  ];
}

/// Hosts that top-level navigation is allowed to leave rivestream.app for.
/// Anything else attempting a main-frame navigation is treated as a
/// redirect ad and cancelled (see TvWebView.shouldOverrideUrlLoading).
const List<String> kNavigationAllowedHosts = [
  'rivestream.app',
  'rivestream.net',
  'rivestream.xyz',
  // OAuth / sign-in providers, so login flows are not mistaken for ads.
  'accounts.google.com',
  'google.com',
  'github.com',
  'githubusercontent.com',
  'appleid.apple.com',
  'auth0.com',
  'firebaseapp.com',
  'supabase.co',
  'cloudflare.com',
  'challenges.cloudflare.com',
];

/// Returns true if [url] may be loaded as a top-level navigation.
bool isNavigationAllowed(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  // In-page and non-web schemes are handled elsewhere; never treat them as ads.
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return kNavigationAllowedHosts.any(
    (allowed) => host == allowed || host.endsWith('.$allowed'),
  );
}

/// Documented gaps, so these are not mistaken for "everything is blocked":
///
///  * First-party ads served from rivestream.app's own domain and its own
///    paths cannot be distinguished from site content by URL alone, so
///    they are only caught by the cosmetic/JS layer, not the network layer.
///  * Ads injected directly into the HTML document (rather than fetched)
///    are likewise handled only cosmetically.
///  * This list is static. Ad networks rotate domains, so it will drift
///    and needs periodic updates; it is not equivalent to a continuously
///    updated filter list such as the ones used by desktop blockers.
const String kKnownLimitations = 'See dartdoc at end of ad_block_rules.dart';
