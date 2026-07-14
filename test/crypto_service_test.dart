import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/models/argon2_params.dart';
import 'package:keyring/services/crypto_service.dart';

void main() {
  final svc = CryptoService();
  const params = Argon2Params();

  test('round-trip encrypt/decrypt', () async {
    final key = svc.generateDek();
    final blob = await svc.encrypt('senha-secreta', key);
    expect(await svc.decrypt(blob, key), 'senha-secreta');
  });

  test('rejeita ciphertext adulterado', () async {
    final key = svc.generateDek();
    final blob = await svc.encrypt('x', key);
    blob[blob.length - 1] ^= 0xFF;
    expect(() => svc.decrypt(blob, key), throwsA(anything));
  });

  test('wrap/unwrap DEK com a KEK', () async {
    final salt = svc.randomSalt();
    final kek = await svc.deriveKek('mestra', salt, params);
    final dek = svc.generateDek();
    final wrapped = await svc.wrapDek(dek, kek);
    final unwrapped = await svc.unwrapDek(wrapped, kek);
    expect(unwrapped, equals(dek));
  });

  test('unwrap falha com KEK errada', () async {
    final salt = svc.randomSalt();
    final kek1 = await svc.deriveKek('certa', salt, params);
    final kek2 = await svc.deriveKek('errada', salt, params);
    final wrapped = await svc.wrapDek(svc.generateDek(), kek1);
    expect(() => svc.unwrapDek(wrapped, kek2), throwsA(anything));
  });

  test('hmac deterministico', () async {
    final key = svc.generateDek();
    expect(await svc.hmacHex('abc', key), await svc.hmacHex('abc', key));
    expect(await svc.hmacHex('abc', key), isNot(await svc.hmacHex('abd', key)));
  });
}
