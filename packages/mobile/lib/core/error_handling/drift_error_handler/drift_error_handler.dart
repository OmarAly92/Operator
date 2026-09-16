import 'package:operator_mobile/core/error_handling/failures/failure.dart';

extension DriftFutureErrorHandler<T> on Future<T> {
  Future<T> handleLocalFailure() async {
    try {
      return await this;
    } catch (error, stacktrace) {
      throw LocalFailure<void>(
        error: error,
        stacktrace: stacktrace,
        message: error is StateError ? error.message.toString() : 'Something went wrong',
      );
    }
  }
}

extension DriftStreamErrorHandler<T> on Stream<T> {
  Stream<T> handleLocalFailure() => handleError((Object error, StackTrace stacktrace) {
    throw LocalFailure<void>(
      error: error,
      stacktrace: stacktrace,
      message: error is StateError ? error.message.toString() : 'Something went wrong',
    );
  });
}
