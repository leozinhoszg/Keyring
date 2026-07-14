import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
}
