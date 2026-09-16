class SaveDesktopParams {
  const SaveDesktopParams({
    required this.name,
    required this.host,
    required this.port,
    required this.secure,
    required this.password,
  });

  final String name;
  final String host;
  final String port;
  final bool secure;
  final String password;
}
