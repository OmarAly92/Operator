import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/events/cdc_cursor.dart';

void main() {
  test('a positioned cursor asks the daemon to replay after that seq', () {
    expect(const CdcCursor.at(7).queryParameters, {'after': 7});
  });

  test('a positioned cursor never asks for a negative seq', () {
    expect(const CdcCursor.at(-4).queryParameters, {'after': 0});
  });

  test('the latest cursor asks for the head instead of a replay', () {
    expect(const CdcCursor.latest().queryParameters, {'fromLatest': true});
  });

  test('the latest cursor never sends an after parameter', () {
    expect(const CdcCursor.latest().queryParameters.containsKey('after'), isFalse);
  });
}
