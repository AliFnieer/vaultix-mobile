/// Compile-time configuration. Override with --dart-define, e.g.:
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
class AppConfig {
  final String apiBaseUrl;

  const AppConfig({required this.apiBaseUrl});

  /// 10.0.2.2 = host loopback from the Android emulator.
  static const fromEnvironment = AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8080',
    ),
  );
}
