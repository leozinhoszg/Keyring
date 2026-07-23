import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../state/vault_repository.dart' show createSchema, migrateVault;

export 'package:sqflite/sqflite.dart' show Database;

/// Versão do schema do cofre.
///
/// IMPORTANTE: incremente SEMPRE que o schema mudar e adicione a migração
/// correspondente em [_migrate]. Migrações só devem ADICIONAR/ALTERAR
/// (ALTER TABLE, novas tabelas) — NUNCA `DROP`/`DELETE` de dados. Assim uma
/// atualização do app jamais apaga o vault do usuário.
const int kVaultSchemaVersion = 2;

bool _ffiReady = false;

void _ensureFfi() {
  if (_ffiReady) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _ffiReady = true;
}

Future<Database> openKeyringDatabase({String? path}) async {
  _ensureFfi();
  final dbPath = path ??
      p.join((await getApplicationDocumentsDirectory()).path, 'keyring', 'vault.db');

  final inMemory = dbPath == inMemoryDatabasePath;
  if (!inMemory) {
    // garante o diretório e faz um backup de segurança antes de migrar o schema
    await Directory(p.dirname(dbPath)).create(recursive: true);
    await _backupBeforeUpgrade(dbPath);
  }

  return openDatabase(
    dbPath,
    version: kVaultSchemaVersion,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, _) => createSchema(db),
    onUpgrade: migrateVault,
  );
}

/// Se o banco já existe e vai ser migrado (versão gravada < versão do código),
/// copia o arquivo para um `.bak` ANTES — uma migração com problema nunca perde dados.
Future<void> _backupBeforeUpgrade(String dbPath) async {
  final file = File(dbPath);
  if (!await file.exists()) return;
  final current = await _readSchemaVersion(dbPath);
  if (current > 0 && current < kVaultSchemaVersion) {
    try {
      await file.copy('$dbPath.v$current.bak');
    } catch (_) {
      // backup é best-effort; não deve impedir a abertura do cofre
    }
  }
}

/// Lê a versão de schema gravada no arquivo (PRAGMA user_version), sem migrar.
Future<int> _readSchemaVersion(String dbPath) async {
  try {
    final db = await openDatabase(dbPath, readOnly: true);
    final rows = await db.rawQuery('PRAGMA user_version');
    await db.close();
    return (rows.first.values.first as int?) ?? 0;
  } catch (_) {
    return 0; // não conseguiu ler → trata como "sem migração pendente"
  }
}

// As migrações vivem em `migrateVault`, no vault_repository.dart, ao lado do
// createSchema — assim o schema e seus degraus mudam juntos, e o teste pode
// exercitar a migração real do app.
