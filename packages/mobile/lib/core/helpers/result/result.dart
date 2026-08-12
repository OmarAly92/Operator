import 'package:operator_mobile/core/error_handling/failures/failure.dart';

typedef FutureResult<T> = Future<Result<T, Failure>>;

/// Abstract result class
sealed class Result<T, E> {
  const Result();

  factory Result.success(T value) = _ResultSuccess<T, E>;

  factory Result.failure(E error) = _ResultFailure<T, E>;
}

/// Success state containing the value
final class _ResultSuccess<T, E> extends Result<T, E> {
  final T value;

  const _ResultSuccess(this.value);
}

/// Failure state containing a Failure object
final class _ResultFailure<T, E> extends Result<T, E> {
  final E error;

  const _ResultFailure(this.error);
}

/// Extensions on Result type for easier handling
extension ResultExtensions<T, E> on Result<T, E> {
  bool get isSuccess => this is _ResultSuccess<T, E>;

  bool get isFailure => this is _ResultFailure<T, E>;

  T getOrDefault(T defaultValue) {
    return switch (this) {
      _ResultSuccess<T, E>(:final value) => value,
      _ResultFailure<T, E>() => defaultValue,
    };
  }

  void when({
    required void Function(T data) onSuccess,
    required void Function(E failure) onFailure,
  }) => switch (this) {
    _ResultSuccess<T, E>(:final value) => onSuccess(value),
    _ResultFailure<T, E>(:final error) => onFailure(error),
  };

  String get errorMessage {
    return switch (this) {
      _ResultFailure<T, E>(:final error) => error.toString(),
      _ => '',
    };
  }
}
