import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/models/credential.dart';
import 'package:keyring/services/cipher_migration.dart';
import 'package:keyring/services/crypto_service.dart';
import 'package:keyring/state/vault_provider.dart';
import 'package:keyring/state/vault_repository.dart';
import 'package:keyring/state/vault_repository_io.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('cofre gravado pela versão antiga continua abrindo', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final repo = SqliteVaultRepository(db);

    // Uma credencial como a v1.1.0 gravava: sem cabeçalho de versão, sem AAD.
    await repo.createCredential(
      CredentialRow(
        id: 'antiga',
        titleEnc: await crypto.encryptLegacyV1('Servidor de produção', dek),
        passwordEnc: await crypto.encryptLegacyV1('s3nha-antiga', dek),
        createdAt: 'now',
        updatedAt: 'now',
      ),
      const [],
    );

    final provider = VaultProvider(repo, crypto, () => dek);
    await provider.loadCredentials();

    expect(provider.credentials.single.title, 'Servidor de produção');
    expect(await provider.reveal('antiga', 'password'), 's3nha-antiga');
  });

  test('trocar um blob de lugar no banco deixa de funcionar', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final repo = SqliteVaultRepository(db);
    final provider = VaultProvider(repo, crypto, () => dek);

    await provider.createCredential(const CredentialInput(title: 'Banco', password: 'senha-do-banco'));
    await provider.createCredential(const CredentialInput(title: 'Email', password: 'senha-do-email'));
    await provider.loadCredentials();
    final banco = provider.credentials.firstWhere((c) => c.title == 'Banco');
    final email = provider.credentials.firstWhere((c) => c.title == 'Email');

    // Ataque: copiar a senha do banco por cima da senha do email, direto no
    // SQLite. Antes do AAD isso funcionava silenciosamente.
    final roubado = (await repo.findCredential(banco.id))!.passwordEnc;
    await db.update('credentials', {'password_enc': roubado},
        where: 'id = ?', whereArgs: [email.id]);

    await expectLater(() => provider.reveal(email.id, 'password'), throwsA(anything));
  });

  test('migração re-cifra os blobs antigos e fecha a troca de lugar', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final repo = SqliteVaultRepository(db);

    // Dois registros no formato antigo — enquanto forem v1, seus blobs são
    // intercambiáveis, porque nada os amarra à linha onde estão.
    for (final (id, titulo, senha) in [
      ('a', 'Banco', 'senha-do-banco'),
      ('b', 'Email', 'senha-do-email'),
    ]) {
      await repo.createCredential(
        CredentialRow(
          id: id,
          titleEnc: await crypto.encryptLegacyV1(titulo, dek),
          passwordEnc: await crypto.encryptLegacyV1(senha, dek),
          createdAt: 'now',
          updatedAt: 'now',
        ),
        const [],
      );
    }
    await repo.createTag(TagRow(id: 't', nameEnc: await crypto.encryptLegacyV1('infra', dek)));

    final convertidos = await migrateCipherToV2(repo: repo, crypto: crypto, dek: dek);
    expect(convertidos, greaterThan(0));

    // Os valores sobrevivem...
    final provider = VaultProvider(repo, crypto, () => dek);
    await provider.loadCredentials();
    expect(provider.credentials.map((c) => c.title), containsAll(['Banco', 'Email']));
    expect(await provider.reveal('a', 'password'), 'senha-do-banco');
    await provider.loadTags();
    expect(provider.tags.single.name, 'infra');

    // ...e agora todo blob está amarrado ao seu lugar.
    expect(crypto.cipherVersionOf((await repo.findCredential('a'))!.passwordEnc!), 2);
    final roubado = (await repo.findCredential('a'))!.passwordEnc;
    await db.update('credentials', {'password_enc': roubado}, where: 'id = ?', whereArgs: ['b']);
    await expectLater(() => provider.reveal('b', 'password'), throwsA(anything));
  });

  test('migração rodada de novo não tem o que fazer', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final repo = SqliteVaultRepository(db);
    final provider = VaultProvider(repo, crypto, () => dek);
    await provider.createCredential(const CredentialInput(title: 'Nova', password: 'x'));

    expect(await migrateCipherToV2(repo: repo, crypto: crypto, dek: dek), 0,
        reason: 'cofre já em v2 não é reescrito a cada desbloqueio');
  });

  test('nada sensível aparece em texto puro no arquivo do cofre', () async {
    final dir = await Directory.systemTemp.createTemp('keyring_inv');
    final path = p.join(dir.path, 'vault.db');
    final db = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final provider = VaultProvider(SqliteVaultRepository(db), crypto, () => dek);

    await provider.createCredential(const CredentialInput(
      title: 'Producao-AWS',
      username: 'root@empresa',
      password: 'S3nh4-Sup3r-S3cr3t4',
      notes: 'chave de recuperacao: ABCD-EFGH',
    ));
    await db.close();

    final bytes = await File(path).readAsBytes();
    final conteudo = String.fromCharCodes(bytes);
    for (final segredo in [
      'Producao-AWS',
      'root@empresa',
      'S3nh4-Sup3r-S3cr3t4',
      'chave de recuperacao: ABCD-EFGH',
    ]) {
      expect(conteudo.contains(segredo), isFalse,
          reason: '"$segredo" não pode estar legível no arquivo');
    }

    await dir.delete(recursive: true);
  });
}
