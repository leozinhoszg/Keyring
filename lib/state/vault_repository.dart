import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';

class TagRow {
  final String id;
  final Uint8List nameEnc;
  final String? color;
  const TagRow({required this.id, required this.nameEnc, this.color});
}

class VaultMetaRow {
  final Uint8List argon2Salt;
  final String argon2Params;
  final Uint8List wrappedDek;
  final Uint8List totpSecretEnc;
  final String recoveryCodesHash;
  final String settings;
  final String createdAt;

  /// DEK envolvido pela chave de acesso rápido guardada no keystore do SO.
  /// Nulo = acesso rápido desligado. Sozinho, é inútil: sem a metade que mora
  /// no keystore daquele aparelho, não abre nada.
  final Uint8List? wrappedDekQuick;

  /// Vencimento da janela de acesso rápido (ISO-8601). Renovado a cada login
  /// completo; nunca estendido por usar a biometria.
  final String? quickExpiresAt;

  const VaultMetaRow({
    required this.argon2Salt,
    required this.argon2Params,
    required this.wrappedDek,
    required this.totpSecretEnc,
    required this.recoveryCodesHash,
    required this.settings,
    required this.createdAt,
    this.wrappedDekQuick,
    this.quickExpiresAt,
  });
}

class CredentialRow {
  final String id;
  final Uint8List titleEnc;
  final Uint8List? usernameEnc;
  final Uint8List? passwordEnc;
  final Uint8List? urlEnc;
  final Uint8List? notesEnc;
  final Uint8List? projectEnc;
  final int isFavorite;
  final int? strengthScore;
  final String? passwordHmac;
  final String? expiresAt;
  final String createdAt;
  final String updatedAt;
  const CredentialRow({
    required this.id,
    required this.titleEnc,
    this.usernameEnc,
    this.passwordEnc,
    this.urlEnc,
    this.notesEnc,
    this.projectEnc,
    this.isFavorite = 0,
    this.strengthScore,
    this.passwordHmac,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });
  Map<String, Object?> toMap() => {
        'id': id, 'title_enc': titleEnc, 'username_enc': usernameEnc, 'password_enc': passwordEnc,
        'url_enc': urlEnc, 'notes_enc': notesEnc, 'project_enc': projectEnc, 'is_favorite': isFavorite,
        'strength_score': strengthScore, 'password_hmac': passwordHmac, 'expires_at': expiresAt,
        'created_at': createdAt, 'updated_at': updatedAt,
      };
  factory CredentialRow.fromMap(Map<String, Object?> m) => CredentialRow(
        id: m['id'] as String, titleEnc: m['title_enc'] as Uint8List,
        usernameEnc: m['username_enc'] as Uint8List?, passwordEnc: m['password_enc'] as Uint8List?,
        urlEnc: m['url_enc'] as Uint8List?, notesEnc: m['notes_enc'] as Uint8List?,
        projectEnc: m['project_enc'] as Uint8List?, isFavorite: (m['is_favorite'] as int?) ?? 0,
        strengthScore: m['strength_score'] as int?, passwordHmac: m['password_hmac'] as String?,
        expiresAt: m['expires_at'] as String?, createdAt: m['created_at'] as String,
        updatedAt: m['updated_at'] as String,
      );
}

class ServerRow {
  final String id;
  final Uint8List nameEnc;
  final Uint8List? ipEnc;
  final Uint8List? environmentEnc;
  final Uint8List? servicesEnc;
  final Uint8List? notesEnc;
  final int isFavorite;
  final String createdAt;
  final String updatedAt;
  const ServerRow({
    required this.id,
    required this.nameEnc,
    this.ipEnc,
    this.environmentEnc,
    this.servicesEnc,
    this.notesEnc,
    this.isFavorite = 0,
    required this.createdAt,
    required this.updatedAt,
  });
  Map<String, Object?> toMap() => {
        'id': id, 'name_enc': nameEnc, 'ip_enc': ipEnc, 'environment_enc': environmentEnc,
        'services_enc': servicesEnc, 'notes_enc': notesEnc, 'is_favorite': isFavorite,
        'created_at': createdAt, 'updated_at': updatedAt,
      };
  factory ServerRow.fromMap(Map<String, Object?> m) => ServerRow(
        id: m['id'] as String, nameEnc: m['name_enc'] as Uint8List,
        ipEnc: m['ip_enc'] as Uint8List?, environmentEnc: m['environment_enc'] as Uint8List?,
        servicesEnc: m['services_enc'] as Uint8List?, notesEnc: m['notes_enc'] as Uint8List?,
        isFavorite: (m['is_favorite'] as int?) ?? 0, createdAt: m['created_at'] as String,
        updatedAt: m['updated_at'] as String,
      );
}

