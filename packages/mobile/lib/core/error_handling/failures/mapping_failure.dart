part of 'failure.dart';

class MappingFailure extends Failure {
  MappingFailure({
    required Object error,
    required StackTrace stacktrace,
    super.message = 'Something went wrong',
    super.statusCode = StatusCode.mappingFailure,
    super.apiStatus,
  }) {
    AppLogger.error(error, failure: this, stacktrace: stacktrace);
  }

  @override
  List<Object?> get props => [message, statusCode, apiStatus];
}
