import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/password_generator.dart';
import 'package:keyring/services/strength.dart';

void main() {
  test('respeita comprimento', () {
    expect(generatePassword(length: 20).length, 20);
  });
  test('apenas digitos quando so digitos', () {
    final pw = generatePassword(length: 30, lower: false, upper: false, digits: true, symbols: false);
    expect(RegExp(r'^[0-9]+$').hasMatch(pw), isTrue);
  });
  test('lanca erro se nenhum conjunto', () {
    expect(() => generatePassword(length: 10, lower: false, upper: false, digits: false, symbols: false),
        throwsArgumentError);
  });
  test('inclui um de cada conjunto habilitado', () {
    final pw = generatePassword(length: 12, lower: true, upper: true, digits: true, symbols: true);
    expect(RegExp(r'[a-z]').hasMatch(pw), isTrue);
    expect(RegExp(r'[A-Z]').hasMatch(pw), isTrue);
    expect(RegExp(r'[0-9]').hasMatch(pw), isTrue);
    expect(RegExp(r'[^a-zA-Z0-9]').hasMatch(pw), isTrue);
  });
  test('forca cresce com complexidade', () {
    expect(evaluateStrength('123'), lessThanOrEqualTo(1));
    expect(evaluateStrength('9x!Kd82@qLmz#0Pv'), greaterThanOrEqualTo(3));
  });
}
