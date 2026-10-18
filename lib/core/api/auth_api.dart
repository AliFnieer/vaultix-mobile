import 'package:dio/dio.dart';

import 'api_client.dart';
import 'app_exception.dart';

// ---------------------------------------------------------------------------
// DTOs — snake_case, matching vaultix-backend JSON tags exactly.
// ---------------------------------------------------------------------------

class UserProfile {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id'] as String,
    email: j['email'] as String? ?? '',
    firstName: j['first_name'] as String? ?? '',
    lastName: j['last_name'] as String? ?? '',
    role: j['role'] as String? ?? 'user',
    isActive: j['is_active'] as bool? ?? true,
    createdAt: j['created_at'] as String? ?? '',
    updatedAt: j['updated_at'] as String? ?? '',
  );
}

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final UserProfile user;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    accessToken: j['access_token'] as String,
    refreshToken: j['refresh_token'] as String,
    tokenType: j['token_type'] as String? ?? 'Bearer',
    expiresIn: (j['expires_in'] as num?)?.toInt() ?? 0,
    user: UserProfile.fromJson(j['user'] as Map<String, dynamic>),
  );
}

// ---------------------------------------------------------------------------
// Auth API
// ---------------------------------------------------------------------------

class AuthApi {
  final ApiClient _client;

  AuthApi(this._client);

  Dio get _dio => _client.dio;

  Future<AuthSession> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final res = await _dio.post(
        '/api/v1/auth/register',
        data: {
          'email': email,
          'password': password,
          'first_name': firstName,
          'last_name': lastName,
        },
      );
      return AuthSession.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '/api/v1/auth/login',
        data: {'email': email, 'password': password},
      );
      return AuthSession.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/v1/auth/logout');
    } on DioException {
      // Best effort: local logout must always succeed (stateless access
      // tokens are not invalidated server-side anyway — audit §3.3).
    }
  }

  Future<UserProfile> me() async {
    try {
      final res = await _dio.get('/api/v1/auth/me');
      return UserProfile.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
