import 'package:anx_reader/utils/crypto/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup crypto encrypt/decrypt roundtrip', () async {
    const password = 'p@ssw0rd!';
    const plaintext = '{"openai":"sk-test"}';

    final secret =
        await encryptString(plaintext: plaintext, password: password);
    final decrypted = await decryptString(secret: secret, password: password);

    expect(decrypted, plaintext);
  });

  test('backup crypto wrong password throws', () async {
    const password = 'p@ssw0rd!';
    const plaintext = 'hello';

    final secret =
        await encryptString(plaintext: plaintext, password: password);

    expect(
      () => decryptString(secret: secret, password: 'wrong'),
      throwsA(isA<Object>()),
    );
  });
}
