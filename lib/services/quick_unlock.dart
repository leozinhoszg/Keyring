import 'dart:typed_data';

/// Desfecho de uma operação com a chave de acesso rápido.
///
/// A distinção entre [cancelled] e [missing] é o que impede uma digital mal lida
/// de custar a reconfiguração do acesso rápido — só [missing] invalida.
enum QuickKeyStatus {
  /// Autenticou e a chave está disponível.
  ok,

  /// O usuário cancelou o prompt, ou a autenticação falhou. Nada muda.
  cancelled,

  /// A plataforma não suporta, ou o aparelho não tem tela de bloqueio.
  unavailable,

  /// A chave não existe mais: app reinstalado, keystore resetado, `vault.db`
  /// de outro aparelho, ou — no Android — o SO destruiu a chave porque uma
  /// digital nova foi cadastrada. Invalida o acesso rápido.
  missing,
}

class QuickKeyResult {
  final QuickKeyStatus status;

  /// Só preenchido quando [status] é [QuickKeyStatus.ok]. Quem consome deve
  /// zerar estes bytes assim que terminar de usá-los.
  final Uint8List? key;

  const QuickKeyResult(this.status, [this.key]);
}

/// Guarda a chave de acesso rápido no cofre de credenciais do sistema.
///
/// Única fronteira do app com `local_auth` e `flutter_secure_storage` — nenhum
/// outro arquivo importa esses pacotes, e é isto que os testes falsificam.
///
/// O prompt de autenticação não é um método separado de propósito: no Android
/// o Keystore o exige ao usar a chave, enquanto no Windows o app precisa
/// chamar o Hello antes de tocar no DPAPI. Cada implementação resolve isso por
/// dentro; quem chama só pede a chave e recebe um desfecho.
abstract class QuickUnlockService {
  /// O aparelho pode proteger a chave? Falso quando não há biometria nem
  /// PIN/padrão configurados, ou a plataforma não é suportada.
  Future<bool> isAvailable();

  /// Grava a chave. Dispara o prompt do SO — é também a confirmação de que a
  /// biometria funciona antes de passarmos a confiar nela.
  Future<QuickKeyStatus> saveKey(Uint8List quickKey, {required String reason});

  /// Lê a chave, autenticando conforme a plataforma.
  Future<QuickKeyResult> readKey({required String reason});

  /// Apaga a chave. Não falha se ela já não existir.
  Future<void> clearKey();
}
