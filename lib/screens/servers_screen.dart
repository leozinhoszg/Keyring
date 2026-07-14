import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/vault_provider.dart';
import '../widgets/command_list.dart';
import '../widgets/copy_button.dart';
import '../widgets/server_form.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});
  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    final vault = context.read<VaultProvider>();
    Future.microtask(() => vault.loadServers());
  }

  Future<void> _reload() => context.read<VaultProvider>().loadServers(q: _q);

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar servidor…'),
              onChanged: (v) {
                _q = v;
                _reload();
              },
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Novo'),
            onPressed: () async {
              final ok = await showServerForm(context);
              if (ok == true) _reload();
            },
          ),
        ]),
        const SizedBox(height: 8),
        if (vault.servers.isEmpty)
          const Expanded(child: Center(child: Text('Nenhum servidor cadastrado.')))
        else
          Expanded(
            child: ListView(
              children: vault.servers
                  .map((s) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Text(
                                        [s.environment, s.services]
                                            .where((e) => e != null && e.isNotEmpty)
                                            .join(' · '),
                                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                                if (s.ip != null) CopyButton(label: s.ip!, value: () => s.ip!),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 16),
                                  onPressed: () async {
                                    final ok = await showServerForm(context, server: s);
                                    if (ok == true) _reload();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 16),
                                  onPressed: () async {
                                    await vault.deleteServer(s.id);
                                    _reload();
                                  },
                                ),
                              ]),
                              const Divider(),
                              CommandList(serverId: s.id),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
