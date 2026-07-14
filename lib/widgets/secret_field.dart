import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/vault_provider.dart';
import '../theme/proma_palette.dart';
import 'copy_button.dart';

class SecretField extends StatefulWidget {
  final String credentialId;
  final String field;
  final String label;
  const SecretField({super.key, required this.credentialId, required this.field, required this.label});
  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  String? _revealed;

  Future<void> _toggle() async {
    if (_revealed != null) {
      setState(() => _revealed = null);
      return;
    }
    final v = await context.read<VaultProvider>().reveal(widget.credentialId, widget.field);
    if (mounted) setState(() => _revealed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lock_outline, size: 15, color: PromaPalette.dim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _revealed ?? '••••••••••',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: Icon(_revealed != null ? Icons.visibility_off : Icons.visibility, size: 16),
          onPressed: _toggle,
          tooltip: _revealed != null ? 'Ocultar' : 'Revelar',
          color: PromaPalette.muted,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
        CopyButton(
          label: widget.label,
          iconOnly: true,
          value: () => context.read<VaultProvider>().reveal(widget.credentialId, widget.field),
        ),
      ],
    );
  }
}
