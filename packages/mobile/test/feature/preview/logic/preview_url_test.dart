import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/preview/logic/preview_url.dart';

void main() {
  group('mobileReachablePreviewUrl', () {
    test('rewrites a loopback host to the daemon host the phone can reach', () {
      expect(
        mobileReachablePreviewUrl('http://localhost:5173/', '10.0.0.5')?.toString(),
        'http://10.0.0.5:5173/',
      );
      expect(
        mobileReachablePreviewUrl('http://127.0.0.1:3000/app', '10.0.0.5')?.toString(),
        'http://10.0.0.5:3000/app',
      );
    });

    test('brackets an IPv6 daemon host', () {
      expect(
        mobileReachablePreviewUrl('http://localhost:5173/', 'fd7a::1')?.toString(),
        'http://[fd7a::1]:5173/',
      );
    });

    test('leaves a already-reachable host alone', () {
      expect(
        mobileReachablePreviewUrl('https://preview.example.com/x', '10.0.0.5')?.toString(),
        'https://preview.example.com/x',
      );
    });

    test('refuses anything that is not http or https', () {
      expect(mobileReachablePreviewUrl('file:///etc/passwd', '10.0.0.5'), isNull);
      expect(mobileReachablePreviewUrl('javascript:alert(1)', '10.0.0.5'), isNull);
    });

    test('returns nothing for a missing, empty or unparseable URL', () {
      expect(mobileReachablePreviewUrl(null, '10.0.0.5'), isNull);
      expect(mobileReachablePreviewUrl('', '10.0.0.5'), isNull);
      expect(mobileReachablePreviewUrl('http://localhost:5173/', ''), isNull);
    });
  });

  group('previewWorthShowing', () {
    // The detector's markdown fallback matches a repo README on a fresh
    // checkout, so the globe's dot must not treat that as "the agent made
    // something to look at".
    test('ignores a bare repo README', () {
      expect(previewWorthShowing('README.md'), isFalse);
      expect(previewWorthShowing('docs/readme.markdown'), isFalse);
    });

    test('accepts anything the agent actually produced', () {
      expect(previewWorthShowing('dist/index.html'), isTrue);
      expect(previewWorthShowing('plan.md'), isTrue);
    });

    test('treats a missing entry as nothing to show', () {
      expect(previewWorthShowing(null), isFalse);
      expect(previewWorthShowing('   '), isFalse);
    });
  });

  test('normalizePreviewHost strips a pasted scheme and trailing slashes', () {
    expect(normalizePreviewHost('  http://10.0.0.5/  '), '10.0.0.5');
    expect(normalizePreviewHost('10.0.0.5'), '10.0.0.5');
  });
}
