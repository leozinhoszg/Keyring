import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/backup.dart';
import '../state/session_provider.dart';
import '../state/vault_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _newTag = TextEditingController();
  final _exportPw = TextEditingController();
  final _importPw = TextEditingController();

  @override
  void initState() {
    super.initState();
    final vault = context.read<VaultProvider>();
    Future.microtask(vault.loadTags);
  }

  BackupService _backup() {
    final vault = context.read<VaultProvider>();
    return BackupService(vault.repository, context.read<SessionProvider>().crypto);
  }

  Future<void> _export() async {
    if (_exportPw.text.length < 8) return _toast('Senha de exportação: 8+ caracteres');
    final messenger = ScaffoldMessenger.of(context);
    final dek = context.read<SessionProvider>().dek!;
    final backup = _backup();
    final content = await backup.export(dek, _exportPw.text);
    final dir = await getApplicationDocumentsDirectory();
    // nome com data/hora legível; nunca sobrescreve um backup existente
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    var path = p.join(dir.path, 'keyring-backup-$stamp.vault');
    var i = 2;
    while (await File(path).exists()) {
      path = p.join(dir.path, 'keyring-backup-${stamp}_$i.vault');
      i++;
    }
    await File(path).writeAsString(content);
    messenger.showSnackBar(SnackBar(content: Text('Backup salvo em: $path')));
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final vault = context.read<VaultProvider>();
    final dek = context.read<SessionProvider>().dek!;
    final backup = _backup();
    final res = await FilePicker.pickFiles(withData: true, dialogTitle: 'Escolher backup .vault');
    if (res == null) return;
    final f = res.files.single;
    // leitura robusta: prefere o caminho do arquivo (desktop); fallback para os bytes
    String content;
    if (f.path != null) {
      content = await File(f.path!).readAsString();
    } else if (f.bytes != null) {
      content = utf8.decode(f.bytes!);
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('Não foi possível ler o arquivo selecionado.')));
      return;
    }
    try {
      final n = await backup.import(dek, content, _importPw.text);
      await vault.loadCredentials();
      messenger.showSnackBar(SnackBar(content: Text('$n itens importados')));
    } on SecretBoxAuthenticationError {
      messenger.showSnackBar(const SnackBar(content: Text('Senha do backup incorreta.')));
    } on FormatException {
      messenger.showSnackBar(const SnackBar(content: Text('Arquivo de backup inválido ou corrompido.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Falha ao importar: $e')));
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final settings = context.read<SessionProvider>().settings;
    return ListView(children: [
      const Text('Configurações', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tags / categorias', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: vault.tags
                  .map((t) => Chip(label: Text(t.name), onDeleted: () => vault.deleteTag(t.id)))
                  .toList(),
            ),
            Row(children: [
              Expanded(child: TextField(controller: _newTag, decoration: const InputDecoration(hintText: 'Nova tag'))),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () async {
                  if (_newTag.text.trim().isEmpty) return;
                  await vault.createTag(_newTag.text.trim());
                  _newTag.clear();
                },
              ),
            ]),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Segurança', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('Auto-lock após ${settings.autoLockMinutes} min de inatividade.'),
            Text('Clipboard limpo ${settings.clipboardClearSeconds}s após copiar.'),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Backup', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _exportPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha do backup (exportar)'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _export, child: const Text('Exportar .vault')),
            const Divider(height: 24),
            TextField(
              controller: _importPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha do backup (importar)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _import, child: const Text('Importar .vault')),
          ]),
        ),
      ),
    ]);
  }
}
