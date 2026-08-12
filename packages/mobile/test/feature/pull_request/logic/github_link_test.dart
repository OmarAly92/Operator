import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/pull_request/logic/github_link.dart';

void main() {
  group('githubAppUrl', () {
    test('maps a repo URL', () {
      expect(githubAppUrl('https://github.com/OmarAly92/operator'), 'github://repo/OmarAly92/operator');
    });

    test('maps a pull request URL', () {
      expect(githubAppUrl('https://github.com/o/r/pull/184'), 'github://repo/o/r/pull/184');
    });

    test('maps an issue URL', () {
      expect(githubAppUrl('https://github.com/o/r/issues/12'), 'github://repo/o/r/issues/12');
    });

    test('tolerates www, http, trailing slashes and query strings', () {
      expect(githubAppUrl('http://www.github.com/o/r/'), 'github://repo/o/r');
      expect(githubAppUrl('https://github.com/o/r/pull/9?diff=split'), 'github://repo/o/r/pull/9');
      expect(githubAppUrl('  https://github.com/o/r  '), 'github://repo/o/r');
    });

    test('refuses the prefilled new-issue URL', () {
      expect(githubAppUrl('https://github.com/OmarAly92/operator/issues/new?body=hello'), isNull);
      expect(githubAppUrl('https://github.com/o/r/issues/new'), isNull);
    });

    test('refuses non-github hosts', () {
      expect(githubAppUrl('https://gitlab.com/o/r'), isNull);
      expect(githubAppUrl('https://example.com/github.com/o/r'), isNull);
      expect(githubAppUrl('https://notgithub.com/o/r'), isNull);
    });

    test('refuses paths with no repo', () {
      expect(githubAppUrl('https://github.com/'), isNull);
      expect(githubAppUrl('https://github.com/onlyowner'), isNull);
    });

    test('refuses reserved roots that look like owners', () {
      expect(githubAppUrl('https://github.com/settings/profile'), isNull);
      expect(githubAppUrl('https://github.com/orgs/acme'), isNull);
    });

    test('refuses deep paths the app has no stable screen for', () {
      expect(githubAppUrl('https://github.com/o/r/blob/main/README.md'), isNull);
      expect(githubAppUrl('https://github.com/o/r/pull/184/files'), isNull);
      expect(githubAppUrl('https://github.com/o/r/pull/abc'), isNull);
    });
  });
}
