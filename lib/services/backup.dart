import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../models/argon2_params.dart';
import '../services/crypto_service.dart';
import '../state/vault_repository.dart';

class BackupService {
  final VaultRepository _repo;
  final CryptoService _crypto;
  final _uuid = const Uuid();
  BackupService(this._repo, this._crypto);

  Future<String?> _dec(Uint8List? blob, Uint8List dek) async =>
      blob == null ? null : await _crypto.decrypt(blob, dek);

  Future<String> export(Uint8List dek, String exportPassword) async {
    final creds = await _repo.listCredentials();
    final credJson = <Map<String, dynamic>>[];
    for (final r in creds) {
      credJson.add({
        'title': await _dec(r.titleEnc, dek),
        'url': await _dec(r.urlEnc, dek),
        'project': await _dec(r.projectEnc, dek),
        'isFavorite': r.isFavorite == 1,
        'expiresAt': r.expiresAt,
        'tags': await _repo.tagsOf(r.id),
        'username': await _dec(r.usernameEnc, dek),
        'password': await _dec(r.passwordEnc, dek),
        'notes': await _dec(r.notesEnc, dek),
      });
    }
    final servers = await _repo.listServers();
    final srvJson = <Map<String, dynamic>>[];
    for (final s in servers) {
      final cmds = await _repo.commandsOf(s.id);
      final cmdJson = <Map<String, dynamic>>[];
      for (final c in cmds) {
        cmdJson.add({
          'label': await _dec(c.labelEnc, dek),
          'command': await _dec(c.commandEnc, dek),
          'sortOrder': c.sortOrder,
        });
      }
      srvJson.add({
        'name': await _dec(s.nameEnc, dek),
        'ip': await _dec(s.ipEnc, dek),
        'environment': await _dec(s.environmentEnc, dek),
        'services': await _dec(s.servicesEnc, dek),
        'isFavorite': s.isFavorite == 1,
        'notes': await _dec(s.notesEnc, dek),
        'commands': cmdJson,
      });
    }
    final tags = await _repo.listTags();
    final tagJson = <Map<String, dynamic>>[];
    for (final t in tags) {
      tagJson.add({'name': await _dec(t.nameEnc, dek), 'color': t.color});
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

  Future<int> import(Uint8List dek, String file, String exportPassword) async {
    final envelope = jsonDecode(utf8.decode(base64Decode(file.trim()))) as Map<String, dynamic>;
    final salt = base64Decode(envelope['salt'] as String);
    final params = Argon2Params.fromJson(envelope['params'] as Map<String, dynamic>);
    final kek = await _crypto.deriveKek(exportPassword, Uint8List.fromList(salt), params);
    final payload = jsonDecode(
      await _crypto.decrypt(Uint8List.fromList(base64Decode(envelope['data'] as String)), kek),
    ) as Map<String, dynamic>;

    var imported = 0;
    final now = DateTime.now().toIso8601String();

    // dedup de tags por nome (nomes cifrados no banco → compara em memória)
    final tagIdByName = <String, String>{};
    for (final t in await _repo.listTags()) {
      tagIdByName[(await _crypto.decrypt(t.nameEnc, dek)).toLowerCase()] = t.id;
    }
    for (final t in (payload['tags'] as List? ?? [])) {
      final name = t['name'] as String;
      if (!tagIdByName.containsKey(name.toLowerCase())) {
        final id = _uuid.v4();
        await _repo.createTag(TagRow(id: id, nameEnc: await _crypto.encrypt(name, dek), color: t['color'] as String?));
        tagIdByName[name.toLowerCase()] = id;
      }
    }
    for (final c in (payload['credentials'] as List? ?? [])) {
      await _repo.createCredential(
        CredentialRow(
          id: _uuid.v4(),
          titleEnc: await _crypto.encrypt(c['title'] as String, dek),
          usernameEnc: await _encN(c['username'], dek),
          passwordEnc: await _encN(c['password'], dek),
          urlEnc: await _encN(c['url'], dek),
          notesEnc: await _encN(c['notes'], dek),
          projectEnc: await _encN(c['project'], dek),
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
      await _repo.createServer(ServerRow(
        id: id,
        nameEnc: await _crypto.encrypt(s['name'] as String, dek),
        ipEnc: await _encN(s['ip'], dek),
        environmentEnc: await _encN(s['environment'], dek),
        servicesEnc: await _encN(s['services'], dek),
        notesEnc: await _encN(s['notes'], dek),
        isFavorite: (s['isFavorite'] as bool? ?? false) ? 1 : 0,
        createdAt: now,
        updatedAt: now,
      ));
      for (final cmd in (s['commands'] as List? ?? [])) {
        await _repo.addCommand(CommandRow(
          id: _uuid.v4(),
          serverId: id,
          labelEnc: await _crypto.encrypt(cmd['label'] as String, dek),
          commandEnc: await _crypto.encrypt(cmd['command'] as String, dek),
          sortOrder: (cmd['sortOrder'] as int?) ?? 0,
        ));
      }
      imported++;
    }
    return imported;
  }

  Future<Uint8List?> _encN(Object? v, Uint8List dek) async =>
      (v == null || (v as String).isEmpty) ? null : await _crypto.encrypt(v, dek);
}
