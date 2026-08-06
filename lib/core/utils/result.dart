sealed class Result<T> {
  const Result();

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error, StackTrace stackTrace) onFailure,
  });
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error, StackTrace stackTrace) onFailure,
  }) => onSuccess(value);
}

final class Failure<T> extends Result<T> {
  const Failure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error, StackTrace stackTrace) onFailure,
  }) => onFailure(error, stackTrace);
}
