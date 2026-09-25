sealed class ConnectionBackoff {
  static const Duration initial = Duration(seconds: 1);
  static const Duration ceiling = Duration(seconds: 30);
  static const Duration rateLimited = Duration(seconds: 60);

  static Duration next(Duration current) {
    final doubled = current * 2;
    return doubled > ceiling ? ceiling : doubled;
  }
}
