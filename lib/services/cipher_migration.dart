import 'dart:typed_data';

import '../state/vault_repository.dart';
import 'cipher_context.dart';
import 'crypto_service.dart';

/// Converte para o formato v2 os blobs que ainda estiverem no formato antigo.
///
/// Enquanto um campo continua em v1 ele não tem AAD, e nada impede que alguém
/// com acesso ao arquivo copie esse blob para outra linha do SQLite — a leitura
/// funcionaria e o segredo apareceria no registro errado. Re-cifrar amarra cada
/// blob ao seu lugar e fecha isso também para os dados que já existiam.
///
/// Roda inteira dentro de uma transação: ou o cofre passa a v2, ou fica
/// exatamente como estava. Retorna quantos blobs foram convertidos — 0 quando
/// não havia nada a fazer, que é o caso de todo desbloqueio depois do primeiro.
Future<int> migrateCipherToV2({
  required VaultRepository repo,
  required CryptoService crypto,
  required Uint8List dek,
}) {
  return repo.transaction(() => _run(repo, crypto, dek));
}

Future<int> _run(VaultRepository repo, CryptoService crypto, Uint8List dek) async {
  var converted = 0;

  /// Devolve o blob já em v2, ou null se ele não precisava mudar. Decifrar
  /// aceita os dois formatos, então basta olhar a versão para decidir.
  Future<Uint8List?> upgrade(Uint8List? blob, String context) async {
    if (blob == null || crypto.cipherVersionOf(blob) == 2) return null;
    final plain = await crypto.decrypt(blob, dek, context: context);
    converted++;
    return crypto.encrypt(plain, dek, context: context);
  }

  for (final r in await repo.listCredentials()) {
    String c(String field) => CipherContext.credential(r.id, field);
    final title = await upgrade(r.titleEnc, c('title'));
    final username = await upgrade(r.usernameEnc, c('username'));
    final password = await upgrade(r.passwordEnc, c('password'));
    final url = await upgrade(r.urlEnc, c('url'));
    final notes = await upgrade(r.notesEnc, c('notes'));
    final project = await upgrade(r.projectEnc, c('project'));
    if ([title, username, password, url, notes, project].every((b) => b == null)) continue;
    await repo.updateCredential(
      CredentialRow(
        id: r.id,
        titleEnc: title ?? r.titleEnc,
        usernameEnc: username ?? r.usernameEnc,
        passwordEnc: password ?? r.passwordEnc,
        urlEnc: url ?? r.urlEnc,
        notesEnc: notes ?? r.notesEnc,
        projectEnc: project ?? r.projectEnc,
        isFavorite: r.isFavorite,
        strengthScore: r.strengthScore,
        passwordHmac: r.passwordHmac,
        expiresAt: r.expiresAt,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      ),
      await repo.tagsOf(r.id),
    );
  }

  for (final s in await repo.listServers()) {
    String sv(String field) => CipherContext.server(s.id, field);
    final name = await upgrade(s.nameEnc, sv('name'));
    final ip = await upgrade(s.ipEnc, sv('ip'));
    final env = await upgrade(s.environmentEnc, sv('environment'));
    final services = await upgrade(s.servicesEnc, sv('services'));
    final notes = await upgrade(s.notesEnc, sv('notes'));
    if ([name, ip, env, services, notes].any((b) => b != null)) {
      await repo.updateServer(ServerRow(
        id: s.id,
        nameEnc: name ?? s.nameEnc,
        ipEnc: ip ?? s.ipEnc,
        environmentEnc: env ?? s.environmentEnc,
        servicesEnc: services ?? s.servicesEnc,
        notesEnc: notes ?? s.notesEnc,
        isFavorite: s.isFavorite,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
      ));
    }
    for (final c in await repo.commandsOf(s.id)) {
      final label = await upgrade(c.labelEnc, CipherContext.command(c.id, 'label'));
      final command = await upgrade(c.commandEnc, CipherContext.command(c.id, 'command'));
      if (label == null && command == null) continue;
      await repo.updateCommand(CommandRow(
        id: c.id,
        serverId: c.serverId,
        labelEnc: label ?? c.labelEnc,
        commandEnc: command ?? c.commandEnc,
        sortOrder: c.sortOrder,
      ));
    }
  }

  for (final t in await repo.listTags()) {
    final name = await upgrade(t.nameEnc, CipherContext.tag(t.id));
    if (name == null) continue;
    await repo.updateTag(TagRow(id: t.id, nameEnc: name, color: t.color));
  }

  final meta = await repo.loadVaultMeta();
  if (meta != null) {
    final totp = await upgrade(meta.totpSecretEnc, CipherContext.totp);
    if (totp != null) await repo.updateTotpSecret(totp);
  }

  return converted;
}
