import 'package:sqflite/sqflite.dart';
import 'vault_repository.dart';
import 'vault_repository_io.dart';

VaultRepository createVaultRepository(Database db) => SqliteVaultRepository(db);
