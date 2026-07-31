import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/session_provider.dart';
import '../theme/proma_palette.dart';
import '../widgets/keyring_background.dart';

/// Entrada pelo código de recuperação, para quem perdeu o autenticador.
///
/// Termina obrigatoriamente na reconfiguração do TOTP: entrar sem trocar o
/// segredo deixaria o usuário gastando um código de recuperação a cada
/// desbloqueio, até acabarem.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _pw = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  SetupResult? _novoTotp;
  int _restantes = 0;

  @override
  void dispose() {
    _pw.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionProvider>();
    bool ok;
    try {
      ok = await session.unlockWithRecoveryCode(_pw.text, _code.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Erro ao abrir o cofre: $e';
      });
      return;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Senha mestra ou código de recuperação inválidos.';
      });
      return;
    }
    // Entrou: já troca o segredo TOTP e mostra o QR novo.
    final novo = await session.resetTotp();
    final restantes = await session.remainingRecoveryCodes();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _novoTotp = novo;
      _restantes = restantes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final novo = _novoTotp;
    return Scaffold(
      body: KeyringBackground(
        scrim: 0.5,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: novo == null ? _form() : _totpNovo(novo),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Perdi o autenticador',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Use a senha mestra e um dos códigos de recuperação que você guardou '
            'ao criar o cofre. Cada código funciona uma única vez.',
            style: TextStyle(color: PromaPalette.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha mestra'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Código de recuperação',
              hintText: 'XXXXX-XXXXX-XXXXX-XXXXX',
              errorText: _error,
            ),
            onSubmitted: (_) => _entrar(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _entrar,
            child: const Text('Entrar e reconfigurar'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Voltar'),
          ),
        ],
      );

  Widget _totpNovo(SetupResult r) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Configure o novo TOTP',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'O segredo antigo foi descartado. Escaneie o QR abaixo no seu app '
            'autenticador — o anterior não gera mais códigos válidos.',
            style: TextStyle(color: PromaPalette.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 216,
              height: 216,
              padding: const EdgeInsets.all(8),
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: QrImageView(
                data: r.keyUri,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PromaPalette.elevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PromaPalette.border),
            ),
            child: Row(children: [
              const Text('Chave: ', style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: SelectableText(r.totpSecret,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
              IconButton(
                tooltip: 'Copiar chave',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: r.totpSecret)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            _restantes > 0
                ? 'Restam $_restantes códigos de recuperação.'
                : 'Você usou o último código de recuperação. Crie um backup do cofre.',
            style: TextStyle(
              fontSize: 12,
              color: _restantes > 0 ? PromaPalette.dim : PromaPalette.accent,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            // O cofre já está aberto: fechar a tela cai direto no cofre.
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Concluir'),
          ),
        ],
      );
}
