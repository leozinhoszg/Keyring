import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server_command.dart';
import '../state/vault_provider.dart';
import '../widgets/copy_button.dart';

class CommandList extends StatefulWidget {
  final String serverId;
  const CommandList({super.key, required this.serverId});
  @override
  State<CommandList> createState() => _CommandListState();
}

class _CommandListState extends State<CommandList> {
  final _label = TextEditingController();
  final _command = TextEditingController();
  List<ServerCommand> _cmds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _cmds = await context.read<VaultProvider>().commandsOf(widget.serverId);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (_label.text.trim().isEmpty || _command.text.trim().isEmpty) return;
    await context.read<VaultProvider>().addCommand(widget.serverId, _label.text, _command.text);
    _label.clear();
    _command.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._cmds.map((c) => ListTile(
                dense: true,
                title: Text(c.label, style: const TextStyle(fontSize: 12)),
                subtitle: Text(c.command, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  CopyButton(label: 'Copiar', value: () => c.command),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 16),
                    onPressed: () async {
                      await context.read<VaultProvider>().deleteCommand(c.id);
                      await _load();
                    },
                  ),
                ]),
              )),
          Row(children: [
            SizedBox(
              width: 120,
              child: TextField(controller: _label, decoration: const InputDecoration(hintText: 'Rótulo')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(controller: _command, decoration: const InputDecoration(hintText: 'ssh deploy@10.0.0.1')),
            ),
            IconButton(icon: const Icon(Icons.add), onPressed: _add),
          ]),
        ],
      );
}
