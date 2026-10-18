import 'package:dio/dio.dart';

/// Typed client-side representation of the backend error envelope
/// `{"error": message, "code"?: code}` (code is ABSENT from /auth/refresh and
/// JWT-middleware errors — see docs/mobile-api-contract.md).
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isUnauthorized => statusCode == 401;
  bool get isValidation => statusCode == 400 || code == 'VALIDATION';

  /// The backend enforces secret-title uniqueness with a GLOBAL per-user Mongo
  /// index; an index violation surfaces as HTTP 500 (audit §3.1). Treat a 500
  /// on create/update as a possible duplicate-title conflict in the UI.
  bool get maybeDuplicateTitle =>
      statusCode == 500 && message.toLowerCase().contains('duplicate');

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode ?? 0;
    String message = 'Network error';
    String? code;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      message = (data['error'] as String?) ?? message;
      code = data['code'] as String?;
    } else if (e.message != null && e.message!.isNotEmpty) {
      message = e.message!;
    }
    return ApiException(statusCode: status, message: message, code: code);
  }

  @override
  String toString() => 'ApiException($statusCode, $message, $code)';
}
