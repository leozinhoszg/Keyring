import 'dart:math';

const _lower = 'abcdefghijklmnopqrstuvwxyz';
const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _digits = '0123456789';
const _symbols = '!@#\$%^&*()-_=+[]{};:,.<>?';

String generatePassword({
  required int length,
  bool lower = true,
  bool upper = true,
  bool digits = true,
  bool symbols = false,
}) {
  final sets = <String>[];
  if (lower) sets.add(_lower);
  if (upper) sets.add(_upper);
  if (digits) sets.add(_digits);
  if (symbols) sets.add(_symbols);
  if (sets.isEmpty) throw ArgumentError('Selecione ao menos um conjunto');
  if (length < sets.length) throw ArgumentError('Comprimento menor que os conjuntos exigidos');

  final rng = Random.secure();
  final chars = <String>[];
  for (final s in sets) {
    chars.add(s[rng.nextInt(s.length)]);
  }
  final all = sets.join();
  while (chars.length < length) {
    chars.add(all[rng.nextInt(all.length)]);
  }
  for (var i = chars.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}
