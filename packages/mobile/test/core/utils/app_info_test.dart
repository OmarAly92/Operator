import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/utils/app_info.dart';

void main() {
  group('formatVersion', () {
    test('combines version and build', () {
      expect(formatVersion(const BuildInfo(version: '1.2.0', build: '42')), '1.2.0 (42)');
    });

    test('omits a build number that only repeats the version', () {
      expect(formatVersion(const BuildInfo(version: '1.2.0', build: '1.2.0')), '1.2.0');
    });

    test('omits a missing or blank build number', () {
      expect(formatVersion(const BuildInfo(version: '1.2.0')), '1.2.0');
      expect(formatVersion(const BuildInfo(version: '1.2.0', build: '  ')), '1.2.0');
    });

    test('falls back rather than rendering an empty row', () {
      expect(formatVersion(const BuildInfo()), 'unknown');
      expect(formatVersion(const BuildInfo(build: '42')), 'build 42');
    });
  });

  group('bugReportBody', () {
    test('names the build and platform so a report is actionable', () {
      final body = bugReportBody(const BuildInfo(version: '1.2.0', build: '42'), 'ios', '18.2');
      expect(body, contains('Operator mobile: 1.2.0 (42)'));
      expect(body, contains('Platform: ios 18.2'));
    });

    test('leaves room above the metadata for the user to type', () {
      expect(bugReportBody(const BuildInfo(version: '1.0.0'), 'android', '34').startsWith('\n\n'), isTrue);
    });
  });
}
