import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:hashlib/hashlib.dart' as hashlib;

import '../models/argon2_params.dart';

/// Argumentos da derivação, para atravessarem a fronteira do isolate.
class _KekRequest {
  final String password;
  final Uint8List salt;
  final Argon2Params params;
  const _KekRequest(this.password, this.salt, this.params);
}

/// Precisa ser função de topo: um método de instância não pode ser enviado
/// para outro isolate.
Uint8List _deriveKekIsolate(_KekRequest r) {
  final digest = hashlib.Argon2(
    salt: r.salt,
    hashLength: 32,
    iterations: r.params.timeCost,
    parallelism: r.params.parallelism,
    memorySizeKB: r.params.memoryCost,
    type: hashlib.Argon2Type.argon2id,
  ).convert(utf8.encode(r.password));
  return Uint8List.fromList(digest.bytes);
}

class CryptoService {
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();
  final Random _rng = Random.secure();

  static const int _nonceLen = 12;
  static const int _tagLen = 16;

  /// Cabeçalho do formato v2: 'K' seguido do número da versão. Um blob v1 pode
  /// começar com esses mesmos dois bytes por acaso, então o cabeçalho é apenas
  /// uma dica — quem decide de fato é a tag GCM, que só fecha na interpretação
  /// correta. Ver [_decryptBytes].
  static const int _magic = 0x4B; // 'K'
  static const int _v2 = 0x02;
  static const int _headerLen = 2;

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  Uint8List randomSalt() => _randomBytes(16);
  Uint8List generateDek() => _randomBytes(32);

  /// Chave que envolve o DEK para o acesso rápido. Mesmo tamanho e mesma fonte
  /// do DEK; nomeada à parte porque o ciclo de vida é outro — esta vive no
  /// keystore do SO e é revogada sem tocar no cofre.
  Uint8List generateQuickKey() => _randomBytes(32);

  /// Deriva a KEK da senha mestra. Roda num isolate porque o Argon2 é pesado de
  /// propósito (dezenas de MiB e centenas de ms): na thread da UI ele congela a
  /// tela inteira a cada desbloqueio, e o usuário lê isso como travamento.
  Future<Uint8List> deriveKek(String password, Uint8List salt, Argon2Params p) =>
      compute(_deriveKekIsolate, _KekRequest(password, salt, p));

  /// Versão do formato de um blob: 2 quando traz cabeçalho e AAD, 1 quando é do
  /// formato antigo. Útil para a migração saber o que ainda falta re-cifrar.
  int cipherVersionOf(Uint8List blob) =>
      (blob.length > _headerLen && blob[0] == _magic && blob[1] == _v2) ? 2 : 1;

  Future<Uint8List> _encryptBytes(List<int> data, Uint8List key, String? context) async {
    final nonce = _randomBytes(_nonceLen);
    final box = await _aes.encrypt(
      data,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _aadOf(context),
    );
    return Uint8List.fromList(
        [_magic, _v2, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  List<int> _aadOf(String? context) => context == null ? const [] : utf8.encode(context);

  Future<List<int>> _openAt(Uint8List blob, Uint8List key, int offset, List<int> aad) {
    final nonce = blob.sublist(offset, offset + _nonceLen);
    final mac = blob.sublist(blob.length - _tagLen);
    final ct = blob.sublist(offset + _nonceLen, blob.length - _tagLen);
    return _aes.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
      aad: aad,
    );
  }

  Future<List<int>> _decryptBytes(Uint8List blob, Uint8List key, String? context) async {
    if (blob.length < _nonceLen + _tagLen) {
      throw FormatException('Blob cifrado curto demais (${blob.length} bytes)');
    }
    // O cabeçalho indica v2, mas quem confirma é a tag: um blob v1 cujos dois
    // primeiros bytes coincidam com o cabeçalho falha aqui e cai no formato
    // antigo logo abaixo. Sem esse fallback a leitura seria ambígua.
    if (cipherVersionOf(blob) == 2 && blob.length >= _headerLen + _nonceLen + _tagLen) {
      try {
        return await _openAt(blob, key, _headerLen, _aadOf(context));
      } on SecretBoxAuthenticationError {
        // segue para o formato antigo
      }
    }
    return _openAt(blob, key, 0, const []);
  }

  /// Cifra [plaintext] amarrando o resultado a [context] — algo como
  /// `credential:<id>:password`. Sem isso, um blob copiado de um registro para
  /// outro dentro do SQLite decifra normalmente no lugar errado.
  Future<Uint8List> encrypt(String plaintext, Uint8List key, {String? context}) =>
      _encryptBytes(utf8.encode(plaintext), key, context);

  Future<String> decrypt(Uint8List blob, Uint8List key, {String? context}) async =>
      utf8.decode(await _decryptBytes(blob, key, context));

  /// Formato antigo, sem cabeçalho nem AAD. Existe só para os testes poderem
  /// fabricar dados como os de um cofre criado antes da v1.2.0.
  @visibleForTesting
  Future<Uint8List> encryptLegacyV1(String plaintext, Uint8List key) async {
    final nonce = _randomBytes(_nonceLen);
    final box = await _aes.encrypt(utf8.encode(plaintext), secretKey: SecretKey(key), nonce: nonce);
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> wrapDek(Uint8List dek, Uint8List kek) =>
      _encryptBytes(dek, kek, _dekContext);

  Future<Uint8List> unwrapDek(Uint8List wrapped, Uint8List kek) async =>
      Uint8List.fromList(await _decryptBytes(wrapped, kek, _dekContext));

  /// A DEK é única no cofre, então o contexto é fixo — serve para separá-la de
  /// qualquer outro blob cifrado com a mesma chave.
  static const String _dekContext = 'vault:dek';

  Future<String> hmacHex(String value, Uint8List key) async {
    final mac = await _hmac.calculateMac(utf8.encode(value), secretKey: SecretKey(key));
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
