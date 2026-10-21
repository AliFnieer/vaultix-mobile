import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultix_mobile/core/crypto/totp.dart';

void main() {
  group('TOTP', () {
    final time = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);

    test('matches the RFC 6238 SHA-1 test vector', () {
      final secret = base32Encode(utf8.encode('12345678901234567890'));
      expect(totpCode(secretB32: secret, time: time, digits: 8), '94287082');
    });

    test('matches the RFC 6238 SHA-256 test vector', () {
      final secret = base32Encode(
        utf8.encode('12345678901234567890123456789012'),
      );
      expect(
        totpCode(
          secretB32: secret,
          time: time,
          algorithm: TotpAlgorithm.sha256,
          digits: 8,
        ),
        '46119246',
      );
    });

    test('matches the RFC 6238 SHA-512 test vector', () {
      final secret = base32Encode(
        utf8.encode(
          '1234567890123456789012345678901234567890123456789012345678901234',
        ),
      );
      expect(
        totpCode(
          secretB32: secret,
          time: time,
          algorithm: TotpAlgorithm.sha512,
          digits: 8,
        ),
        '90693936',
      );
    });

    test('rejects invalid secrets and parameters', () {
      expect(() => totpCode(secretB32: '0', time: time), throwsFormatException);
      expect(
        () => totpCode(secretB32: 'GEZDGNBV', time: time, digits: 5),
        throwsFormatException,
      );
    });

    test('parses valid otpauth TOTP setup URIs', () {
      final config = parseOtpauthUri(
        'otpauth://totp/Example%3Aalice%40example.com'
        '?secret=GEZDGNBV&issuer=Example&algorithm=SHA256&digits=8&period=45',
      );

      expect(config, isNotNull);
      expect(config!.issuer, 'Example');
      expect(config.account, 'alice@example.com');
      expect(config.algorithm, TotpAlgorithm.sha256);
      expect(config.digits, 8);
      expect(config.period, 45);
    });

    test('rejects unsupported or invalid setup URIs', () {
      expect(
        parseOtpauthUri('otpauth://hotp/Example:alice?secret=GEZDGNBV'),
        isNull,
      );
      expect(
        parseOtpauthUri(
          'otpauth://totp/Example:alice?secret=GEZDGNBV&algorithm=SHA3',
        ),
        isNull,
      );
      expect(
        parseOtpauthUri('otpauth://totp/Example:alice?secret=not-base32!'),
        isNull,
      );
    });
  });
}
