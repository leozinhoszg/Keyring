import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/strength.dart';
import '../state/session_provider.dart';
import '../theme/proma_palette.dart';
import '../widgets/keyring_background.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  SetupResult? _result;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    if (_pw.text.length < 8) return _toast('A senha mestra precisa de 8+ caracteres');
    if (_pw.text != _confirm.text) return _toast('As senhas não coincidem');
    setState(() => _busy = true);
    final res = await context.read<SessionProvider>().setup(_pw.text);
    // reabilita a UI ao avançar para a etapa do TOTP; sem isto o botão
    // "Confirmar e entrar" fica desabilitado (só o Enter funcionava).
    if (mounted) {
      setState(() {
        _result = res;
        _busy = false;
      });
    }
  }

  Future<void> _confirmAndEnter() async {
    if (_code.text.length != 6) return setState(() => _error = 'Digite o código de 6 dígitos do Authy');
    setState(() {
      _busy = true;
      _error = null;
    });
    // valida o TOTP do setup pendente, persiste o cofre e já desbloqueia
    final ok = await context.read<SessionProvider>().confirmSetup(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) setState(() => _error = 'Código inválido. Confira se adicionou a conta no Authy e tente o código atual.');
    // se ok, o _Root reconstrói e mostra o cofre desbloqueado
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      body: KeyringBackground(
        scrim: 0.5,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', width: 78, height: 78),
                  const SizedBox(height: 18),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: r == null ? _form() : _totpStep(r),
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

  Widget _form() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Crie seu cofre', style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'A senha mestra nunca é armazenada e não há recuperação — só o backup criptografado protege seus dados.',
            style: TextStyle(color: PromaPalette.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Senha mestra'),
            onChanged: (_) => setState(() {}),
          ),
          if (_pw.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Força: ${strengthLabel(evaluateStrength(_pw.text))}',
                  style: const TextStyle(fontSize: 12, color: PromaPalette.dim)),
            ),
          const SizedBox(height: 12),
          TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirme a senha')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _create, child: const Text('Criar cofre')),
        ],
      );

  Widget _totpStep(SetupResult r) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Configure o TOTP no Authy', style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Escaneie o QR com o Authy — ou adicione manualmente com a chave abaixo (Authy → "+" → "Inserir chave manualmente").',
            style: TextStyle(color: PromaPalette.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // QR com fundo branco e cores explícitas (contraste garantido sobre o tema dark)
          Center(
            child: Container(
              width: 216,
              height: 216,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: QrImageView(
                data: r.keyUri,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle:
                    const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Segredo copiável (entrada manual à prova de falhas caso o QR não escaneie)
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
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.totpSecret));
                  _toast('Chave copiada');
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Text('Códigos de recuperação (guarde em local seguro):',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Se você perder o autenticador, cada um destes códigos abre o cofre '
            'uma vez, junto com a senha mestra.',
            style: TextStyle(color: PromaPalette.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: r.recoveryCodes
                .map((c) => Chip(label: Text(c, style: const TextStyle(fontFamily: 'monospace'))))
                .toList(),
          ),
          const Divider(height: 28),
          const Text('Confirme digitando o código atual do Authy:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(labelText: 'Código de 6 dígitos', errorText: _error),
            onSubmitted: (_) => _confirmAndEnter(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _confirmAndEnter,
            child: const Text('Confirmar e entrar'),
          ),
        ],
      );
}