class CommandRow {
  final String id;
  final String serverId;
  final Uint8List labelEnc;
  final Uint8List commandEnc;
  final int sortOrder;
  const CommandRow({
    required this.id,
    required this.serverId,
    required this.labelEnc,
    required this.commandEnc,
    this.sortOrder = 0,
  });
}

abstract class VaultRepository {
  Future<bool> isSetup();
  Future<void> saveVaultMeta(VaultMetaRow row);
  Future<VaultMetaRow?> loadVaultMeta();

  /// Escreve apenas as colunas do acesso rápido. Passar `(null, null)` desliga.
  /// Separado de [saveVaultMeta] de propósito: aquele reescreve a meta inteira.
  Future<void> updateQuickUnlock(Uint8List? wrapped, String? expiresAt);

  Future<void> createCredential(CredentialRow row, List<String> tagIds);
  Future<void> updateCredential(CredentialRow row, List<String> tagIds);
  Future<void> deleteCredential(String id);
  Future<CredentialRow?> findCredential(String id);
  Future<List<CredentialRow>> listCredentials({bool favorite = false, String? tagId});
  Future<List<String>> tagsOf(String id);
  Future<List<MapEntry<String, String>>> allPasswordHmacs();

  Future<void> createServer(ServerRow row);
  Future<void> updateServer(ServerRow row);
  Future<void> deleteServer(String id);
  Future<ServerRow?> findServer(String id);
  Future<List<ServerRow>> listServers();
  Future<void> addCommand(CommandRow row);
  Future<void> deleteCommand(String id);
  Future<List<CommandRow>> commandsOf(String serverId);

  Future<void> createTag(TagRow row);
  Future<void> deleteTag(String id);
  Future<List<TagRow>> listTags();
}

/// Schema com todos os campos textuais cifrados (colunas `*_enc` em BLOB).
/// Usado no onCreate do banco e nos testes com banco em memória.
Future<void> createSchema(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''CREATE TABLE IF NOT EXISTS vault_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1), argon2_salt BLOB NOT NULL, argon2_params TEXT NOT NULL,
    wrapped_dek BLOB NOT NULL, totp_secret_enc BLOB NOT NULL, recovery_codes_hash TEXT NOT NULL,
    settings TEXT NOT NULL, created_at TEXT NOT NULL,
    wrapped_dek_quick BLOB, quick_expires_at TEXT)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS credentials (
    id TEXT PRIMARY KEY, title_enc BLOB NOT NULL, username_enc BLOB, password_enc BLOB, url_enc BLOB,
    notes_enc BLOB, project_enc BLOB, is_favorite INTEGER NOT NULL DEFAULT 0, strength_score INTEGER,
    password_hmac TEXT, expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
  await db.execute('CREATE TABLE IF NOT EXISTS tags (id TEXT PRIMARY KEY, name_enc BLOB NOT NULL, color TEXT)');
  await db.execute('''CREATE TABLE IF NOT EXISTS credential_tags (
    credential_id TEXT NOT NULL REFERENCES credentials(id) ON DELETE CASCADE,
    tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY (credential_id, tag_id))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS servers (
    id TEXT PRIMARY KEY, name_enc BLOB NOT NULL, ip_enc BLOB, environment_enc BLOB, services_enc BLOB,
    notes_enc BLOB, is_favorite INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS server_commands (
    id TEXT PRIMARY KEY, server_id TEXT NOT NULL REFERENCES servers(id) ON DELETE CASCADE,
    label_enc BLOB NOT NULL, command_enc BLOB NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)''');
}

/// Migrações incrementais entre versões de schema. Cada degrau preserva os dados:
/// apenas ADD/ALTER/CREATE, nunca DROP/DELETE.
///
/// Pública para que `test/migration_test.dart` exercite a migração real do app,
/// em vez de uma imitação que só testaria o sqflite.
Future<void> migrateVault(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE vault_meta ADD COLUMN wrapped_dek_quick BLOB');
    await db.execute('ALTER TABLE vault_meta ADD COLUMN quick_expires_at TEXT');
  }
}
