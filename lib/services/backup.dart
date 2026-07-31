import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../models/argon2_params.dart';
import '../services/cipher_context.dart';
import '../services/crypto_service.dart';
import '../state/vault_repository.dart';

/// Teto do arquivo `.vault` aceito no import (32 MiB em base64 — muitas ordens
/// de grandeza acima de um cofre real). Sem ele, um arquivo escolhido por
/// engano, ou fabricado, é carregado inteiro na memória antes de qualquer
/// validação: trava o app sem nem chegar a decifrar.
const int kMaxBackupFileBytes = 32 * 1024 * 1024;

/// Arquivo maior que [kMaxBackupFileBytes]. Recusado antes de decifrar.
class BackupTooLargeException implements Exception {
  final int bytes;
  const BackupTooLargeException(this.bytes);
  @override
  String toString() =>
      'Arquivo de backup grande demais (${(bytes / 1024 / 1024).toStringAsFixed(1)} MB). '
      'O limite é ${kMaxBackupFileBytes ~/ 1024 ~/ 1024} MB.';
}

class BackupService {
  final VaultRepository _repo;
  final CryptoService _crypto;
  final _uuid = const Uuid();
  BackupService(this._repo, this._crypto);

  Future<String?> _dec(Uint8List? blob, Uint8List dek, String ctx) async =>
      blob == null ? null : await _crypto.decrypt(blob, dek, context: ctx);

  Future<String> export(Uint8List dek, String exportPassword) async {
    final creds = await _repo.listCredentials();
    final credJson = <Map<String, dynamic>>[];
    for (final r in creds) {
      String c(String field) => CipherContext.credential(r.id, field);
      credJson.add({
        'title': await _dec(r.titleEnc, dek, c('title')),
        'url': await _dec(r.urlEnc, dek, c('url')),
        'project': await _dec(r.projectEnc, dek, c('project')),
        'isFavorite': r.isFavorite == 1,
        'expiresAt': r.expiresAt,
        'tags': await _repo.tagsOf(r.id),
        'username': await _dec(r.usernameEnc, dek, c('username')),
        'password': await _dec(r.passwordEnc, dek, c('password')),
        'notes': await _dec(r.notesEnc, dek, c('notes')),
      });
    }
    final servers = await _repo.listServers();
    final srvJson = <Map<String, dynamic>>[];
    for (final s in servers) {
      String sv(String field) => CipherContext.server(s.id, field);
      final cmds = await _repo.commandsOf(s.id);
      final cmdJson = <Map<String, dynamic>>[];
      for (final c in cmds) {
        cmdJson.add({
          'label': await _dec(c.labelEnc, dek, CipherContext.command(c.id, 'label')),
          'command': await _dec(c.commandEnc, dek, CipherContext.command(c.id, 'command')),
          'sortOrder': c.sortOrder,
        });
      }
      srvJson.add({
        'name': await _dec(s.nameEnc, dek, sv('name')),
        'ip': await _dec(s.ipEnc, dek, sv('ip')),
        'environment': await _dec(s.environmentEnc, dek, sv('environment')),
        'services': await _dec(s.servicesEnc, dek, sv('services')),
        'isFavorite': s.isFavorite == 1,
        'notes': await _dec(s.notesEnc, dek, sv('notes')),
        'commands': cmdJson,
      });
    }
    final tags = await _repo.listTags();
    final tagJson = <Map<String, dynamic>>[];
    for (final t in tags) {
      tagJson.add({
        'name': await _dec(t.nameEnc, dek, CipherContext.tag(t.id)),
        'color': t.color,
      });
    }
    final payload = jsonEncode({'credentials': credJson, 'servers': srvJson, 'tags': tagJson});

    const params = Argon2Params();
    final salt = _crypto.randomSalt();
    final kek = await _crypto.deriveKek(exportPassword, salt, params);
    final blob = await _crypto.encrypt(payload, kek);
    final envelope = {
      'v': 1,
      'salt': base64Encode(salt),
      'params': params.toJson(),
      'data': base64Encode(blob),
    };
    return base64Encode(utf8.encode(jsonEncode(envelope)));
  }

