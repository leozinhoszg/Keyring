import 'dart:async';
import 'dart:math';

/// Atraso progressivo entre tentativas de desbloqueio malsucedidas.
///
/// O Argon2 já torna cada tentativa cara, mas nada impede alguém com a máquina
/// destravada de emendar tentativas a noite inteira. O atraso cresce a cada
/// erro e zera no primeiro acerto, encarecendo a força bruta sem atrapalhar
/// quem só errou a senha uma vez.
///
/// Vive em memória, de propósito: persistir o contador daria a quem mexe no
/// arquivo o poder de trancar o dono para fora.
class UnlockThrottle {
  final Duration base;
  final Duration max;
  final Future<void> Function(Duration) _sleep;

  /// [sleep] existe para os testes não gastarem segundos de verdade.
  UnlockThrottle({
    this.base = const Duration(milliseconds: 500),
    this.max = const Duration(seconds: 30),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future.delayed;

  int _failures = 0;
  int get failures => _failures;

  /// Atraso que a próxima tentativa vai pagar: dobra a cada erro, até o teto.
  /// As duas primeiras tentativas saem na hora — errar a senha uma vez é
  /// normal, e punir isso só irrita.
  Duration get nextDelay {
    if (_failures < 2) return Duration.zero;
    final ms = base.inMilliseconds * pow(2, _failures - 2).toInt();
    return Duration(milliseconds: min(ms, max.inMilliseconds));
  }

  Future<void> wait() async {
    final d = nextDelay;
    if (d > Duration.zero) await _sleep(d);
  }

  void registerFailure() => _failures++;
  void registerSuccess() => _failures = 0;
}
