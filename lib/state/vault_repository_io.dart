import 'package:sqflite/sqflite.dart';
import 'vault_repository.dart';

class SqliteVaultRepository implements VaultRepository {
  final Database _db;
  SqliteVaultRepository(this._db);

  @override
  Future<bool> isSetup() async =>
      (await _db.query('vault_meta', where: 'id = 1')).isNotEmpty;

  @override
  Future<void> saveVaultMeta(VaultMetaRow r) async {
    await _db.insert('vault_meta', {
      'id': 1, 'argon2_salt': r.argon2Salt, 'argon2_params': r.argon2Params,
      'wrapped_dek': r.wrappedDek, 'totp_secret_enc': r.totpSecretEnc,
      'recovery_codes_hash': r.recoveryCodesHash, 'settings': r.settings, 'created_at': r.createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<VaultMetaRow?> loadVaultMeta() async {
    final rows = await _db.query('vault_meta', where: 'id = 1');
    if (rows.isEmpty) return null;
    final m = rows.first;
    return VaultMetaRow(
      argon2Salt: m['argon2_salt'] as dynamic, argon2Params: m['argon2_params'] as String,
      wrappedDek: m['wrapped_dek'] as dynamic, totpSecretEnc: m['totp_secret_enc'] as dynamic,
      recoveryCodesHash: m['recovery_codes_hash'] as String, settings: m['settings'] as String,
      createdAt: m['created_at'] as String,
    );
  }

  @override
  Future<void> createCredential(CredentialRow row, List<String> tagIds) async {
    await _db.transaction((txn) async {
      await txn.insert('credentials', row.toMap());
      for (final t in tagIds) {
        await txn.insert('credential_tags', {'credential_id': row.id, 'tag_id': t},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  @override
  Future<void> updateCredential(CredentialRow row, List<String> tagIds) async {
    await _db.transaction((txn) async {
      await txn.update('credentials', row.toMap(), where: 'id = ?', whereArgs: [row.id]);
      await txn.delete('credential_tags', where: 'credential_id = ?', whereArgs: [row.id]);
      for (final t in tagIds) {
        await txn.insert('credential_tags', {'credential_id': row.id, 'tag_id': t},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  @override
  Future<void> deleteCredential(String id) =>
      _db.delete('credentials', where: 'id = ?', whereArgs: [id]);

  @override
  Future<CredentialRow?> findCredential(String id) async {
    final rows = await _db.query('credentials', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : CredentialRow.fromMap(rows.first);
  }

  @override
  Future<List<CredentialRow>> listCredentials({bool favorite = false, String? tagId}) async {
    final where = <String>[];
    final args = <Object?>[];
    var sql = 'SELECT c.* FROM credentials c';
    if (tagId != null) {
      sql += ' JOIN credential_tags ct ON ct.credential_id = c.id';
      where.add('ct.tag_id = ?');
      args.add(tagId);
    }
    if (favorite) where.add('c.is_favorite = 1');
    if (where.isNotEmpty) sql += ' WHERE ${where.join(' AND ')}';
    // Ordenação final (por título) é feita em memória, após decifrar.
    sql += ' ORDER BY c.is_favorite DESC, c.created_at';
    final rows = await _db.rawQuery(sql, args);
    return rows.map(CredentialRow.fromMap).toList();
  }

  @override
  Future<List<String>> tagsOf(String id) async {
    final rows = await _db.query('credential_tags', columns: ['tag_id'], where: 'credential_id = ?', whereArgs: [id]);
    return rows.map((r) => r['tag_id'] as String).toList();
  }

  @override
  Future<List<MapEntry<String, String>>> allPasswordHmacs() async {
    final rows = await _db.query('credentials', columns: ['id', 'password_hmac'], where: 'password_hmac IS NOT NULL');
    return rows.map((r) => MapEntry(r['id'] as String, r['password_hmac'] as String)).toList();
  }

  @override
  Future<void> createServer(ServerRow row) => _db.insert('servers', row.toMap());
  @override
  Future<void> updateServer(ServerRow row) =>
      _db.update('servers', row.toMap(), where: 'id = ?', whereArgs: [row.id]);
  @override
  Future<void> deleteServer(String id) => _db.delete('servers', where: 'id = ?', whereArgs: [id]);
  @override
  Future<ServerRow?> findServer(String id) async {
    final rows = await _db.query('servers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : ServerRow.fromMap(rows.first);
  }

  @override
  Future<List<ServerRow>> listServers() async {
    final rows = await _db.query('servers', orderBy: 'is_favorite DESC, created_at');
    return rows.map(ServerRow.fromMap).toList();
  }

  @override
  Future<void> addCommand(CommandRow c) => _db.insert('server_commands', {
        'id': c.id, 'server_id': c.serverId, 'label_enc': c.labelEnc, 'command_enc': c.commandEnc,
        'sort_order': c.sortOrder,
      });
  @override
  Future<void> deleteCommand(String id) => _db.delete('server_commands', where: 'id = ?', whereArgs: [id]);
  @override
  Future<List<CommandRow>> commandsOf(String serverId) async {
    final rows = await _db.query('server_commands', where: 'server_id = ?', whereArgs: [serverId], orderBy: 'sort_order');
    return rows
        .map((r) => CommandRow(
              id: r['id'] as String, serverId: r['server_id'] as String,
              labelEnc: r['label_enc'] as dynamic, commandEnc: r['command_enc'] as dynamic,
              sortOrder: (r['sort_order'] as int?) ?? 0,
            ))
        .toList();
  }

  @override
  Future<void> createTag(TagRow t) =>
      _db.insert('tags', {'id': t.id, 'name_enc': t.nameEnc, 'color': t.color});
  @override
  Future<void> deleteTag(String id) => _db.delete('tags', where: 'id = ?', whereArgs: [id]);
  @override
  Future<List<TagRow>> listTags() async {
    final rows = await _db.query('tags');
    return rows
        .map((r) => TagRow(id: r['id'] as String, nameEnc: r['name_enc'] as dynamic, color: r['color'] as String?))
        .toList();
  }
}
