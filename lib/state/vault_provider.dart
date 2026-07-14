import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/credential.dart';
import '../models/server.dart';
import '../models/server_command.dart';
import '../models/tag.dart';
import '../services/crypto_service.dart';
import 'vault_repository.dart';

class VaultProvider extends ChangeNotifier {
  final VaultRepository _repo;
  final CryptoService _crypto;
  final Uint8List? Function() _dek;
  final _uuid = const Uuid();

  VaultProvider(this._repo, this._crypto, this._dek);

  VaultRepository get repository => _repo;

  Uint8List get _key {
    final k = _dek();
    if (k == null) throw StateError('Cofre bloqueado');
    return k;
  }

  List<CredentialSummary> credentials = [];
  List<ServerSummary> servers = [];
  List<Tag> tags = [];

  String _nowIso() => DateTime.now().toIso8601String();

  // ---- helpers de cripto ----
  Future<Uint8List> _enc(String v) => _crypto.encrypt(v, _key);
  Future<Uint8List?> _encN(String? v) async =>
      (v == null || v.isEmpty) ? null : await _crypto.encrypt(v, _key);
  Future<String> _dec(Uint8List blob) => _crypto.decrypt(blob, _key);
  Future<String?> _decN(Uint8List? blob) async => blob == null ? null : await _crypto.decrypt(blob, _key);

