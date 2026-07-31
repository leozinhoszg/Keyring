import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/unlock_throttle.dart';

void main() {
  test('as duas primeiras tentativas não esperam', () {
    final t = UnlockThrottle();
    expect(t.nextDelay, Duration.zero);
    t.registerFailure();
    expect(t.nextDelay, Duration.zero, reason: 'errar uma vez é normal');
  });

  test('o atraso dobra a cada erro seguinte', () {
    final t = UnlockThrottle(base: const Duration(milliseconds: 500));
    for (var i = 0; i < 2; i++) {
      t.registerFailure();
    }
    expect(t.nextDelay, const Duration(milliseconds: 500));
    t.registerFailure();
    expect(t.nextDelay, const Duration(seconds: 1));
    t.registerFailure();
    expect(t.nextDelay, const Duration(seconds: 2));
  });

  test('o atraso tem teto', () {
    final t = UnlockThrottle(
      base: const Duration(milliseconds: 500),
      max: const Duration(seconds: 5),
    );
    for (var i = 0; i < 30; i++) {
      t.registerFailure();
    }
    expect(t.nextDelay, const Duration(seconds: 5));
  });

  test('acertar zera a punição', () {
    final t = UnlockThrottle();
    for (var i = 0; i < 5; i++) {
      t.registerFailure();
    }
    t.registerSuccess();
    expect(t.nextDelay, Duration.zero);
  });

  test('wait realmente espera o atraso calculado', () async {
    final dormidas = <Duration>[];
    final t = UnlockThrottle(
      base: const Duration(milliseconds: 500),
      sleep: (d) async => dormidas.add(d),
    );
    await t.wait();
    expect(dormidas, isEmpty, reason: 'sem falhas, sem espera');

    t.registerFailure();
    t.registerFailure();
    await t.wait();
    expect(dormidas, [const Duration(milliseconds: 500)]);
  });
}
