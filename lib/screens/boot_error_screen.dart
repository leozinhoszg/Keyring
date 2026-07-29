import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/proma_palette.dart';

/// Mostrada quando a inicialização falha antes do runApp normal.
///
/// Sem ela, uma exceção no bootstrap deixa o processo vivo com a janela
/// invisível — o runner nativo só chama Show() no primeiro frame. Qualquer
/// coisa renderizada aqui é o que separa "erro legível" de "o app não abre".
class BootErrorApp extends StatelessWidget {
  final String error;
  final String stack;
  const BootErrorApp({super.key, required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keyring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: PromaPalette.darkest,
        cardColor: PromaPalette.dark,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.error_outline, size: 44, color: PromaPalette.accent),
                      const SizedBox(height: 12),
                      const Text(
                        'O Keyring não conseguiu abrir',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ocorreu um erro ao preparar o cofre. Seus dados não foram '
                        'alterados — o vault continua no disco, junto dos backups '
                        'automáticos (.bak) criados antes de qualquer migração.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PromaPalette.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: PromaPalette.elevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: PromaPalette.border),
                        ),
                        child: SelectableText(
                          error,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copiar detalhes do erro'),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: '$error\n\n$stack')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
