import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:hashlib/hashlib.dart' as hashlib;

import '../models/argon2_params.dart';

class CryptoService {
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();
  final Random _rng = Random.secure();

  static const int _nonceLen = 12;
  static const int _tagLen = 16;

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  Uint8List randomSalt() => _randomBytes(16);
  Uint8List generateDek() => _randomBytes(32);

  /// Chave que envolve o DEK para o acesso rápido. Mesmo tamanho e mesma fonte
  /// do DEK; nomeada à parte porque o ciclo de vida é outro — esta vive no
  /// keystore do SO e é revogada sem tocar no cofre.
  Uint8List generateQuickKey() => _randomBytes(32);

  Future<Uint8List> deriveKek(String password, Uint8List salt, Argon2Params p) async {
    final digest = hashlib.Argon2(
      salt: salt,
      hashLength: 32,
      iterations: p.timeCost,
      parallelism: p.parallelism,
      memorySizeKB: p.memoryCost,
      type: hashlib.Argon2Type.argon2id,
    ).convert(utf8.encode(password));
    return Uint8List.fromList(digest.bytes);
  }

  Future<Uint8List> _encryptBytes(List<int> data, Uint8List key) async {
    final nonce = _randomBytes(_nonceLen);
    final box = await _aes.encrypt(data, secretKey: SecretKey(key), nonce: nonce);
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<List<int>> _decryptBytes(Uint8List blob, Uint8List key) async {
    final nonce = blob.sublist(0, _nonceLen);
    final mac = blob.sublist(blob.length - _tagLen);
    final ct = blob.sublist(_nonceLen, blob.length - _tagLen);
    final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));
    return _aes.decrypt(box, secretKey: SecretKey(key));
  }

  Future<Uint8List> encrypt(String plaintext, Uint8List key) =>
      _encryptBytes(utf8.encode(plaintext), key);

  Future<String> decrypt(Uint8List blob, Uint8List key) async =>
      utf8.decode(await _decryptBytes(blob, key));

  Future<Uint8List> wrapDek(Uint8List dek, Uint8List kek) => _encryptBytes(dek, kek);

  Future<Uint8List> unwrapDek(Uint8List wrapped, Uint8List kek) async =>
      Uint8List.fromList(await _decryptBytes(wrapped, kek));

  Future<String> hmacHex(String value, Uint8List key) async {
    final mac = await _hmac.calculateMac(utf8.encode(value), secretKey: SecretKey(key));
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
