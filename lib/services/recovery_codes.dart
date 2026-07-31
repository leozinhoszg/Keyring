import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as legacy;

/// Códigos que abrem o cofre no lugar do TOTP, para quem perdeu o Authy.
///
/// Não são senhas: são segredos aleatórios de 100 bits, então um hash rápido
/// com salt já é suficiente — força bruta sobre 100 bits é inviável qualquer
/// que seja a função. O salt (o mesmo do cofre) elimina tabelas pré-computadas
/// e faz o hash de um cofre não valer nada em outro.
///
/// O formato antigo tinha 40 bits vindos de um UUID e hash sem salt; códigos
/// gerados assim continuam sendo aceitos por [verify] enquanto não forem
/// trocados, para não trancar quem já anotou os seus.
class RecoveryCodes {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; // base32, sem 0/1/8/9
  static const _groups = 4;
  static const _groupLen = 5;
  static const int count = 8;

  final Random _rng = Random.secure();

  /// Gera [count] códigos no formato `XXXXX-XXXXX-XXXXX-XXXXX`.
  List<String> generate() => List.generate(count, (_) {
        final grupos = List.generate(
          _groups,
          (_) => List.generate(_groupLen, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join(),
        );
        return grupos.join('-');
      });

  /// JSON com o hash de cada código, para guardar no cofre.
  String hashAll(List<String> codes, Uint8List salt) =>
      jsonEncode([for (final c in codes) _hash(c, salt)]);

  /// Confere [code] contra os hashes gravados. Devolve o JSON já sem o código
  /// usado — cada um vale uma vez — ou null se não bateu com nenhum.
  String? consume(String code, String storedJson, Uint8List salt) {
    final stored = (jsonDecode(storedJson) as List).cast<String>();
    final normalizado = normalize(code);
    final candidatos = {
      _hash(normalizado, salt),
      _legacyHash(normalizado), // cofres criados antes da v1.2.0
      _legacyHash(code.trim()),
    };
    final restantes = <String>[];
    var achou = false;
    for (final h in stored) {
      // Sem short-circuit: percorre a lista inteira para não vazar, pelo tempo
      // de resposta, a posição do código dentro dela.
      if (!achou && candidatos.contains(h)) {
        achou = true;
        continue;
      }
      restantes.add(h);
    }
    return achou ? jsonEncode(restantes) : null;
  }

  /// Aceita o código como o usuário digitar: minúsculas, espaços, sem hífens.
  static String normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');

  String _hash(String code, Uint8List salt) =>
      legacy.sha256.convert([...salt, ...utf8.encode(normalize(code))]).toString();

  String _legacyHash(String code) => legacy.sha256.convert(utf8.encode(code)).toString();
}
