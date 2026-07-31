import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server.dart';
import '../state/vault_provider.dart';
import '../theme/proma_palette.dart';

Future<bool?> showServerForm(BuildContext context, {ServerSummary? server}) =>
    showDialog<bool>(context: context, builder: (_) => _ServerForm(server: server));

class _ServerForm extends StatefulWidget {
  final ServerSummary? server;
  const _ServerForm({this.server});
  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _env = TextEditingController();
  final _services = TextEditingController();
  final _notes = TextEditingController();
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    final s = widget.server;
    if (s != null) {
      _name.text = s.name;
      _ip.text = s.ip ?? '';
      _env.text = s.environment ?? '';
      _services.text = s.services ?? '';
      _favorite = s.isFavorite;
      if (s.hasNotes) {
        context.read<VaultProvider>().revealServerNotes(s.id).then((v) {
          _notes.text = v;
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _ip, _env, _services, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Informe um nome')));
      return;
    }
    final v = context.read<VaultProvider>();
    final navigator = Navigator.of(context);
    final input = ServerInput(
      name: _name.text,
      ip: _ip.text,
      environment: _env.text,
      services: _services.text,
      notes: _notes.text,
      isFavorite: _favorite,
    );
    try {
      if (widget.server == null) {
        await v.createServer(input);
      } else {
        await v.updateServer(widget.server!.id, input);
      }
    } on StateError {
      messenger.showSnackBar(const SnackBar(
          content: Text('O cofre foi bloqueado por inatividade. Desbloqueie e salve de novo.')));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: wide ? 40 : 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: size.height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    widget.server == null ? 'Novo servidor' : 'Editar servidor',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: PromaPalette.dim,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: _name, decoration: const InputDecoration(hintText: 'Nome *')),
                    const SizedBox(height: 14),
                    TextField(controller: _ip, decoration: const InputDecoration(hintText: 'IP')),
                    const SizedBox(height: 14),
                    TextField(controller: _env, decoration: const InputDecoration(hintText: 'Ambiente (prod, staging…)')),
                    const SizedBox(height: 14),
                    TextField(controller: _services, decoration: const InputDecoration(hintText: 'Serviços (nginx, postgres…)')),
                    const SizedBox(height: 14),
                    TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(hintText: 'Notas')),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setState(() => _favorite = !_favorite),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Checkbox(
                            value: _favorite,
                            onChanged: (v) => setState(() => _favorite = v ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 8),
                          const Text('Favorito'),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: _save, child: const Text('Salvar')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
