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

  group('contexto (AAD)', () {
    test('blob de um campo não decifra no lugar de outro', () async {
      final key = svc.generateDek();
      final blob = await svc.encrypt('senha-do-banco', key, context: 'credential:aaa:password');

      // É o ataque que o AAD fecha: copiar o blob cifrado de um registro para
      // outro, direto no SQLite, e o app exibir o segredo no lugar errado.
      expect(
        () => svc.decrypt(blob, key, context: 'credential:bbb:password'),
        throwsA(anything),
        reason: 'o mesmo blob em outro registro deve ser rejeitado',
      );
      expect(
        () => svc.decrypt(blob, key, context: 'credential:aaa:username'),
        throwsA(anything),
        reason: 'o mesmo blob em outro campo deve ser rejeitado',
      );
      expect(await svc.decrypt(blob, key, context: 'credential:aaa:password'),
          'senha-do-banco');
    });

    test('blobs gravados pela versão antiga continuam legíveis', () async {
      final key = svc.generateDek();
      final legado = await svc.encryptLegacyV1('segredo-antigo', key);
      // Cofres existentes têm blobs sem versão nem AAD; recusá-los trancaria o
      // usuário fora dos próprios dados.
      expect(await svc.decrypt(legado, key, context: 'credential:aaa:password'),
          'segredo-antigo');
    });

    test('blob novo carrega a versão do formato', () async {
      final key = svc.generateDek();
      final blob = await svc.encrypt('x', key, context: 'c:1:f');
      expect(svc.cipherVersionOf(blob), 2);
      expect(svc.cipherVersionOf(await svc.encryptLegacyV1('x', key)), 1);
    });

    test('cada cifragem usa um nonce novo', () async {
      final key = svc.generateDek();
      final a = await svc.encrypt('mesmo-valor', key, context: 'c:1:f');
      final b = await svc.encrypt('mesmo-valor', key, context: 'c:1:f');
      expect(a, isNot(equals(b)), reason: 'nonce reutilizado em GCM é catastrófico');
    });

    test('blob truncado é rejeitado sem estourar RangeError', () async {
      final key = svc.generateDek();
      final blob = await svc.encrypt('x', key, context: 'c:1:f');
      expect(
        () => svc.decrypt(blob.sublist(0, 8), key, context: 'c:1:f'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
