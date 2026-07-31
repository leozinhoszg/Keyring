import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/credential.dart';
import '../models/server.dart';
import '../models/server_command.dart';
import '../models/tag.dart';
import '../services/cipher_context.dart';
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

  /// Descarta o que foi decifrado para a tela. Chamado quando o cofre tranca:
  /// sem isto, títulos, URLs e projetos continuariam legíveis na memória do
  /// processo mesmo com a DEK já zerada.
  void clearCache() {
    credentials = [];
    servers = [];
    tags = [];
    notifyListeners();
  }

  // ---- helpers de cripto ----
  // Todo blob é amarrado ao registro e ao campo de onde veio (ver CipherContext).
  Future<Uint8List> _enc(String v, String ctx) => _crypto.encrypt(v, _key, context: ctx);
  Future<Uint8List?> _encN(String? v, String ctx) async =>
      (v == null || v.isEmpty) ? null : await _crypto.encrypt(v, _key, context: ctx);
  Future<String> _dec(Uint8List blob, String ctx) => _crypto.decrypt(blob, _key, context: ctx);
  Future<String?> _decN(Uint8List? blob, String ctx) async =>
      blob == null ? null : await _crypto.decrypt(blob, _key, context: ctx);

  // ---- tags ----
  Future<void> loadTags() async {
    final rows = await _repo.listTags();
    final result = <Tag>[];
    for (final r in rows) {
      result.add(Tag(id: r.id, name: await _dec(r.nameEnc, CipherContext.tag(r.id)), color: r.color));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    tags = result;
    notifyListeners();
  }

  Future<Tag> createTag(String name) async {
    // dedup por nome em memória (nome é cifrado no banco)
    final existing = await _repo.listTags();
    for (final r in existing) {
      final decoded = await _dec(r.nameEnc, CipherContext.tag(r.id));
      if (decoded.toLowerCase() == name.toLowerCase()) {
        return Tag(id: r.id, name: decoded, color: r.color);
      }
    }
    final id = _uuid.v4();
    await _repo.createTag(TagRow(id: id, nameEnc: await _enc(name, CipherContext.tag(id))));
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
        title: await _dec(r.titleEnc, CipherContext.credential(r.id, 'title')),
        url: await _decN(r.urlEnc, CipherContext.credential(r.id, 'url')),
        project: await _decN(r.projectEnc, CipherContext.credential(r.id, 'project')),
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
    String c(String field) => CipherContext.credential(id, field);
    await _repo.createCredential(
      CredentialRow(
        id: id, titleEnc: await _enc(i.title, c('title')),
        usernameEnc: await _encN(i.username, c('username')),
        passwordEnc: await _encN(i.password, c('password')),
        urlEnc: await _encN(i.url, c('url')), notesEnc: await _encN(i.notes, c('notes')),
        projectEnc: await _encN(i.project, c('project')),
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
    String c(String field) => CipherContext.credential(id, field);
    await _repo.updateCredential(
      CredentialRow(
        id: id, titleEnc: await _enc(i.title, c('title')),
        usernameEnc: await _encN(i.username, c('username')),
        passwordEnc: await _encN(i.password, c('password')),
        urlEnc: await _encN(i.url, c('url')), notesEnc: await _encN(i.notes, c('notes')),
        projectEnc: await _encN(i.project, c('project')),
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
    final name = field == 'password' || field == 'username' ? field : 'notes';
    return blob == null ? '' : _dec(blob, CipherContext.credential(id, name));
  }

  // ---- servidores ----
  Future<void> loadServers({String? q}) async {
    final rows = await _repo.listServers();
    final result = <ServerSummary>[];
    for (final r in rows) {
      String s(String field) => CipherContext.server(r.id, field);
      result.add(ServerSummary(
        id: r.id,
        name: await _dec(r.nameEnc, s('name')),
        ip: await _decN(r.ipEnc, s('ip')),
        environment: await _decN(r.environmentEnc, s('environment')),
        services: await _decN(r.servicesEnc, s('services')),
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
    String s(String field) => CipherContext.server(id, field);
    await _repo.createServer(ServerRow(
      id: id, nameEnc: await _enc(i.name, s('name')), ipEnc: await _encN(i.ip, s('ip')),
      environmentEnc: await _encN(i.environment, s('environment')),
      servicesEnc: await _encN(i.services, s('services')),
      notesEnc: await _encN(i.notes, s('notes')), isFavorite: i.isFavorite ? 1 : 0,
      createdAt: _nowIso(), updatedAt: _nowIso(),
    ));
    return id;
  }

  Future<void> updateServer(String id, ServerInput i) async {
    final ex = await _repo.findServer(id);
    if (ex == null) return;
    String s(String field) => CipherContext.server(id, field);
    await _repo.updateServer(ServerRow(
      id: id, nameEnc: await _enc(i.name, s('name')), ipEnc: await _encN(i.ip, s('ip')),
      environmentEnc: await _encN(i.environment, s('environment')),
      servicesEnc: await _encN(i.services, s('services')),
      notesEnc: await _encN(i.notes, s('notes')), isFavorite: i.isFavorite ? 1 : 0,
      createdAt: ex.createdAt, updatedAt: _nowIso(),
    ));
  }

  Future<void> deleteServer(String id) => _repo.deleteServer(id);
  Future<String> revealServerNotes(String id) async {
    final r = await _repo.findServer(id);
    return (r?.notesEnc == null)
        ? ''
        : _dec(r!.notesEnc!, CipherContext.server(id, 'notes'));
  }

  Future<List<ServerCommand>> commandsOf(String serverId) async {
    final rows = await _repo.commandsOf(serverId);
    final result = <ServerCommand>[];
    for (final c in rows) {
      result.add(ServerCommand(
        id: c.id, serverId: c.serverId,
        label: await _dec(c.labelEnc, CipherContext.command(c.id, 'label')),
        command: await _dec(c.commandEnc, CipherContext.command(c.id, 'command')),
        sortOrder: c.sortOrder,
      ));
    }
    return result;
  }

  Future<void> addCommand(String serverId, String label, String command) async {
    final id = _uuid.v4();
    await _repo.addCommand(CommandRow(
      id: id,
      serverId: serverId,
      labelEnc: await _enc(label, CipherContext.command(id, 'label')),
      commandEnc: await _enc(command, CipherContext.command(id, 'command')),
    ));
  }

  Future<void> deleteCommand(String id) => _repo.deleteCommand(id);
}
