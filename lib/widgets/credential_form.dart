import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/credential.dart';
import '../models/tag.dart';
import '../services/strength.dart';
import '../state/vault_provider.dart';
import '../theme/proma_palette.dart';
import '../widgets/password_generator_dialog.dart';
import '../widgets/strength_meter.dart';

Future<bool?> showCredentialForm(BuildContext context,
        {CredentialSummary? credential, required List<Tag> tags}) =>
    showDialog<bool>(context: context, builder: (_) => _CredentialForm(credential: credential, tags: tags));

class _CredentialForm extends StatefulWidget {
  final CredentialSummary? credential;
  final List<Tag> tags;
  const _CredentialForm({this.credential, required this.tags});
  @override
  State<_CredentialForm> createState() => _CredentialFormState();
}

class _CredentialFormState extends State<_CredentialForm> {
  final _title = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController();
  final _project = TextEditingController();
  final _notes = TextEditingController();
  final Set<String> _tagIds = {};
  bool _favorite = false;
  bool _showPassword = false;
  DateTime? _expires;

  @override
  void initState() {
    super.initState();
    final c = widget.credential;
    if (c != null) {
      _title.text = c.title;
      _url.text = c.url ?? '';
      _project.text = c.project ?? '';
      _favorite = c.isFavorite;
      _tagIds.addAll(c.tags);
      _expires = c.expiresAt != null ? DateTime.tryParse(c.expiresAt!) : null;
      final vault = context.read<VaultProvider>();
      Future.microtask(() async {
        _username.text = c.hasUsername ? await vault.reveal(c.id, 'username') : '';
        _password.text = c.hasPassword ? await vault.reveal(c.id, 'password') : '';
        _notes.text = await vault.reveal(c.id, 'notes');
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _username, _password, _url, _project, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (_title.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Informe um título')));
      return;
    }
    final vault = context.read<VaultProvider>();
    final input = CredentialInput(
      title: _title.text,
      username: _username.text,
      password: _password.text,
      url: _url.text,
      notes: _notes.text,
      project: _project.text,
      tagIds: _tagIds.toList(),
      isFavorite: _favorite,
      expiresAt: _expires?.toIso8601String(),
      strengthScore: _password.text.isNotEmpty ? evaluateStrength(_password.text) : null,
    );
    String? dup;
    try {
      if (widget.credential == null) {
        dup = await vault.createCredential(input);
      } else {
        await vault.updateCredential(widget.credential!.id, input);
      }
    } on StateError {
      // O auto-lock disparou com o formulário aberto: a DEK já foi zerada e não
      // há como cifrar. Sem este aviso, o "Salvar" simplesmente não faria nada.
      messenger.showSnackBar(const SnackBar(
          content: Text('O cofre foi bloqueado por inatividade. Desbloqueie e salve de novo.')));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      return;
    }
    if (dup != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Atenção: esta senha já é usada em outra credencial')));
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
        constraints: BoxConstraints(maxWidth: 460, maxHeight: size.height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    widget.credential == null ? 'Nova credencial' : 'Editar credencial',
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
            // Campos
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: _title, decoration: const InputDecoration(hintText: 'Título *')),
                    const SizedBox(height: 14),
                    TextField(controller: _username, decoration: const InputDecoration(hintText: 'Usuário')),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _password,
                          // Escondida por padrão: o formulário fica aberto o
                          // tempo todo da edição, à vista de quem passar.
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            hintText: 'Senha',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword ? Icons.visibility_off : Icons.visibility,
                                size: 18,
                                color: PromaPalette.dim,
                              ),
                              tooltip: _showPassword ? 'Ocultar' : 'Mostrar',
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Gerar'),
                        onPressed: () async {
                          final pw = await showPasswordGenerator(context);
                          if (pw != null) setState(() => _password.text = pw);
                        },
                      ),
                    ]),
                    const SizedBox(height: 8),
                    StrengthMeter(password: _password.text),
                    const SizedBox(height: 14),
                    TextField(controller: _url, decoration: const InputDecoration(hintText: 'URL')),
                    const SizedBox(height: 14),
                    TextField(controller: _project, decoration: const InputDecoration(hintText: 'Projeto')),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'Notas'),
                    ),
                    const SizedBox(height: 14),
                    // Expiração
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          suffixIcon: Icon(Icons.calendar_today, size: 18, color: PromaPalette.dim),
                        ),
                        child: Text(
                          _expires == null ? 'Expira em (opcional)' : _fmt(_expires!),
                          style: TextStyle(
                            color: _expires == null ? PromaPalette.dim : PromaPalette.white,
                          ),
                        ),
                      ),
                    ),
                    if (widget.tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.tags
                            .map((t) => FilterChip(
                                  label: Text(t.name),
                                  selected: _tagIds.contains(t.id),
                                  showCheckmark: false,
                                  onSelected: (v) =>
                                      setState(() => v ? _tagIds.add(t.id) : _tagIds.remove(t.id)),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Favorito (checkbox como na web)
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
            // Ações
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
