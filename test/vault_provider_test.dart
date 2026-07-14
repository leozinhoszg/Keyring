import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/models/credential.dart';
import 'package:keyring/models/server.dart';
import 'package:keyring/services/crypto_service.dart';
import 'package:keyring/state/vault_repository.dart';
import 'package:keyring/state/vault_repository_io.dart';
import 'package:keyring/state/vault_provider.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<(VaultProvider, Database)> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    final crypto = CryptoService();
    final dek = crypto.generateDek();
    final provider = VaultProvider(SqliteVaultRepository(db), crypto, () => dek);
    return (provider, db);
  }

  test('título é cifrado no disco e decifrado ao listar', () async {
    final (provider, db) = await fresh();
    await provider.createCredential(const CredentialInput(title: 'GitHub', password: 's3nha', project: 'infra'));
    // no banco, o title_enc NÃO contém o texto "GitHub"
    final raw = await db.query('credentials');
    final titleBlob = raw.first['title_enc'] as List<int>;
    expect(String.fromCharCodes(titleBlob), isNot(contains('GitHub')));
    // ao listar, o provider decifra
    await provider.loadCredentials();
    expect(provider.credentials.first.title, 'GitHub');
    expect(provider.credentials.first.project, 'infra');
  });

  test('busca em memória por título/projeto', () async {
    final (provider, _) = await fresh();
    await provider.createCredential(const CredentialInput(title: 'GitHub', project: 'infra'));
    await provider.createCredential(const CredentialInput(title: 'GitLab', project: 'devops'));
    await provider.loadCredentials(q: 'hub');
    expect(provider.credentials.length, 1);
    expect(provider.credentials.first.title, 'GitHub');
    await provider.loadCredentials(q: 'devops');
    expect(provider.credentials.length, 1);
    expect(provider.credentials.first.title, 'GitLab');
  });

  test('reveal decifra a senha sob demanda', () async {
    final (provider, _) = await fresh();
    await provider.createCredential(const CredentialInput(title: 'X', password: 's3nha'));
    await provider.loadCredentials();
    final id = provider.credentials.first.id;
    expect(await provider.reveal(id, 'password'), 's3nha');
  });

  test('detecta duplicata de senha', () async {
    final (provider, _) = await fresh();
    await provider.createCredential(const CredentialInput(title: 'A', password: 'igual'));
    final dup = await provider.createCredential(const CredentialInput(title: 'B', password: 'igual'));
    expect(dup, isNotNull);
  });

  test('tag: dedup por nome (nome cifrado no banco)', () async {
    final (provider, db) = await fresh();
    final t1 = await provider.createTag('prod');
    final t2 = await provider.createTag('prod');
    expect(t1.id, t2.id);
    // nome cifrado no disco
    final raw = await db.query('tags');
    final nameBlob = raw.first['name_enc'] as List<int>;
    expect(String.fromCharCodes(nameBlob), isNot(contains('prod')));
  });

  test('servidor: nome/comandos cifrados e decifrados', () async {
    final (provider, db) = await fresh();
    final id = await provider.createServer(const ServerInput(name: 'web-01', ip: '10.0.0.1', environment: 'prod'));
    await provider.addCommand(id, 'ssh', 'ssh deploy@10.0.0.1');
    // no disco, nada legível
    final rawS = await db.query('servers');
    expect(String.fromCharCodes(rawS.first['name_enc'] as List<int>), isNot(contains('web-01')));
    final rawC = await db.query('server_commands');
    expect(String.fromCharCodes(rawC.first['command_enc'] as List<int>), isNot(contains('ssh')));
    // ao carregar, decifra
    await provider.loadServers();
    expect(provider.servers.first.name, 'web-01');
    final cmds = await provider.commandsOf(id);
    expect(cmds.first.command, 'ssh deploy@10.0.0.1');
  });
}
