// ---------------------------------------------------------------------------
// Vault + Secret DTOs — snake_case, matching vaultix-backend JSON tags.
// ---------------------------------------------------------------------------

class VaultDto {
  final String id;
  final String name;
  final String description;
  final String? color;
  final String? icon;
  final bool isDefault;
  final int sortOrder;
  final String createdAt;
  final String updatedAt;

  const VaultDto({
    required this.id,
    required this.name,
    required this.description,
    this.color,
    this.icon,
    required this.isDefault,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VaultDto.fromJson(Map<String, dynamic> j) => VaultDto(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    color: j['color'] as String?,
    icon: j['icon'] as String?,
    isDefault: j['is_default'] as bool? ?? false,
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    createdAt: j['created_at'] as String? ?? '',
    updatedAt: j['updated_at'] as String? ?? '',
  );
}

/// `type ∈ login|note|card|api_key|custom` (server-validated enum).
class SecretDto {
  static const types = ['login', 'note', 'card', 'api_key', 'custom'];

  final String id;
  final String vaultId;
  final String title;
  final String type;

  /// Fields come back DECRYPTED (server-side encryption — audit §2).
  final Map<String, String> fields;
  final List<String> tags;
  final bool favorite;
  final bool isArchived;
  final bool isTrashed;
  final String createdAt;
  final String updatedAt;

  const SecretDto({
    required this.id,
    required this.vaultId,
    required this.title,
    required this.type,
    required this.fields,
    required this.tags,
    required this.favorite,
    required this.isArchived,
    required this.isTrashed,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SecretDto.fromJson(Map<String, dynamic> j) => SecretDto(
    id: j['id'] as String,
    vaultId: j['vault_id'] as String,
    title: j['title'] as String? ?? '',
    type: j['type'] as String? ?? 'login',
    fields: ((j['fields'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
    ),
    tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
    favorite: j['favorite'] as bool? ?? false,
    isArchived: j['is_archived'] as bool? ?? false,
    isTrashed: j['is_trashed'] as bool? ?? false,
    createdAt: j['created_at'] as String? ?? '',
    updatedAt: j['updated_at'] as String? ?? '',
  );
}

class SecretsPage {
  final List<SecretDto> secrets;
  final int total;
  final int page;
  final int limit;

  const SecretsPage({
    required this.secrets,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory SecretsPage.fromJson(Map<String, dynamic> j) => SecretsPage(
    secrets: ((j['secrets'] as List?) ?? const [])
        .map((e) => SecretDto.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: (j['total'] as num?)?.toInt() ?? 0,
    page: (j['page'] as num?)?.toInt() ?? 1,
    limit: (j['limit'] as num?)?.toInt() ?? 20,
  );
}
