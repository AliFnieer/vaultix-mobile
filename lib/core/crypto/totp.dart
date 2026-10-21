import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 TOTP + RFC 4648 base32 + otpauth:// URI handling.
///
/// Pure Dart, no custom cryptography: HMAC from `package:crypto`.
enum TotpAlgorithm { sha1, sha256, sha512 }

class TotpConfig {
  final String secretB32;
  final String issuer;
  final String account;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  const TotpConfig({
    required this.secretB32,
    required this.issuer,
    required this.account,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  });

  bool get isValid =>
      (base32Decode(secretB32)?.isNotEmpty ?? false) &&
      digits >= 6 &&
      digits <= 8 &&
      period >= 15;
}

/// RFC 4648 base32 (A-Z2-7, padding optional, case-insensitive).
Uint8List? base32Decode(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final cleaned = input.replaceAll('=', '').replaceAll(' ', '').toUpperCase();
  if (cleaned.isEmpty) return null;
  var buffer = 0;
  var bitsLeft = 0;
  final out = <int>[];
  for (final c in cleaned.split('')) {
    final idx = alphabet.indexOf(c);
    if (idx < 0) return null;
    buffer = (buffer << 5) | idx;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      out.add((buffer >> (bitsLeft - 8)) & 0xff);
      bitsLeft -= 8;
    }
  }
  return Uint8List.fromList(out);
}

String base32Encode(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bitsLeft = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      out.write(alphabet[(buffer >> (bitsLeft - 5)) & 0x1f]);
      bitsLeft -= 5;
    }
  }
  if (bitsLeft > 0) {
    out.write(alphabet[(buffer << (5 - bitsLeft)) & 0x1f]);
  }
  return out.toString();
}

/// Generates the TOTP code for [time] (RFC 6238).
String totpCode({
  required String secretB32,
  required DateTime time,
  TotpAlgorithm algorithm = TotpAlgorithm.sha1,
  int digits = 6,
  int period = 30,
}) {
  if (digits < 6 || digits > 8 || period < 15) {
    throw const FormatException('invalid TOTP parameters');
  }
  final secret = base32Decode(secretB32);
  if (secret == null) {
    throw const FormatException('invalid base32 secret');
  }
  final counter = time.millisecondsSinceEpoch ~/ 1000 ~/ period;
  final msg = _int64Bytes(counter);
  final List<int> mac;
  switch (algorithm) {
    case TotpAlgorithm.sha1:
      mac = Hmac(sha1, secret).convert(msg).bytes;
    case TotpAlgorithm.sha256:
      mac = Hmac(sha256, secret).convert(msg).bytes;
    case TotpAlgorithm.sha512:
      mac = Hmac(sha512, secret).convert(msg).bytes;
  }
  final offset = mac[mac.length - 1] & 0x0f;
  final binary =
      ((mac[offset] & 0x7f) << 24) |
      ((mac[offset + 1] & 0xff) << 16) |
      ((mac[offset + 2] & 0xff) << 8) |
      (mac[offset + 3] & 0xff);
  final otp = binary % math.pow(10, digits).toInt();
  return otp.toString().padLeft(digits, '0');
}

/// Seconds remaining in the current period.
int totpRemainingSeconds(DateTime time, {int period = 30}) {
  if (period <= 0) {
    throw const FormatException('invalid TOTP period');
  }
  final s = time.millisecondsSinceEpoch ~/ 1000;
  return period - (s % period);
}

List<int> _int64Bytes(int value) {
  final b = Uint8List(8);
  var v = value;
  for (var i = 7; i >= 0; i--) {
    b[i] = v & 0xff;
    v >>= 8;
  }
  return b;
}

/// Parses `otpauth://totp/Issuer:account?secret=...&issuer=...&algorithm=...&digits=...&period=...`
TotpConfig? parseOtpauthUri(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'otpauth' || parsed.host != 'totp') {
    return null;
  }
  final label = Uri.decodeComponent(parsed.path.replaceFirst('/', ''));
  String issuer = parsed.queryParameters['issuer'] ?? '';
  String account = label;
  final colon = label.indexOf(':');
  if (colon >= 0) {
    final labelIssuer = label.substring(0, colon).trim();
    account = label.substring(colon + 1).trim();
    if (issuer.isEmpty) issuer = labelIssuer;
  }
  final secret = (parsed.queryParameters['secret'] ?? '').replaceAll(' ', '');
  if (base32Decode(secret)?.isNotEmpty != true) return null;

  final algoName = (parsed.queryParameters['algorithm'] ?? 'SHA1')
      .toUpperCase();
  final algo = switch (algoName) {
    'SHA1' => TotpAlgorithm.sha1,
    'SHA256' => TotpAlgorithm.sha256,
    'SHA512' => TotpAlgorithm.sha512,
    _ => null,
  };
  if (algo == null) return null;
  final digits = int.tryParse(parsed.queryParameters['digits'] ?? '') ?? 6;
  final period = int.tryParse(parsed.queryParameters['period'] ?? '') ?? 30;

  final cfg = TotpConfig(
    secretB32: secret,
    issuer: issuer,
    account: account.isEmpty ? 'account' : account,
    algorithm: algo,
    digits: digits,
    period: period,
  );
  return cfg.isValid ? cfg : null;
}

/// Builds an otpauth:// URI (used by tests and the "show URI" affordance).
String buildOtpauthUri(TotpConfig cfg) {
  final algo = switch (cfg.algorithm) {
    TotpAlgorithm.sha1 => 'SHA1',
    TotpAlgorithm.sha256 => 'SHA256',
    TotpAlgorithm.sha512 => 'SHA512',
  };
  final label = Uri.encodeComponent('${cfg.issuer}:${cfg.account}');
  return Uri(
    scheme: 'otpauth',
    host: 'totp',
    path: '/$label',
    queryParameters: {
      'secret': cfg.secretB32,
      'issuer': cfg.issuer,
      'algorithm': algo,
      'digits': '${cfg.digits}',
      'period': '${cfg.period}',
    },
  ).toString();
}
