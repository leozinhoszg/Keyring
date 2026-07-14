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
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Senha mestra'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: const InputDecoration(labelText: 'Código do Authy (6 dígitos)'),
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: 16),
                          FilledButton(onPressed: _busy ? null : _unlock, child: const Text('Desbloquear')),
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
