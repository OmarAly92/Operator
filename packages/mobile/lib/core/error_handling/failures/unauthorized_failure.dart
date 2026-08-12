part of 'failure.dart';

class UnauthorizedFailure<T> extends Failure<T> {
  const UnauthorizedFailure({
    super.message = 'Session expired. Please sign in again.',
    super.statusCode = 401,
    super.apiStatus,
    super.validationErrors,
  });

  @override
  List<Object?> get props => [message, statusCode, apiStatus, validationErrors];
}
