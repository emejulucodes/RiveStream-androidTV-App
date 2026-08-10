import 'package:flutter_test/flutter_test.dart';
import 'package:rivestream/services/ad_block_rules.dart';

// Note: HomeShell/TvWebView can't be pumped in a plain unit test -- they
// build an InAppWebView, which asserts that a platform implementation is
// registered. That only happens on a real device/emulator, so widget-level
// coverage belongs in integration_test, not here. These tests cover the
// pure logic the ad blocker depends on.

void main() {
  group('isNavigationAllowed', () {
    test('allows the site itself and its subdomains', () {
      expect(isNavigationAllowed('https://www.rivestream.app'), isTrue);
      expect(isNavigationAllowed('https://rivestream.app/watch/123'), isTrue);
      expect(isNavigationAllowed('http://cdn.rivestream.app/a.js'), isTrue);
    });

    test('allows sign-in providers so login flows are not mistaken for ads', () {
      expect(isNavigationAllowed('https://accounts.google.com/signin'), isTrue);
      expect(isNavigationAllowed('https://challenges.cloudflare.com/turnstile'), isTrue);
    });

    test('blocks off-site redirect targets', () {
      expect(isNavigationAllowed('https://popads.net/landing'), isFalse);
      expect(isNavigationAllowed('https://some-random-ad.example/win'), isFalse);
    });

    test('is not fooled by a lookalike host suffix', () {
      expect(isNavigationAllowed('https://rivestream.app.evil.com/x'), isFalse);
      expect(isNavigationAllowed('https://notrivestream.app/x'), isFalse);
    });

    test('rejects empty, malformed and non-web schemes', () {
      expect(isNavigationAllowed(null), isFalse);
      expect(isNavigationAllowed(''), isFalse);
      expect(isNavigationAllowed('javascript:alert(1)'), isFalse);
      expect(isNavigationAllowed('intent://scan/#Intent;scheme=zxing;end'), isFalse);
    });
  });

  group('buildAdBlockRules', () {
    final rules = buildAdBlockRules();

    // Combined into two alternations on purpose: Android runs every rule's
    // regex against every request, so rule count is per-request CPU cost.
    test('collapses to two rules regardless of list size', () {
      expect(rules.length, 2);
      expect(kBlockedHosts.length, greaterThan(100));
    });

    // The Android implementation tests rules with Matcher.matches(), which
    // only fires when the pattern consumes the whole URL. A pattern that
    // merely matches a prefix silently never blocks anything.
    bool fullyMatches(String pattern, String url) {
      final m = RegExp(pattern, caseSensitive: false).firstMatch(url);
      return m != null && m.start == 0 && m.end == url.length;
    }

    test('host rules match the ENTIRE url, not just its prefix', () {
      expect(fullyMatches(combinedHostPattern, 'https://doubleclick.net'), isTrue);
      expect(
        fullyMatches(combinedHostPattern, 'https://static.doubleclick.net/gpt/x.js?a=1'),
        isTrue,
      );
      expect(fullyMatches(combinedHostPattern, 'https://example.com/x'), isFalse);
    });

    test('no rule blocks the embed player chain', () {
      const playerUrls = [
        'https://ataraxiaoftheapex.space/generate.php',
        'https://ataraxiaoftheapex.space/pl/H4sIAAAAAAAAAxXOyXKCMAAA0F8iCVs64/master.m3u8',
        'https://cloudorchestranova.com/',
        'https://vsembed.ru/embed/movie/1284041',
        'https://vsrc.su/embed/movie/1339713',
      ];
      for (final url in playerUrls) {
        for (final rule in rules) {
          expect(
            fullyMatches(rule.trigger.urlFilter, url),
            isFalse,
            reason: '$url blocked by ${rule.trigger.urlFilter}',
          );
        }
      }
    });

    test('host patterns match the domain and its subdomains, not lookalikes', () {
      final re = RegExp('^(?:$combinedHostPattern)' r'$', caseSensitive: false);

      expect(re.hasMatch('https://doubleclick.net/gpt'), isTrue);
      expect(re.hasMatch('https://static.doubleclick.net/x.js'), isTrue);
      expect(re.hasMatch('https://example.com/notdoubleclick.net'), isFalse);
    });

    test('path patterns do not match innocent words containing "ad"', () {
      final re = RegExp(combinedPathPattern, caseSensitive: false);

      expect(re.hasMatch('https://www.rivestream.app/ads/banner.js'), isTrue);
      expect(re.hasMatch('https://www.rivestream.app/ad/x.png'), isTrue);
      // These would break the site if they matched.
      expect(re.hasMatch('https://www.rivestream.app/js/loader.js'), isFalse);
      expect(re.hasMatch('https://www.rivestream.app/upload/poster.jpg'), isFalse);
      expect(re.hasMatch('https://www.rivestream.app/download/file'), isFalse);
      expect(re.hasMatch('https://www.rivestream.app/header.css'), isFalse);
    });

    test('every rule compiles as a valid regex', () {
      for (final rule in rules) {
        expect(
          () => RegExp(rule.trigger.urlFilter),
          returnsNormally,
          reason: 'invalid urlFilter: ${rule.trigger.urlFilter}',
        );
      }
    });
  });
}
