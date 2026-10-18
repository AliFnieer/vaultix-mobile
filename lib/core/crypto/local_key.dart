import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Local KDF parameters, versioned so accounts can migrate (e.g. PBKDF2 ->
/// Argon2id) without breaking existing ones.
///
/// The vaultix-backend does NOT exchange KDF params (it authenticates with the
/// plaintext master password over TLS and bcrypts server-side, see
/// docs/mobile-api-contract.md). These parameters are therefore DEVICE-LOCAL:
/// they protect the locally wrapped vault key at rest.
class KdfParams {
  static const int algoPbkdf2Sha256 = 1;
  // Reserved: static const int algoArgon2id = 2; // when an approved package lands.

  final int algo;
  final int iterations;
  final Uint8List salt;

  const KdfParams({
    required this.algo,
    required this.iterations,
    required this.salt,
  });

  static const int defaultPbkdf2Iterations = 600000;

  factory KdfParams.newPbkdf2({Uint8List? salt}) => KdfParams(
    algo: algoPbkdf2Sha256,
    iterations: defaultPbkdf2Iterations,
    salt: salt ?? randomBytes(16),
  );

  Map<String, dynamic> toJson() => {
    'algo': algo,
    'iterations': iterations,
    'salt': base64Encode(salt),
  };

  factory KdfParams.fromJson(Map<String, dynamic> j) => KdfParams(
    algo: (j['algo'] as num).toInt(),
    iterations: (j['iterations'] as num).toInt(),
    salt: base64Decode(j['salt'] as String),
  );
}

/// Derives the 256-bit local master key from the user's master password.
///
/// PRODUCTION UPGRADE: [KdfParams.algoArgon2id] once an approved Argon2id
/// package is added; the versioned params make this a data migration, not a
/// redesign. Custom crypto is never written here — only `package:cryptography`.
abstract class LocalKdf {
  Future<SecretKey> deriveLocalMasterKey(String password, KdfParams params);
}

class Pbkdf2Sha256Kdf implements LocalKdf {
  const Pbkdf2Sha256Kdf();

  @override
  Future<SecretKey> deriveLocalMasterKey(String password, KdfParams params) {
    if (params.algo != KdfParams.algoPbkdf2Sha256) {
      throw UnsupportedError(
        'Unsupported local KDF algo ${params.algo}; app update required.',
      );
    }
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: params.salt,
    );
  }
}

/// Cryptographically-secure random bytes.
Uint8List randomBytes(int n) => Uint8List.fromList(
  List<int>.generate(n, (_) => Random.secure().nextInt(256)),
);
