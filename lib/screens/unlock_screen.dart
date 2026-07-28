import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/session_provider.dart';
import '../widgets/keyring_background.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pw = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  /// Quando true, mostra o formulário de senha mestra + TOTP. Começa false se o
  /// acesso rápido estiver disponível.
  bool _showFullForm = false;

  /// O prompt do SO abre sozinho uma vez ao entrar na tela. Se o usuário
  /// cancelar, não reabrimos — vira um botão, para não virar um loop.
  bool _autoPromptDone = false;

  /// No Android o PIN do aparelho também abre; prometer só "digital" seria mentir.
  String get _quickLabel =>
      Platform.isWindows ? 'Entrar com Windows Hello' : 'Entrar com digital ou PIN';

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>();
    _showFullForm = !session.quickUnlockUsable;
    if (session.quickUnlockUsable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _quickUnlock());
    }
  }

  Future<void> _quickUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _autoPromptDone = true;
    });
    final session = context.read<SessionProvider>();
    final outcome = await session.unlockWithBiometrics();
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == QuickUnlockOutcome.success) return; // o roteador troca a tela

    final message = switch (outcome) {
      QuickUnlockOutcome.expired => 'Já se passaram 7 dias — confirme sua senha mestra.',
      QuickUnlockOutcome.invalidated =>
        'Acesso rápido foi desativado neste dispositivo. Entre com a senha mestra para reativá-lo.',
      QuickUnlockOutcome.unavailable => 'Acesso rápido indisponível neste dispositivo.',
      QuickUnlockOutcome.cancelled => null,
      QuickUnlockOutcome.success => null,
    };

    setState(() {
      // Cancelar mantém o botão à mão; os demais desfechos exigem o formulário.
      if (outcome != QuickUnlockOutcome.cancelled) _showFullForm = true;
    });
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    final ok = await context.read<SessionProvider>().unlock(_pw.text, _code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _pw.clear();
      _code.clear();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Senha mestra ou código TOTP inválidos')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final showQuickButton = session.quickUnlockUsable;

    return Scaffold(
      body: KeyringBackground(
        scrim: 0.5,
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', width: 72, height: 72),
                  const SizedBox(height: 16),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Desbloquear cofre',
                              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          if (showQuickButton) ...[
                            FilledButton.icon(
                              onPressed: _busy ? null : _quickUnlock,
                              icon: const Icon(Icons.fingerprint, size: 20),
                              label: Text(_autoPromptDone ? 'Tentar novamente' : _quickLabel),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (!_showFullForm)
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _showFullForm = true),
                              child: const Text('Usar senha mestra'),
                            ),
                          if (_showFullForm) ...[
                            TextField(
                              controller: _pw,
                              obscureText: true,
                              autofocus: !showQuickButton,
                              decoration: const InputDecoration(labelText: 'Senha mestra'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _code,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6)
                              ],
                              decoration:
                                  const InputDecoration(labelText: 'Código do Authy (6 dígitos)'),
                              onSubmitted: (_) => _unlock(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _busy ? null : _unlock,
                                child: const Text('Desbloquear')),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
