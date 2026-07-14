import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/session_provider.dart';
import '../theme/proma_palette.dart';

class CopyButton extends StatelessWidget {
  final String label;
  final FutureOr<String> Function() value;
  final bool iconOnly;
  const CopyButton({super.key, required this.label, required this.value, this.iconOnly = false});

  Future<void> _copy(BuildContext context) async {
    final secs = context.read<SessionProvider>().settings.clipboardClearSeconds;
    final v = await value();
    await Clipboard.setData(ClipboardData(text: v));
    if (secs > 0) {
      Timer(Duration(seconds: secs), () => Clipboard.setData(const ClipboardData(text: '')));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copiado — clipboard limpo em ${secs}s')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return IconButton(
        onPressed: () => _copy(context),
        icon: const Icon(Icons.copy, size: 16),
        tooltip: 'Copiar $label',
        color: PromaPalette.muted,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _copy(context),
      icon: const Icon(Icons.copy, size: 14),
      label: Text(label),
    );
  }
}
