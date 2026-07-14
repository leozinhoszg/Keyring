import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/state/vault_repository.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('migração de schema preserva os dados existentes do cofre', () async {
    final dir = await Directory.systemTemp.createTemp('keyring_mig');
    final dbPath = p.join(dir.path, 'vault.db');

    // v1: cria o schema e grava uma credencial
    final db1 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => createSchema(db)),
    );
    await db1.insert('credentials', {
      'id': 'c1',
      'title_enc': Uint8List.fromList([1, 2, 3]),
      'is_favorite': 0,
      'created_at': 'now',
      'updated_at': 'now',
    });
    await db1.close();

    // v2: migração incremental (adiciona coluna) — os dados devem permanecer
    final db2 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => createSchema(db),
        onUpgrade: (db, oldV, _) async {
          if (oldV < 2) await db.execute('ALTER TABLE credentials ADD COLUMN note TEXT');
        },
      ),
    );
    final rows = await db2.query('credentials');
    expect(rows.length, 1, reason: 'a credencial deve sobreviver à migração');
    expect(rows.first['id'], 'c1');
    expect(rows.first.containsKey('note'), isTrue, reason: 'a nova coluna deve existir');
    await db2.close();

    await dir.delete(recursive: true);
  });
}
