import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/totp_service.dart';

void main() {
  final svc = TotpService();

  test('valida token gerado do mesmo segredo', () {
    final secret = svc.generateSecret();
    expect(svc.verify(svc.currentCode(secret), secret), isTrue);
  });

  test('rejeita token invalido', () {
    final secret = svc.generateSecret();
    expect(svc.verify('000000', secret), isFalse);
  });

  test('monta keyUri otpauth', () {
    final uri = svc.keyUri('ABC', label: 'cofre', issuer: 'Keyring');
    expect(uri, contains('otpauth://totp/'));
    expect(uri, contains('Keyring'));
  });
}
