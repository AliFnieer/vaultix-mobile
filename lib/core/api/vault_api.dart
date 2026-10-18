import 'package:dio/dio.dart';

import 'api_client.dart';
import 'app_exception.dart';
import 'models.dart';

/// Vault + Secret endpoints of vaultix-backend (docs/mobile-api-contract.md).
class VaultApi {
  final ApiClient _client;

  VaultApi(this._client);

  Dio get _dio => _client.dio;

  Future<T> _wrap<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // -- vaults ----------------------------------------------------------------

  Future<List<VaultDto>> listVaults() => _wrap(() async {
    final res = await _dio.get('/api/v1/vaults');
    final j = res.data as Map<String, dynamic>;
    return ((j['vaults'] as List?) ?? const [])
        .map((e) => VaultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Future<VaultDto> createVault({
    required String name,
    String description = '',
    String? color,
    String? icon,
    int sortOrder = 0,
  }) => _wrap(() async {
    final data = {
      'name': name,
      if (description.isNotEmpty) 'description': description,
      'color': ?color,
      'icon': ?icon,
      'sort_order': sortOrder,
    };
    final res = await _dio.post('/api/v1/vaults', data: data);
    return VaultDto.fromJson(res.data as Map<String, dynamic>);
  });

  Future<VaultDto> updateVault({
    required String id,
    required String name,
    String description = '',
    String? color,
    String? icon,
    int sortOrder = 0,
  }) => _wrap(() async {
    final data = {
      'name': name,
      'description': description,
      'color': ?color,
      'icon': ?icon,
      'sort_order': sortOrder,
    };
    final res = await _dio.put('/api/v1/vaults/$id', data: data);
    return VaultDto.fromJson(res.data as Map<String, dynamic>);
  });

  Future<void> deleteVault(String id) => _wrap(() async {
    await _dio.delete('/api/v1/vaults/$id');
  });

  // -- secrets ---------------------------------------------------------------

  Future<SecretsPage> listSecrets({
    int page = 1,
    int limit = 100,
    String? vaultId,
    String? search,
    bool includeArchived = true,
    bool includeTrashed = false,
  }) => _wrap(() async {
    final res = await _dio.get(
      '/api/v1/secrets',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (vaultId != null && vaultId.isNotEmpty) 'vault_id': vaultId,
        if (search != null && search.isNotEmpty) 'search': search,
        'include_archived': includeArchived.toString(),
        'include_trashed': includeTrashed.toString(),
      },
    );
    return SecretsPage.fromJson(res.data as Map<String, dynamic>);
  });

  Future<SecretDto> getSecret(String id) => _wrap(() async {
    final res = await _dio.get('/api/v1/secrets/$id');
    return SecretDto.fromJson(res.data as Map<String, dynamic>);
  });

  Future<SecretDto> createSecret({
    required String title,
    required String type,
    required String vaultId,
    required Map<String, String> fields,
    List<String> tags = const [],
    bool favorite = false,
  }) => _wrap(() async {
    final res = await _dio.post(
      '/api/v1/secrets',
      data: {
        'title': title,
        'type': type,
        'vault_id': vaultId,
        'fields': fields,
        'tags': tags,
        'favorite': favorite,
      },
    );
    return SecretDto.fromJson(res.data as Map<String, dynamic>);
  });

  Future<SecretDto> updateSecret({
    required String id,
    required String title,
    required String type,
    required String vaultId,
    required Map<String, String> fields,
    List<String> tags = const [],
    bool favorite = false,
  }) => _wrap(() async {
    final res = await _dio.put(
      '/api/v1/secrets/$id',
      data: {
        'title': title,
        'type': type,
        'vault_id': vaultId,
        'fields': fields,
        'tags': tags,
        'favorite': favorite,
      },
    );
    return SecretDto.fromJson(res.data as Map<String, dynamic>);
  });

  Future<void> deleteSecret(String id) => _wrap(() async {
    await _dio.delete('/api/v1/secrets/$id');
  });

  /// archive | unarchive | trash | restore
  Future<void> secretFlag(String id, String action) => _wrap(() async {
    await _dio.post('/api/v1/secrets/$id/$action');
  });

  Future<bool> toggleFavorite(String id) => _wrap(() async {
    final res = await _dio.post('/api/v1/secrets/$id/favorite');
    return (res.data as Map<String, dynamic>)['favorite'] as bool? ?? false;
  });
}
