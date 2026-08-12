import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/dio_error_handler/status_code.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';

void main() {
  group('Result', () {
    test('success carries its value through when', () {
      final Result<int, Failure> result = Result.success(7);
      var seen = 0;
      result.when(onSuccess: (value) => seen = value, onFailure: (_) => seen = -1);
      expect(seen, 7);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('failure carries its failure through when', () {
      final failure = ServerFailure.noNetwork();
      final Result<int, Failure> result = Result.failure(failure);
      Failure? seen;
      result.when(onSuccess: (_) {}, onFailure: (error) => seen = error);
      expect(seen, same(failure));
      expect(result.getOrDefault(3), 3);
    });

    test('noNetwork carries the offline status code', () {
      expect(ServerFailure.noNetwork().statusCode, StatusCode.noInternetConnection);
    });
  });
}
