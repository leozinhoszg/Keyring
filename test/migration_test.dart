import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/state/vault_repository.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('migração v1→v2 preserva os dados e adiciona as colunas do acesso rápido', () async {
    final dir = await Directory.systemTemp.createTemp('keyring_mig');
    final dbPath = p.join(dir.path, 'vault.db');

    // v1: schema antigo, sem as colunas do acesso rápido, com uma credencial
    final db1 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE vault_meta (
          id INTEGER PRIMARY KEY CHECK (id = 1), argon2_salt BLOB NOT NULL,
          argon2_params TEXT NOT NULL, wrapped_dek BLOB NOT NULL,
          totp_secret_enc BLOB NOT NULL, recovery_codes_hash TEXT NOT NULL,
          settings TEXT NOT NULL, created_at TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE credentials (
          id TEXT PRIMARY KEY, title_enc BLOB NOT NULL, username_enc BLOB, password_enc BLOB,
          url_enc BLOB, notes_enc BLOB, project_enc BLOB,
          is_favorite INTEGER NOT NULL DEFAULT 0, strength_score INTEGER, password_hmac TEXT,
          expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
      }),
    );
    await db1.insert('credentials', {
      'id': 'c1',
      'title_enc': Uint8List.fromList([1, 2, 3]),
      'is_favorite': 0,
      'created_at': 'now',
      'updated_at': 'now',
    });
    await db1.close();

    // v2: a migração REAL do app
    final db2 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => createSchema(db),
        onUpgrade: migrateVault,
      ),
    );

    final rows = await db2.query('credentials');
    expect(rows.length, 1, reason: 'a credencial deve sobreviver à migração');
    expect(rows.first['id'], 'c1');

    final cols = await db2.rawQuery('PRAGMA table_info(vault_meta)');
    final names = cols.map((c) => c['name'] as String).toSet();
    expect(names, contains('wrapped_dek_quick'));
    expect(names, contains('quick_expires_at'));

    await db2.close();
    await dir.delete(recursive: true);
  });
}