  /// Importa um `.vault`. Ou entra tudo, ou nada: um item malformado no meio
  /// desfaz o que já havia sido gravado, em vez de deixar o cofre com meio
  /// backup dentro — estado que o usuário não tem como distinguir do certo.
  Future<int> import(Uint8List dek, String file, String exportPassword) async {
    if (file.length > kMaxBackupFileBytes) {
      throw BackupTooLargeException(file.length);
    }
    final envelope = jsonDecode(utf8.decode(base64Decode(file.trim()))) as Map<String, dynamic>;
    final salt = base64Decode(envelope['salt'] as String);
    final params = Argon2Params.fromJson(envelope['params'] as Map<String, dynamic>);
    final kek = await _crypto.deriveKek(exportPassword, Uint8List.fromList(salt), params);
    final payload = jsonDecode(
      await _crypto.decrypt(Uint8List.fromList(base64Decode(envelope['data'] as String)), kek),
    ) as Map<String, dynamic>;

    return _repo.transaction(() => _writeAll(payload, dek));
  }

  Future<int> _writeAll(Map<String, dynamic> payload, Uint8List dek) async {
    var imported = 0;
    final now = DateTime.now().toIso8601String();

    // dedup de tags por nome (nomes cifrados no banco → compara em memória)
    final tagIdByName = <String, String>{};
    for (final t in await _repo.listTags()) {
      final name = await _crypto.decrypt(t.nameEnc, dek, context: CipherContext.tag(t.id));
      tagIdByName[name.toLowerCase()] = t.id;
    }
    for (final t in (payload['tags'] as List? ?? [])) {
      final name = t['name'] as String;
      if (!tagIdByName.containsKey(name.toLowerCase())) {
        final id = _uuid.v4();
        await _repo.createTag(TagRow(
          id: id,
          nameEnc: await _crypto.encrypt(name, dek, context: CipherContext.tag(id)),
          color: t['color'] as String?,
        ));
        tagIdByName[name.toLowerCase()] = id;
      }
    }
    for (final c in (payload['credentials'] as List? ?? [])) {
      final id = _uuid.v4();
      String cx(String field) => CipherContext.credential(id, field);
      await _repo.createCredential(
        CredentialRow(
          id: id,
          titleEnc: await _crypto.encrypt(c['title'] as String, dek, context: cx('title')),
          usernameEnc: await _encN(c['username'], dek, cx('username')),
          passwordEnc: await _encN(c['password'], dek, cx('password')),
          urlEnc: await _encN(c['url'], dek, cx('url')),
          notesEnc: await _encN(c['notes'], dek, cx('notes')),
          projectEnc: await _encN(c['project'], dek, cx('project')),
          isFavorite: (c['isFavorite'] as bool? ?? false) ? 1 : 0,
          passwordHmac: c['password'] == null ? null : await _crypto.hmacHex(c['password'] as String, dek),
          expiresAt: c['expiresAt'] as String?,
          createdAt: now,
          updatedAt: now,
        ),
        [for (final n in (c['tags'] as List? ?? [])) if (tagIdByName[(n as String).toLowerCase()] != null) tagIdByName[n.toLowerCase()]!],
      );
      imported++;
    }
    for (final s in (payload['servers'] as List? ?? [])) {
      final id = _uuid.v4();
      String sx(String field) => CipherContext.server(id, field);
      await _repo.createServer(ServerRow(
        id: id,
        nameEnc: await _crypto.encrypt(s['name'] as String, dek, context: sx('name')),
        ipEnc: await _encN(s['ip'], dek, sx('ip')),
        environmentEnc: await _encN(s['environment'], dek, sx('environment')),
        servicesEnc: await _encN(s['services'], dek, sx('services')),
        notesEnc: await _encN(s['notes'], dek, sx('notes')),
        isFavorite: (s['isFavorite'] as bool? ?? false) ? 1 : 0,
        createdAt: now,
        updatedAt: now,
      ));
      for (final cmd in (s['commands'] as List? ?? [])) {
        final cmdId = _uuid.v4();
        await _repo.addCommand(CommandRow(
          id: cmdId,
          serverId: id,
          labelEnc: await _crypto.encrypt(cmd['label'] as String, dek,
              context: CipherContext.command(cmdId, 'label')),
          commandEnc: await _crypto.encrypt(cmd['command'] as String, dek,
              context: CipherContext.command(cmdId, 'command')),
          sortOrder: (cmd['sortOrder'] as int?) ?? 0,
        ));
      }
      imported++;
    }
    return imported;
  }

  Future<Uint8List?> _encN(Object? v, Uint8List dek, String ctx) async =>
      (v == null || (v as String).isEmpty) ? null : await _crypto.encrypt(v, dek, context: ctx);
}
