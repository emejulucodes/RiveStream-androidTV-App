# RiveStream TV

An Android TV client for [rivestream.app](https://www.rivestream.app), built with Flutter.

The site is a desktop-oriented Next.js web app. This project wraps it in a WebView and adds
everything a TV needs and the site does not have: remote (D-pad) navigation, a 10-foot UI,
ad and popup blocking, fullscreen video handling, and a set of performance measures that keep
a low-powered TV box responsive.

> **Scope, honestly stated:** this is a wrapper, not a native client. The site's own rendering
> is the performance floor. A lot of work here goes into removing overhead — both the wrapper's
> and the site's — but it cannot become a native Leanback app. See
> [Known limitations](#known-limitations).

---

## Contents

- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Features](#features)
- [Settings](#settings)
- [Architecture](#architecture)
- [Design decisions that are not obvious](#design-decisions-that-are-not-obvious)
- [Performance](#performance)
- [Testing](#testing)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

---

## Requirements

| Tool | Version used |
|---|---|
| Flutter | 3.44.8 (stable) |
| Dart SDK | ^3.12.2 |
| Android Gradle Plugin | 9.0.1 |
| Gradle | 9.1.0 |
| Kotlin | 2.3.20 |
| JDK | 17+ |

**Target devices:** Android TV, `minSdk 21`, landscape only. Verified against an
Android TV emulator (`Television_1080p`, API 36) and reported working on real TV hardware.

### One-time dependency patch

`flutter_inappwebview_android` 1.1.3 does not build under AGP 9 — its Gradle script calls
`getDefaultProguardFile('proguard-android.txt')`, which AGP 9 rejects because it implies
`-dontoptimize`.

Until upstream fixes it, patch the copy in your pub cache:

```bash
sed -i '' "s/getDefaultProguardFile('proguard-android.txt')/getDefaultProguardFile('proguard-android-optimize.txt')/g" ~/.pub-cache/hosted/pub.dev/flutter_inappwebview_android-1.1.3/android/build.gradle
```

This lives outside the repo, so it must be reapplied after `flutter pub cache repair` or on a
fresh machine. A release build fails loudly without it, so you will not ship a broken artifact
by forgetting.

---

## Build and run

```bash
flutter pub get
```

```bash
flutter run -d <device-id>
```

```bash
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk` (~47 MB).

Install and launch on a device or emulator:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

```bash
adb shell am start -n com.emejulucodes.rivestream/.MainActivity
```

### Regenerating launcher icons

Icons and the TV banner are committed, so this is only needed if the source art changes.

```bash
dart run flutter_launcher_icons
```

The Leanback banner (`android:banner`) is **not** produced by that tool — the four density
variants under `android/app/src/main/res/drawable-*/tv_banner.png` are committed directly.
Android TV's home screen shows the banner, never the launcher icon, so a missing banner means
an invisible app.

---

## Features

**TV integration**
- Leanback launcher entry (`LEANBACK_LAUNCHER`), `android.software.leanback` required,
  touchscreen explicitly not required, landscape-locked, `320×180` TV banner.
- Immersive full-screen; screen kept awake during playback via a wake lock tied to real
  `<video>` play/pause events, not merely to the app being open.

**Remote navigation** — two modes, switchable in Settings:
- **Pointer** (default): a Flutter-drawn cursor moved by the D-pad, with acceleration while
  held, edge scrolling, real hover dispatch, and a click that works over embedded players.
- **Tab focus**: spatial (directional) navigation between the page's focusable elements, with
  a Flutter-drawn highlight ring.

**Content**
- Two-layer ad blocking: network-level request blocking plus in-page DOM cleanup.
- Popup/new-tab suppression, including the synthetic-anchor popunder pattern.
- Off-site top-level navigation blocked as redirect-ad protection, with a sign-in allowlist.

**Playback**
- HTML5 fullscreen handled on both the native custom-view path and the JS
  `fullscreenchange` path.
- Back exits fullscreen rather than navigating.

**Robustness**
- Splash, load progress, offline/timeout screen with a D-pad-reachable Retry.
- Automatic recovery from a wedged service worker (see
  [Design decisions](#5-a-blank-page-that-reports-success)).
- Exit confirmation dialog with Cancel / Refresh / Settings / Exit.

---

## Settings

Reachable from the exit dialog (Back with no page history) or the offline screen.

| Setting | Default | Effect |
|---|---|---|
| **Mode** | Pointer | Pointer cursor vs. Tab focus navigation. |
| **Performance** | On | Strips the page's blur, shadows and animations. Reloads the page. |
| **Ad blocker** | On | Network + DOM ad blocking. Reloads the page. |
| **Clear cache** | — | Clears WebView cache *and* unregisters the site's service worker. |

All three toggles persist via `shared_preferences`.

---

## Architecture

```
lib/
├── main.dart                       App root; landscape lock + immersive mode
├── screens/
│   ├── home_shell.dart             State machine, remote input routing, back handling
│   └── settings_screen.dart        Settings UI
├── services/
│   ├── remote_control.dart         MethodChannel to MainActivity (keys, taps, IME)
│   ├── cursor_motion.dart          Pure pointer geometry (tested)
│   ├── nav_mode.dart               Pointer/Tab mode + persistence
│   ├── ad_block_prefs.dart         Ad blocker persistence
│   ├── perf_prefs.dart             Performance mode persistence
│   ├── ad_block_rules.dart         Network blocklists → ContentBlocker rules (tested)
│   ├── ad_block_script.dart        In-page popup/ad suppression
│   ├── tv_bridge_script.dart       D-pad bridge: focus, hover, click, scroll
│   ├── tv_perf_script.dart         Strips expensive visual effects
│   └── webview_polyfills.dart      Browser APIs WebView lacks
└── widgets/
    ├── tv_webview.dart             InAppWebView configuration + script injection
    ├── virtual_cursor.dart         Pointer overlay + CursorView model
    ├── focus_highlight.dart        Tab-mode focus ring
    ├── tv_button.dart              Shared D-pad-friendly button
    ├── exit_confirm_dialog.dart    Cancel / Refresh / Settings / Exit
    ├── app_splash.dart             In-Flutter splash
    └── offline_view.dart           Connection error + Retry

android/app/src/main/kotlin/com/emejulucodes/rivestream/
└── MainActivity.kt                 Key interception, synthetic touch, IME control
```

### How input flows

```
Remote keypress
   ↓
MainActivity.dispatchKeyEvent          ← intercepts before the view hierarchy
   ↓  MethodChannel "onKey"
HomeShell._handleRemoteKey
   ↓
   ├── overlay open?  → Flutter focus traversal (dialogs, settings)
   ├── Tab mode       → __riveMoveFocus / __riveClickFocused   (JS)
   └── Pointer mode   → cursor math → __riveHoverAt / native tap
```

The page never receives raw key events. Dart decides where every press goes.

---

## Design decisions that are not obvious

Each of these looks like an odd choice until you hit the failure it exists to prevent. They are
recorded here because the obvious alternative has already been tried and does not work.

### 1. Keys are intercepted in the Activity, not in Flutter or JavaScript

The WebView is a **platform view**, so Android delivers key events to whichever native view
holds focus — in practice the WebView, not Flutter. A page-level `keydown` listener also needs
the page to have a focused element, which a non-TV site generally does not.

`dispatchKeyEvent` runs before the event reaches the view hierarchy at all, so it works
regardless of who holds focus. Both DOWN and UP are consumed so the WebView does not also
scroll underneath.

`KEYCODE_BACK` is deliberately **not** intercepted — it is left to the normal dispatch path so
Flutter's `PopScope` keeps working.

Dialogs are driven the same way: interception stays on and Dart routes presses into Flutter's
focus system. Passing keys through to the hierarchy instead would reintroduce the original bug,
because the WebView still holds focus underneath the dialog.

### 2. Everything crossing the JS bridge is a viewport *fraction*, never a pixel

Flutter's logical pixels and the page's CSS pixels do not correspond. Measured on a 1920×1080
TV, the desktop user agent gives the page a **960×540** layout viewport. Fractions are the only
mapping that survives whatever scale the page ends up at.

### 3. Clicks on iframes and text fields are real touch events

A JS-synthesised click cannot reach inside a cross-origin `<iframe>` — `elementFromPoint`
returns the `<iframe>` element and the parent document cannot touch its contents. The site's
Embed Mode player lives in exactly such a frame, so its play button never responded.

A text field has the same problem for a different reason: a programmatic `focus()` never raises
the Android IME. WebView only builds an `InputConnection` and asks for the keyboard when it
handles a genuine touch itself.

Both are solved by dispatching a real `MotionEvent` from `MainActivity`, which goes through the
compositor and hits whatever is actually under the point.

> A native `showSoftInput(decorView)` fallback was tried and **removed**. It raises a keyboard
> with no `InputConnection`: it appears, swallows the D-pad, and types into nothing — worse than
> no keyboard. `MainActivity` now refuses to show the IME unless a real view holds focus.

### 4. Scrolling walks up to find the real scroll container

`window.scrollBy()` alone does nothing here: **the document does not scroll**
(`scrollHeight == clientHeight`). The real scroller is an inner `div` roughly 4400 px tall, and
each poster row is its own horizontal scroller ~3500 px wide — about 14 nested scrollers in all.

`__riveScrollBy` walks up from the element under the pointer and scrolls the first ancestor that
both *can* scroll on that axis and *still has room* in that direction. The "room left" test is
what lets an exhausted inner carousel hand off to the page behind it.

### 5. A blank page that reports success

The site registers a workbox service worker. Once its cache wedges, the navigation request never
resolves: `readyState` stays `loading`, `documentElement` is `null` — yet `onLoadStop` still
fires, so the app believes it loaded. The result is a permanently black screen with no error and
no retry.

A strict blank-page check (body missing or zero children, polled over 20 s) unregisters the
service worker, clears cache storage and reloads once, then surfaces the error screen. "Clear
cache" in Settings does the same, because `clearAllCache()` alone does not touch service workers
— it could not fix the one failure most likely to need it.

### 6. Tab mode uses spatial navigation, not DOM order

DOM order on this site runs navbar → hero → every card of every row. Stepping through it
sequentially jumps around the screen unpredictably, and the first 14 entries are 21×27 px navbar
icons inside a clipped scroller — so the CSS focus outline was cropped or simply invisible from a
couch.

Tab mode therefore picks the nearest element in the pressed direction, reveals it by nudging each
scrollable ancestor the *minimum* amount (never `scrollIntoView`, which recentres every ancestor
at once and queues a smooth-scroll animation per press), and the highlight is **drawn by Flutter**
over the WebView so it cannot be clipped or lost in a stacking context.

Focus never lands off-screen: if a candidate cannot be brought into view, the move is reverted and
the container scrolls instead.

### 7. The ad blocker does not run inside player frames

Embed Mode nests `cloudorchestranova.com` → `vsembed.ru`. Inside those documents *everything* is
"off-site" by the blocker's own test, so its navigation guards blocked the player's own controls
and its overlay sweep deleted the player container. Only the `window.open` stub — the actual
popunder defence — runs in subframes.

### 8. Content blocker rules are two combined regexes, not ~160

Android runs `Matcher.matches()` for **every rule on every request**, and a video session is
thousands of segment requests. Collapsing the host list and path list into one alternation each
takes that from ~160 regex evaluations per request to two.

`Matcher.matches()` also requires the pattern to consume the **entire** URL. Host patterns
without a trailing catch-all silently never fire — the host blocklist was dead code until this
was found. `test/ad_block_test.dart` guards it.

### 9. WebView lacks browser APIs, and the gaps are fatal

The site is written for a full browser. When it touches an API WebView omits, the exception
propagates into React and Next.js replaces the entire page with *"Application error: a
client-side exception has occurred"* — a missing API is a hard crash of the player page, not a
degraded feature.

Confirmed on device: `new MediaMetadata(...)` threw `ReferenceError` and killed playback. WebView
exposes `navigator.mediaSession` but **not** the `MediaMetadata` constructor, so the usual
`if ('mediaSession' in navigator)` feature check passes and the next line throws.
`webview_polyfills.dart` shims it inertly.

---

## Performance

Measured with `dumpsys gfxinfo` on the Android TV emulator, identical workload
(40 D-pad scroll presses), Performance mode off vs on:

| Metric | Off | On |
|---|---|---|
| Janky frames | 7.18 % | **2.46 %** |
| 90th pct frame | 44 ms | **25 ms** |
| 95th pct frame | 53 ms | **28 ms** |
| 99th pct frame | 89 ms | **34 ms** |
| Frames rendered | 348 | **122** |

The last row matters most: the same input produced 65 % fewer frames. A mostly-static page should
not be repainting at all.

> These numbers are from an **emulator**, whose GPU is the host's. They show direction and rough
> magnitude, not what a given TV will do. The A/B also isolates only the Performance-mode toggle;
> the JS, Flutter and content-blocker work below is not separately switchable.

**What was costing the most**

- **DOM sweeps ran on every mutation** and called `getComputedStyle` on every `body > div` —
  a full style recalc per frame on a constantly re-rendering React page. Now debounced to 600 ms,
  with the expensive overlay scan on a 3 s cadence behind a cheap geometry pre-test.
- **Every cursor step called `setState`**, rebuilding the subtree including the `InAppWebView`
  widget. Under hybrid composition a Flutter repaint drags the WebView surface with it. Cursor,
  progress and focus ring now live in `ValueNotifier`s behind `RepaintBoundary`s.
- **Hover fired on every key repeat** — a platform-channel round trip plus layout-forcing JS.
  Now coalesced to ~14/s; the cursor still moves at full rate because Flutter draws it.
- **A `urlFilter: '.*'` cosmetic rule** matched every request, and the plugin responds by
  scheduling a JS injection per request. Removed; cosmetic hiding happens in the debounced sweep.

**Performance mode** additionally strips, via injected CSS: `backdrop-filter` and decorative
blur (the worst offender — forces readback and blur of everything behind the element), animations
and transitions, `box-shadow`/`text-shadow`, and `will-change` hints that each promote a
compositor layer. It adds `content-visibility: auto` so off-screen rows skip layout and paint,
and `decoding=async` + `loading=lazy` on images.

**WebView tuning:** renderer priority pinned to `IMPORTANT` (stops the launcher demoting the
renderer mid-playback), `offscreenPreRaster` off, scrollbars and overscroll off, resource/AJAX
interception hooks explicitly off, `largeHeap` in the manifest.

---

## Testing

```bash
flutter test
```

29 tests, all pure logic:

| File | Covers |
|---|---|
| `cursor_motion_test.dart` | Pointer movement, acceleration, clamping, edge-scroll thresholds |
| `ad_block_test.dart` | Full-URL match semantics, no rule blocks the player chain, no false positives on "ad"-containing words |
| `nav_mode_test.dart` | Mode round-trip, persisted key stability, `RemoteKey` ↔ Kotlin `keyName()` parity |

`HomeShell` and `TvWebView` cannot be pumped in a widget test — they build an `InAppWebView`,
which asserts a platform implementation is registered. Widget-level coverage would need
`integration_test` on a device.

### Debugging the page itself

The WebView renders into a hybrid-composition surface, so page-level problems are best diagnosed
through logs rather than screenshots. `TvWebView` forwards page console output to
`flutter run` under `kDebugMode`:

```bash
flutter run -d emulator-5554 --debug 2>&1 | grep '\[web\]'
```

---

## Known limitations

- **It is a WebView.** The site's rendering is the performance floor. Further gains would require
  visually lossy measures (capping poster resolution, killing the hero video, forcing a smaller
  layout viewport).
- **The ad host list is static.** Ad networks rotate domains, so it drifts and needs periodic
  updates. It is not equivalent to a continuously updated filter list.
- **First-party ads cannot be distinguished by URL** from site content, so they are only caught
  by the cosmetic layer.
- **Off-site navigation blocking is a real risk.** If the site moves domain, or uses a sign-in
  provider outside `kNavigationAllowedHosts`, clicks will appear dead. That list is the first
  place to look.
- **Spatial navigation is tuned to the current layout.** A redesign could change what "nearest in
  direction" picks.
- **The tab-mode highlight is positioned from `getBoundingClientRect`**, so a card that animates
  on hover can lead the ring by a frame.
- **IME behaviour varies by TV.** Verified against Gboard on the emulator; a different leanback
  IME may position itself differently.
- Release builds are signed with the **debug key** (`android/app/build.gradle.kts`). Configure a
  real signing config before distributing.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Release build fails on `getDefaultProguardFile` | The pub-cache patch is missing — see [Requirements](#one-time-dependency-patch). |
| Permanently black screen | Wedged service worker. Should self-heal in ~20 s; otherwise Settings → Clear cache, or `adb shell pm clear com.emejulucodes.rivestream`. |
| Video will not load / retry loop | Settings → **Ad blocker: Off**, then reload. If that fixes it, a blocklist entry is over-matching. |
| Play button does nothing on an embed | The embed is a cross-origin iframe; activation needs the native tap path. Check `__riveHitKind` is returning `iframe`. |
| Keyboard does not appear | The field must be reached by a real tap. Confirm with `adb shell dumpsys input_method \| grep mInputShown` — if it reports shown but typing does nothing, the IME has no `InputConnection`. |
| Remote does nothing | Interception may be stuck off after text entry. Press Back to reclaim it. |
| App missing from the TV home screen | The Leanback banner or `LEANBACK_LAUNCHER` category is missing. |

---

## Maintenance

**Ad blocklists** — `kBlockedHosts` and `kBlockedPathPatterns` in `ad_block_rules.dart`. Add
hosts as bare domains (subdomains are matched automatically). Path patterns must be anchored on a
path or word boundary: naive substrings like `ad` match `loader.js`, `upload` and `header`, and
there is a test asserting they do not.

**Navigation allowlist** — `kNavigationAllowedHosts` in the same file.

**Remote keys** — `keyName()` in `MainActivity.kt` and the `RemoteKey` enum must stay in sync;
a test asserts it.

**Pointer feel** — the constants at the top of `CursorMotion` (`stepMin`, `stepMax`, `edgeMargin`,
scroll fractions, acceleration).

**Page structure assumptions** — the measured facts this code relies on (viewport size, scroller
layout, focusable counts) are documented at the top of `tv_bridge_script.dart`. If the site is
redesigned, re-measure before adjusting the navigation logic.