  // ---- tags ----
  Future<void> loadTags() async {
    final rows = await _repo.listTags();
    final result = <Tag>[];
    for (final r in rows) {
      result.add(Tag(id: r.id, name: await _dec(r.nameEnc), color: r.color));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    tags = result;
    notifyListeners();
  }

  Future<Tag> createTag(String name) async {
    // dedup por nome em memória (nome é cifrado no banco)
    final existing = await _repo.listTags();
    for (final r in existing) {
      if ((await _dec(r.nameEnc)).toLowerCase() == name.toLowerCase()) {
        return Tag(id: r.id, name: await _dec(r.nameEnc), color: r.color);
      }
    }
    final id = _uuid.v4();
    await _repo.createTag(TagRow(id: id, nameEnc: await _enc(name)));
    await loadTags();
    return Tag(id: id, name: name);
  }

  Future<void> deleteTag(String id) async {
    await _repo.deleteTag(id);
    await loadTags();
  }

  // ---- credenciais ----
  Future<void> loadCredentials({String? q, String? tagId, bool favorite = false}) async {
    final rows = await _repo.listCredentials(favorite: favorite, tagId: tagId);
    final result = <CredentialSummary>[];
    for (final r in rows) {
      result.add(CredentialSummary(
        id: r.id,
        title: await _dec(r.titleEnc),
        url: await _decN(r.urlEnc),
        project: await _decN(r.projectEnc),
        isFavorite: r.isFavorite == 1,
        tags: await _repo.tagsOf(r.id),
        hasUsername: r.usernameEnc != null,
        hasPassword: r.passwordEnc != null,
        strengthScore: r.strengthScore,
        expiresAt: r.expiresAt,
      ));
    }
    // busca textual em memória (título/projeto/URL já decifrados)
    var filtered = result;
    if (q != null && q.trim().isNotEmpty) {
      final needle = q.toLowerCase();
      filtered = result.where((c) {
        return c.title.toLowerCase().contains(needle) ||
            (c.project?.toLowerCase().contains(needle) ?? false) ||
            (c.url?.toLowerCase().contains(needle) ?? false);
      }).toList();
    }
    filtered.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    credentials = filtered;
    notifyListeners();
  }

  Future<String?> createCredential(CredentialInput i) async {
    final id = _uuid.v4();
    String? hmac;
    String? duplicateOf;
    if (i.password != null && i.password!.isNotEmpty) {
      hmac = await _crypto.hmacHex(i.password!, _key);
      for (final e in await _repo.allPasswordHmacs()) {
        if (e.value == hmac) {
          duplicateOf = e.key;
          break;
        }
      }
    }
    await _repo.createCredential(
      CredentialRow(
        id: id, titleEnc: await _enc(i.title),
        usernameEnc: await _encN(i.username), passwordEnc: await _encN(i.password),
        urlEnc: await _encN(i.url), notesEnc: await _encN(i.notes), projectEnc: await _encN(i.project),
        isFavorite: i.isFavorite ? 1 : 0, strengthScore: i.strengthScore, passwordHmac: hmac,
        expiresAt: i.expiresAt, createdAt: _nowIso(), updatedAt: _nowIso(),
      ),
      i.tagIds,
    );
    return duplicateOf;
  }

  Future<void> updateCredential(String id, CredentialInput i) async {
    final existing = await _repo.findCredential(id);
    if (existing == null) return;
    await _repo.updateCredential(
      CredentialRow(
        id: id, titleEnc: await _enc(i.title),
        usernameEnc: await _encN(i.username), passwordEnc: await _encN(i.password),
        urlEnc: await _encN(i.url), notesEnc: await _encN(i.notes), projectEnc: await _encN(i.project),
        isFavorite: i.isFavorite ? 1 : 0, strengthScore: i.strengthScore,
        passwordHmac: (i.password != null && i.password!.isNotEmpty)
            ? await _crypto.hmacHex(i.password!, _key)
            : null,
        expiresAt: i.expiresAt, createdAt: existing.createdAt, updatedAt: _nowIso(),
      ),
      i.tagIds,
    );
  }

  Future<void> deleteCredential(String id) => _repo.deleteCredential(id);

  Future<String> reveal(String id, String field) async {
    final r = await _repo.findCredential(id);
    if (r == null) return '';
    final blob = field == 'password' ? r.passwordEnc : field == 'username' ? r.usernameEnc : r.notesEnc;
    return blob == null ? '' : _crypto.decrypt(blob, _key);
  }

  // ---- servidores ----
  Future<void> loadServers({String? q}) async {
    final rows = await _repo.listServers();
    final result = <ServerSummary>[];
    for (final r in rows) {
      result.add(ServerSummary(
        id: r.id,
        name: await _dec(r.nameEnc),
        ip: await _decN(r.ipEnc),
        environment: await _decN(r.environmentEnc),
        services: await _decN(r.servicesEnc),
        isFavorite: r.isFavorite == 1,
        hasNotes: r.notesEnc != null,
      ));
    }
    var filtered = result;
    if (q != null && q.trim().isNotEmpty) {
      final needle = q.toLowerCase();
      filtered = result.where((s) {
        return s.name.toLowerCase().contains(needle) ||
            (s.ip?.toLowerCase().contains(needle) ?? false) ||
            (s.environment?.toLowerCase().contains(needle) ?? false);
      }).toList();
    }
    filtered.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    servers = filtered;
    notifyListeners();
  }

  Future<String> createServer(ServerInput i) async {
    final id = _uuid.v4();
    await _repo.createServer(ServerRow(
      id: id, nameEnc: await _enc(i.name), ipEnc: await _encN(i.ip),
      environmentEnc: await _encN(i.environment), servicesEnc: await _encN(i.services),
      notesEnc: await _encN(i.notes), isFavorite: i.isFavorite ? 1 : 0,
      createdAt: _nowIso(), updatedAt: _nowIso(),
    ));
    return id;
  }

  Future<void> updateServer(String id, ServerInput i) async {
    final ex = await _repo.findServer(id);
    if (ex == null) return;
    await _repo.updateServer(ServerRow(
      id: id, nameEnc: await _enc(i.name), ipEnc: await _encN(i.ip),
      environmentEnc: await _encN(i.environment), servicesEnc: await _encN(i.services),
      notesEnc: await _encN(i.notes), isFavorite: i.isFavorite ? 1 : 0,
      createdAt: ex.createdAt, updatedAt: _nowIso(),
    ));
  }

  Future<void> deleteServer(String id) => _repo.deleteServer(id);
  Future<String> revealServerNotes(String id) async {
    final r = await _repo.findServer(id);
    return (r?.notesEnc == null) ? '' : _crypto.decrypt(r!.notesEnc!, _key);
  }

  Future<List<ServerCommand>> commandsOf(String serverId) async {
    final rows = await _repo.commandsOf(serverId);
    final result = <ServerCommand>[];
    for (final c in rows) {
      result.add(ServerCommand(
        id: c.id, serverId: c.serverId,
        label: await _dec(c.labelEnc), command: await _dec(c.commandEnc), sortOrder: c.sortOrder,
      ));
    }
    return result;
  }

  Future<void> addCommand(String serverId, String label, String command) async => _repo.addCommand(
        CommandRow(id: _uuid.v4(), serverId: serverId, labelEnc: await _enc(label), commandEnc: await _enc(command)),
      );
  Future<void> deleteCommand(String id) => _repo.deleteCommand(id);
}
