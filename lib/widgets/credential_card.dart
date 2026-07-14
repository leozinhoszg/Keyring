import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/credential.dart';
import '../state/vault_provider.dart';
import '../theme/proma_palette.dart';
import '../widgets/copy_button.dart';
import '../widgets/secret_field.dart';

class CredentialCard extends StatelessWidget {
  final CredentialSummary c;
  final Map<String, String> tagNames;
  final VoidCallback onEdit;
  final VoidCallback onDeleted;
  const CredentialCard({
    super.key,
    required this.c,
    required this.tagNames,
    required this.onEdit,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final vault = context.read<VaultProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (c.isFavorite) ...[
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  c.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _iconAction(Icons.edit, 'Editar', onEdit),
              _iconAction(Icons.delete, 'Excluir', () async {
                await vault.deleteCredential(c.id);
                onDeleted();
              }),
            ]),
            if (c.project != null && c.project!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(c.project!,
                    style: const TextStyle(fontSize: 12, color: PromaPalette.dim),
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 8),
            if (c.hasUsername)
              Row(children: [
                const Icon(Icons.person_outline, size: 15, color: PromaPalette.dim),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Usuário', style: TextStyle(fontSize: 13, color: PromaPalette.muted)),
                ),
                CopyButton(label: 'Usuário', iconOnly: true, value: () => vault.reveal(c.id, 'username')),
              ]),
            if (c.hasPassword) ...[
              const SizedBox(height: 2),
              SecretField(credentialId: c.id, field: 'password', label: 'Senha'),
            ],
            if (c.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: c.tags
                      .map((t) => Chip(
                            label: Text(tagNames[t] ?? t),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String tip, VoidCallback onTap) => IconButton(
        icon: Icon(icon, size: 16),
        tooltip: tip,
        color: PromaPalette.muted,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        onPressed: onTap,
      );
}
