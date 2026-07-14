import 'package:flutter/material.dart';
import '../services/password_generator.dart';
import 'strength_meter.dart';

Future<String?> showPasswordGenerator(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _GeneratorDialog());

class _GeneratorDialog extends StatefulWidget {
  const _GeneratorDialog();
  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  double _length = 20;
  bool _lower = true, _upper = true, _digits = true, _symbols = true;
  String _pw = '';

  void _gen() {
    if (!_lower && !_upper && !_digits && !_symbols) return;
    setState(() => _pw = generatePassword(
        length: _length.round(), lower: _lower, upper: _upper, digits: _digits, symbols: _symbols));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _gen());
  }

  Widget _sw(String label, bool v, ValueChanged<bool> on) => SwitchListTile(
        dense: true,
        title: Text(label),
        value: v,
        onChanged: (x) {
          on(x);
          _gen();
        },
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Gerador de senha'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: SelectableText(_pw, style: const TextStyle(fontFamily: 'monospace'))),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _gen),
            ]),
            StrengthMeter(password: _pw),
            Row(children: [
              Text('Tamanho: ${_length.round()}'),
              Expanded(
                child: Slider(
                  value: _length,
                  min: 8,
                  max: 64,
                  onChanged: (v) => setState(() => _length = v),
                  onChangeEnd: (_) => _gen(),
                ),
              ),
            ]),
            _sw('Minúsculas', _lower, (v) => _lower = v),
            _sw('Maiúsculas', _upper, (v) => _upper = v),
            _sw('Dígitos', _digits, (v) => _digits = v),
            _sw('Símbolos', _symbols, (v) => _symbols = v),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, _pw), child: const Text('Usar')),
        ],
      );
}
