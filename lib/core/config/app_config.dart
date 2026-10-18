/// Compile-time configuration. Override with --dart-define, e.g.:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
class AppConfig {
  final String apiBaseUrl;

  const AppConfig({required this.apiBaseUrl});

  /// Local backend reachable on the development network.
  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://192.168.1.59:8080',
    ),
  );
}
