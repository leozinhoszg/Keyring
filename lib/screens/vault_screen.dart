import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/vault_provider.dart';
import '../widgets/credential_card.dart';
import '../widgets/credential_form.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String _q = '';
  String? _tag;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    final v = context.read<VaultProvider>();
    await v.loadTags();
    await v.loadCredentials(q: _q, tagId: _tag, favorite: _favorite);
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final tagNames = {for (final t in vault.tags) t.id: t.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por título, projeto ou URL…',
              ),
              onChanged: (v) {
                _q = v;
                _reload();
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.star, color: _favorite ? Colors.amber : null),
            onPressed: () {
              setState(() => _favorite = !_favorite);
              _reload();
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nova'),
            onPressed: () async {
              final ok = await showCredentialForm(context, tags: vault.tags);
              if (ok == true) _reload();
            },
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 4, children: [
          ChoiceChip(
            label: const Text('Todas'),
            selected: _tag == null,
            onSelected: (_) {
              setState(() => _tag = null);
              _reload();
            },
          ),
          ...vault.tags.map((t) => ChoiceChip(
                label: Text(t.name),
                selected: _tag == t.id,
                onSelected: (_) {
                  setState(() => _tag = t.id);
                  _reload();
                },
              )),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: vault.credentials.isEmpty
              ? const Center(child: Text('Nenhuma credencial encontrada.'))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    mainAxisExtent: 200,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: vault.credentials.length,
                  itemBuilder: (_, i) {
                    final c = vault.credentials[i];
                    return CredentialCard(
                      c: c,
                      tagNames: tagNames,
                      onEdit: () async {
                        final ok = await showCredentialForm(context, credential: c, tags: vault.tags);
                        if (ok == true) _reload();
                      },
                      onDeleted: _reload,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
