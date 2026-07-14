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
}
