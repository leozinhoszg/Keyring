import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/state/vault_repository.dart';
import 'package:keyring/state/vault_repository_io.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<VaultRepository> freshRepo() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    return SqliteVaultRepository(db);
  }

  Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

  test('cria, filtra por favorito/tag e deleta credencial', () async {
    final repo = await freshRepo();
    await repo.createTag(TagRow(id: 't1', nameEnc: b('prod'), color: '#f00'));
    await repo.createCredential(
      CredentialRow(
        id: 'c1', titleEnc: b('GitHub'), usernameEnc: b('u'), passwordEnc: b('p'),
        urlEnc: b('url'), projectEnc: b('infra'), isFavorite: 1, passwordHmac: 'h',
        createdAt: 'now', updatedAt: 'now',
      ),
      ['t1'],
    );
    final found = await repo.findCredential('c1');
    expect(found, isNotNull);
    expect(found!.titleEnc, b('GitHub')); // blob preservado como está (repo não cifra)
    expect(await repo.tagsOf('c1'), ['t1']);
    expect((await repo.listCredentials(tagId: 't1')).length, 1);
    expect((await repo.listCredentials(favorite: true)).length, 1);
    await repo.deleteCredential('c1');
    expect(await repo.findCredential('c1'), isNull);
  });

  test('updateQuickUnlock grava e limpa apenas as colunas do acesso rapido', () async {
    final repo = await freshRepo();

    await repo.saveVaultMeta(VaultMetaRow(
      argon2Salt: Uint8List.fromList([1, 2]),
      argon2Params: '{}',
      wrappedDek: Uint8List.fromList([3, 4]),
      totpSecretEnc: Uint8List.fromList([5, 6]),
      recoveryCodesHash: '[]',
      settings: '{}',
      createdAt: 'agora',
    ));

    // recem-criado: acesso rapido desligado
    var meta = await repo.loadVaultMeta();
    expect(meta!.wrappedDekQuick, isNull);
    expect(meta.quickExpiresAt, isNull);

    // grava
    await repo.updateQuickUnlock(Uint8List.fromList([9, 9, 9]), '2026-08-01T00:00:00.000');
    meta = await repo.loadVaultMeta();
    expect(meta!.wrappedDekQuick, Uint8List.fromList([9, 9, 9]));
    expect(meta.quickExpiresAt, '2026-08-01T00:00:00.000');
    expect(meta.wrappedDek, Uint8List.fromList([3, 4]),
        reason: 'a meta original nao pode ser tocada');

    // limpa
    await repo.updateQuickUnlock(null, null);
    meta = await repo.loadVaultMeta();
    expect(meta!.wrappedDekQuick, isNull);
    expect(meta.quickExpiresAt, isNull);
    expect(meta.totpSecretEnc, Uint8List.fromList([5, 6]),
        reason: 'limpar o acesso rapido nao pode afetar o resto');
  });
}
