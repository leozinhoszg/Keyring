import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/models/argon2_params.dart';
import 'package:keyring/models/credential.dart';
import 'package:keyring/services/backup.dart';
import 'package:keyring/services/crypto_service.dart';
import 'package:keyring/state/vault_repository.dart';
import 'package:keyring/state/vault_repository_io.dart';
import 'package:keyring/state/vault_provider.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<(VaultProvider, BackupService, dynamic)> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final repo = SqliteVaultRepository(db);
    final provider = VaultProvider(repo, crypto, () => dek);
    return (provider, BackupService(repo, crypto), dek);
  }

  test('backup: export -> grava em arquivo -> lê -> import (fluxo real)', () async {
    final (provider1, backup1, dek1) = await fresh();
    await provider1.createCredential(
      const CredentialInput(title: 'GitHub', username: 'me', password: 's3nha', project: 'infra'),
    );

    // export
    final content = await backup1.export(dek1 as dynamic, 'export-pw-123');

    // grava e relê EXATAMENTE como a UI faz (writeAsString + readAsBytes + fromCharCodes)
    final dir = await Directory.systemTemp.createTemp('kb');
    final path = p.join(dir.path, 'backup.vault');
    await File(path).writeAsString(content);
    final bytes = await File(path).readAsBytes();
    final readContent = String.fromCharCodes(bytes);

    // import num cofre novo, mesma senha de export
    final (provider2, backup2, dek2) = await fresh();
    final n = await backup2.import(dek2 as dynamic, readContent, 'export-pw-123');
    expect(n, greaterThan(0), reason: 'deve importar ao menos a credencial');

    await provider2.loadCredentials();
    expect(provider2.credentials.first.title, 'GitHub');
    expect(await provider2.reveal(provider2.credentials.first.id, 'password'), 's3nha');

    await Directory(dir.path).delete(recursive: true);
  });

  /// Monta um arquivo .vault legítimo (cifra de verdade) com o payload dado.
  /// Permite fabricar backups malformados que só quebram DEPOIS de decifrar.
  Future<String> vaultFileWith(Map<String, dynamic> payload, String pw) async {
    final crypto = CryptoService();
    const params = Argon2Params();
    final salt = crypto.randomSalt();
    final kek = await crypto.deriveKek(pw, salt, params);
    final blob = await crypto.encrypt(jsonEncode(payload), kek);
    return base64Encode(utf8.encode(jsonEncode({
      'v': 1,
      'salt': base64Encode(salt),
      'params': params.toJson(),
      'data': base64Encode(blob),
    })));
  }

  test('import que falha no meio não deixa itens gravados', () async {
    final (provider, backup, dek) = await fresh();
    // A segunda credencial não tem título: quebra ao ser gravada, depois da
    // primeira já ter entrado. Sem transação, o cofre fica com metade do backup.
    final file = await vaultFileWith({
      'credentials': [
        {'title': 'Primeira', 'password': 'a'},
        {'title': null, 'password': 'b'},
      ],
      'servers': <dynamic>[],
      'tags': <dynamic>[],
    }, 'pw-do-backup');

    await expectLater(
      () => backup.import(dek as dynamic, file, 'pw-do-backup'),
      throwsA(anything),
    );

    await provider.loadCredentials();
    expect(provider.credentials, isEmpty,
        reason: 'import atômico: falha no meio desfaz o que já entrou');
  });

  test('import roda duas vezes sem duplicar as tags', () async {
    final (provider, backup, dek) = await fresh();
    final file = await vaultFileWith({
      'credentials': [
        {'title': 'GitHub', 'password': 'a', 'tags': ['infra']},
      ],
      'servers': <dynamic>[],
      'tags': [
        {'name': 'infra', 'color': null},
      ],
    }, 'pw-do-backup');

    await backup.import(dek as dynamic, file, 'pw-do-backup');
    await backup.import(dek as dynamic, file, 'pw-do-backup');

    await provider.loadTags();
    expect(provider.tags.length, 1, reason: 'a tag existente é reaproveitada');
  });

  test('arquivo grande demais é recusado antes de decifrar', () async {
    final (_, backup, dek) = await fresh();
    final huge = 'A' * (kMaxBackupFileBytes + 1);
    await expectLater(
      () => backup.import(dek as dynamic, huge, 'qualquer'),
      throwsA(isA<BackupTooLargeException>()),
    );
  });
}
