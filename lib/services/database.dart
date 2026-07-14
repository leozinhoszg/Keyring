import 'dart:io' show Platform;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../state/vault_repository.dart' show createSchema;

export 'package:sqflite/sqflite.dart' show Database;

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
  return openDatabase(
    dbPath,
    version: 1,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, _) => createSchema(db),
  );
}
