import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';

class _Probe {
  const _Probe(this.count);
  final int count;

  static _Probe fromJson(Map<String, dynamic> json) =>
      _Probe((json['projects'] as List<dynamic>).length);
}

void main() {
  group('GlobalResponse', () {
    test('parses a bare daemon payload when withDataKey is false', () {
      final response = GlobalResponse<_Probe>.fromJson(
        {
          'projects': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        },
        fromJsonT: _Probe.fromJson,
        withDataKey: false,
      );

      expect(response.data?.count, 2);
    });

    test('throws MappingFailure when the payload shape is wrong', () {
      expect(
        () => GlobalResponse<_Probe>.fromJson(
          {'projects': 'not-a-list'},
          fromJsonT: _Probe.fromJson,
          withDataKey: false,
        ),
        throwsA(isA<MappingFailure>()),
      );
    });
  });
}
