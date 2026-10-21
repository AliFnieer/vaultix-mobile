import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultix_mobile/core/crypto/totp.dart';
import 'package:vaultix_mobile/core/data/totp_repository.dart';
import 'package:vaultix_mobile/core/db/database.dart';

void main() {
  test(
    'stores TOTP secrets encrypted and can decrypt them for code generation',
    () async {
      final db = AppDb(NativeDatabase.memory());
      final repository = TotpRepository(db, SecretKey(List.filled(32, 7)));
      const config = TotpConfig(
        secretB32: 'GEZDGNBV',
        issuer: 'Example',
        account: 'alice@example.com',
        algorithm: TotpAlgorithm.sha256,
        digits: 8,
        period: 45,
      );

      await repository.add(config);
      final rows = await db.watchTotpRows().first;

      expect(rows, hasLength(1));
      expect(rows.single.secretCipher, isNot(config.secretB32));
      expect(rows.single.issuer, 'Example');
      expect(rows.single.label, 'alice@example.com');
      expect(rows.single.algorithm, 'SHA256');
      expect(rows.single.digits, 8);
      expect(rows.single.periodSeconds, 45);
      expect(await repository.openSecret(rows.single), config.secretB32);

      await repository.delete(rows.single.id);
      expect(await db.watchTotpRows().first, isEmpty);
      await db.close();
    },
  );

  test('rejects invalid TOTP configuration', () async {
    final db = AppDb(NativeDatabase.memory());
    final repository = TotpRepository(db, SecretKey(List.filled(32, 7)));

    await expectLater(
      repository.add(
        const TotpConfig(secretB32: 'not-base32!', issuer: '', account: ''),
      ),
      throwsFormatException,
    );
    expect(await db.watchTotpRows().first, isEmpty);
    await db.close();
  });
}
