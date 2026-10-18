import 'package:dio/dio.dart';

/// Holds tokens in memory (access) + the injected [TokenPersistence] (refresh).
///
/// Refresh-token persistence is abstracted so unit tests need no platform
/// channels; production wiring uses flutter_secure_storage.
abstract class TokenPersistence {
  Future<void> saveRefresh(String token);
  Future<String?> readRefresh();
  Future<void> clearRefresh();
}

class TokenStore {
  final TokenPersistence _persistence;
  String? _cachedAccess;
  String? _cachedRefresh;

  // Refresh token loaded from disk at startup is kept here so hasRefresh
  // works before any in-memory update.
  String? _lastKnownRefresh;

  TokenStore(this._persistence);

  String? get cachedAccess => _cachedAccess;
  String? get refreshToken => _cachedRefresh ?? _lastKnownRefresh;
  bool get hasRefresh => refreshToken != null && refreshToken!.isNotEmpty;

  void setTokens({required String access, required String refresh}) {
    _cachedAccess = access;
    _cachedRefresh = refresh;
    _lastKnownRefresh = refresh;
    // Fire and forget; failures surface on the next refresh attempt.
    _persistence.saveRefresh(refresh);
  }

  Future<void> loadPersisted() async {
    _lastKnownRefresh = await _persistence.readRefresh();
    _cachedRefresh = _lastKnownRefresh;
  }

  void clearCached() {
    _cachedAccess = null;
    _cachedRefresh = null;
    _lastKnownRefresh = null;
    _persistence.clearRefresh();
  }
}

/// Dio wrapper with Bearer injection and SINGLE-FLIGHT refresh-and-retry on
/// 401. Single-flight matters here because the backend's refresh rotation is
/// not bound to the presented token (audit §3.2): concurrent refreshes would
/// evict each other's tokens and force a logout.
class ApiClient {
  final Dio dio;
  final TokenStore tokens;
  final String baseUrl;

  /// Invoked when a refresh definitively fails (401 from /auth/refresh):
  /// controllers use it to flip auth state to loggedOut.
  void Function()? onSessionExpired;

  Future<(String, String)>? _inFlightRefresh;

  ApiClient({required this.baseUrl, required this.tokens})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final t = tokens.cachedAccess;
          if (t != null) {
            options.headers['Authorization'] = 'Bearer $t';
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final status = err.response?.statusCode;
          final alreadyRetried = err.requestOptions.extra['retried'] == true;
          final isRefreshCall = err.requestOptions.path.contains(
            '/auth/refresh',
          );
          if (status == 401 &&
              !alreadyRetried &&
              !isRefreshCall &&
              tokens.hasRefresh) {
            try {
              final pair = await _refreshOnce();
              tokens.setTokens(access: pair.$1, refresh: pair.$2);
              final response = await _retry(err.requestOptions, pair.$1);
              return handler.resolve(response);
            } on DioException catch (refreshErr) {
              tokens.clearCached();
              onSessionExpired?.call();
              return handler.next(refreshErr);
            }
          }
          handler.next(err);
        },
      ),
    );
  }

  /// Serializes refreshes: only one network refresh runs at a time and all
  /// concurrent 401s await the same future.
  Future<(String, String)> _refreshOnce() {
    _inFlightRefresh ??= _doRefresh();
    return _inFlightRefresh!.whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<(String, String)> _doRefresh() async {
    final raw = Dio(BaseOptions(baseUrl: baseUrl));
    final res = await raw.post(
      '/api/v1/auth/refresh',
      data: {'refresh_token': tokens.refreshToken},
      options: Options(headers: {'Accept': 'application/json'}),
    );
    final j = res.data as Map<String, dynamic>;
    return (j['access_token'] as String, j['refresh_token'] as String);
  }

  Future<Response<dynamic>> _retry(
    RequestOptions requestOptions,
    String access,
  ) {
    requestOptions.extra['retried'] = true;
    requestOptions.headers['Authorization'] = 'Bearer $access';
    return dio.fetch<dynamic>(requestOptions);
  }
}
