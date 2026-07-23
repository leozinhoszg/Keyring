import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'quick_unlock.dart';

/// Implementação real sobre o cofre de credenciais do sistema.
///
/// **Android:** `AndroidOptions.biometric` faz o backend gerar a chave dentro do
/// Keystore com `setUserAuthenticationRequired(true)`, timeout 0 (autentica a
/// cada uso), `setInvalidatedByBiometricEnrollment(true)` (cadastrar uma digital
/// nova destrói a chave), `setUnlockedDeviceRequired(true)` e StrongBox quando o
/// aparelho tem. A chave nunca sai do TEE — root não basta para extraí-la.
///
/// **Windows:** o armazenamento é DPAPI, sem equivalente de chave presa ao
/// hardware, então o `local_auth` (Hello) é chamado antes de cada operação. A
/// ligação entre autenticação e chave é lógica, decidida aqui.
class PlatformQuickUnlockService implements QuickUnlockService {
  static const _keyName = 'keyring_quick_unlock_key';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  PlatformQuickUnlockService({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ??
            const FlutterSecureStorage(
              // enforceBiometrics: recusa gerar a chave em aparelho sem tela de
              // bloqueio, em vez de guardá-la desprotegida.
              aOptions: AndroidOptions.biometric(enforceBiometrics: true),
            ),
        _auth = auth ?? LocalAuthentication();

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isWindows;

  /// No Android o prompt vem do próprio Keystore ao usar a chave; chamar o
  /// `local_auth` aqui também renderia dois prompts em sequência.
  bool get _needsExplicitPrompt => Platform.isWindows;

  @override
  Future<bool> isAvailable() async {
    if (!_isSupportedPlatform) return false;
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<QuickKeyStatus> saveKey(Uint8List quickKey, {required String reason}) async {
    if (!await isAvailable()) return QuickKeyStatus.unavailable;
    if (_needsExplicitPrompt && !await _promptOk(reason)) return QuickKeyStatus.cancelled;
    try {
      await _storage.write(key: _keyName, value: base64Encode(quickKey));
      return QuickKeyStatus.ok;
    } on PlatformException {
      // No Android, gravar já exige autenticação: falha aqui é cancelamento ou
      // sensor recusado. Nada foi gravado, então nada a invalidar.
      return QuickKeyStatus.cancelled;
    }
  }

  @override
  Future<QuickKeyResult> readKey({required String reason}) async {
    if (!await isAvailable()) return const QuickKeyResult(QuickKeyStatus.unavailable);

    // Consultar a existência antes de ler é o que separa "cancelou" de "sumiu":
    // containsKey não decifra, então não dispara prompt nem falha por autenticação.
    try {
      if (!await _storage.containsKey(key: _keyName)) {
        return const QuickKeyResult(QuickKeyStatus.missing);
      }
    } on PlatformException {
      return const QuickKeyResult(QuickKeyStatus.missing);
    }

    if (_needsExplicitPrompt && !await _promptOk(reason)) {
      return const QuickKeyResult(QuickKeyStatus.cancelled);
    }

    try {
      final raw = await _storage.read(key: _keyName);
      if (raw == null) return const QuickKeyResult(QuickKeyStatus.missing);
      return QuickKeyResult(QuickKeyStatus.ok, Uint8List.fromList(base64Decode(raw)));
    } on PlatformException {
      // A entrada existia e a leitura falhou: autenticação recusada ou cancelada.
      // Se a chave tiver sido destruída pelo SO, o `resetOnError` do pacote limpa
      // o storage, e a próxima tentativa cai no containsKey acima como `missing`.
      return const QuickKeyResult(QuickKeyStatus.cancelled);
    } on FormatException {
      return const QuickKeyResult(QuickKeyStatus.missing);
    }
  }

  @override
  Future<void> clearKey() async {
    try {
      await _storage.delete(key: _keyName);
    } on PlatformException {
      // Já não existe, ou o keystore está inacessível. O acesso rápido é
      // revogado pelo banco de qualquer forma — não há o que salvar aqui.
    }
  }

  Future<bool> _promptOk(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // false: o PIN/padrão do aparelho é fallback aceito (decisão da spec).
        biometricOnly: false,
      );
    } on PlatformException {
      return false;
    }
  }
}
