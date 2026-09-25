abstract class ConnectionSignals {
  Stream<void> get retries;
  bool get authFailed;
  bool get rateLimited;
}
