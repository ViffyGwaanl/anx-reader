import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedBackupSecret {
  EncryptedBackupSecret({
    required this.saltB64,
    required this.nonceB64,
    required this.iterations,
    required this.cipherTextB64,
  });

  final String saltB64;
  final String nonceB64;
  final int iterations;
  final String cipherTextB64;

  Map<String, dynamic> toJson() => {
        'kdf': {
          'alg': 'PBKDF2-HMAC-SHA256',
          'saltB64': saltB64,
          'iterations': iterations,
        },
        'encryption': {
          'alg': 'AES-256-GCM',
          'nonceB64': nonceB64,
        },
        'cipherTextB64': cipherTextB64,
      };

  factory EncryptedBackupSecret.fromJson(Map<String, dynamic> json) {
    final kdf = (json['kdf'] as Map?)?.cast<String, dynamic>() ?? const {};
    final enc =
        (json['encryption'] as Map?)?.cast<String, dynamic>() ?? const {};
    return EncryptedBackupSecret(
      saltB64: kdf['saltB64']?.toString() ?? '',
      nonceB64: enc['nonceB64']?.toString() ?? '',
      iterations: (kdf['iterations'] as num?)?.toInt() ?? 150000,
      cipherTextB64: json['cipherTextB64']?.toString() ?? '',
    );
  }
}

Uint8List _randomBytes(int length) {
  final r = Random.secure();
  final bytes = List<int>.generate(length, (_) => r.nextInt(256));
  return Uint8List.fromList(bytes);
}

Future<SecretKey> _deriveKey({
  required String password,
  required Uint8List salt,
  required int iterations,
}) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  return pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
}

/// Encrypt a UTF-8 string using PBKDF2-HMAC-SHA256 + AES-256-GCM.
Future<EncryptedBackupSecret> encryptString({
  required String plaintext,
  required String password,
  int iterations = 150000,
}) async {
  final salt = _randomBytes(16);
  final nonce = _randomBytes(12);
  final key =
      await _deriveKey(password: password, salt: salt, iterations: iterations);

  final cipher = AesGcm.with256bits();
  final box = await cipher.encrypt(
    utf8.encode(plaintext),
    secretKey: key,
    nonce: nonce,
  );

  // Store nonce + ciphertext + tag in one blob.
  final blob = <int>[
    ...box.cipherText,
    ...box.mac.bytes,
  ];

  return EncryptedBackupSecret(
    saltB64: base64Encode(salt),
    nonceB64: base64Encode(nonce),
    iterations: iterations,
    cipherTextB64: base64Encode(blob),
  );
}

/// Decrypt a UTF-8 string encrypted by [encryptString].
Future<String> decryptString({
  required EncryptedBackupSecret secret,
  required String password,
}) async {
  final salt = base64Decode(secret.saltB64);
  final nonce = base64Decode(secret.nonceB64);
  final blob = base64Decode(secret.cipherTextB64);

  if (blob.length < 16) {
    throw StateError('ciphertext too short');
  }

  // AES-GCM tag is 16 bytes.
  final cipherText = blob.sublist(0, blob.length - 16);
  final macBytes = blob.sublist(blob.length - 16);

  final key = await _deriveKey(
    password: password,
    salt: Uint8List.fromList(salt),
    iterations: secret.iterations,
  );

  final cipher = AesGcm.with256bits();
  final clear = await cipher.decrypt(
    SecretBox(
      cipherText,
      nonce: Uint8List.fromList(nonce),
      mac: Mac(macBytes),
    ),
    secretKey: key,
  );

  return utf8.decode(clear);
}
