import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as legacy; // sha256 para hash dos recovery codes
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/argon2_params.dart';
import '../models/vault_settings.dart';
import '../services/crypto_service.dart';
import '../services/quick_unlock.dart';
import '../services/totp_service.dart';
import 'vault_repository.dart';

class SetupResult {
  final String totpSecret;
  final String keyUri;
  final List<String> recoveryCodes;
  const SetupResult({required this.totpSecret, required this.keyUri, required this.recoveryCodes});
}

/// Desfecho de uma tentativa de abrir o cofre pela biometria. A UI trata cada
/// um de um jeito — ver a tabela de mensagens na spec.
enum QuickUnlockOutcome {
  success,

  /// Usuário cancelou ou a biometria não foi reconhecida. Nada muda.
  cancelled,

  /// Acesso rápido não configurado, ou aparelho sem suporte.
  unavailable,

  /// Passaram-se mais de 7 dias do último login completo.
  expired,

  /// A metade do dispositivo não bate com a do banco. Acesso rápido desligado.
  invalidated,
}

class SessionProvider extends ChangeNotifier {
  final VaultRepository _repo;
  final CryptoService _crypto;
  final TotpService _totp;
  final Argon2Params _params;
  final QuickUnlockService _quick;

  SessionProvider(this._repo, this._crypto, this._totp, this._params, this._quick);

  bool _isSetup = false;
  Uint8List? _dek;
  Timer? _lockTimer;
  VaultSettings _settings = const VaultSettings();

  Uint8List? _quickWrapped;
  DateTime? _quickExpiresAt;
  bool _quickAvailable = false;

  /// Janela de acesso rápido, contada do último login completo.
  static const Duration quickUnlockWindow = Duration(days: 7);

  // Dados de setup gerados mas ainda não confirmados/persistidos
  Uint8List? _pendingDek;
  String? _pendingSecret;
  VaultMetaRow? _pendingMeta;

  bool get isSetup => _isSetup;
  bool get isUnlocked => _dek != null;
  Uint8List? get dek => _dek;
  VaultSettings get settings => _settings;
  CryptoService get crypto => _crypto;

  /// Há uma metade do acesso rápido gravada no cofre deste aparelho.
  bool get quickUnlockEnabled => _quickWrapped != null;

  /// A plataforma e o aparelho suportam acesso rápido.
  bool get quickUnlockAvailable => _quickAvailable;

  DateTime? get quickUnlockExpiresAt => _quickExpiresAt;

  /// Ativo, suportado e dentro da janela — só então a tela de desbloqueio
  /// oferece o caminho rápido.
  bool get quickUnlockUsable =>
      quickUnlockEnabled &&
      _quickAvailable &&
      _quickExpiresAt != null &&
      _quickExpiresAt!.isAfter(DateTime.now());

  /// Exposto para os testes envelhecerem a janela direto no banco, evitando
  /// injeção de relógio no código de produção.
  @visibleForTesting
  VaultRepository get debugRepository => _repo;

  Future<void> refreshStatus() async {
    _isSetup = await _repo.isSetup();
    _quickAvailable = await _quick.isAvailable();
    if (_isSetup) {
      final meta = await _repo.loadVaultMeta();
      _adoptQuickState(meta);
    }
    notifyListeners();
  }

  void _adoptQuickState(VaultMetaRow? meta) {
    _quickWrapped = meta?.wrappedDekQuick;
    final iso = meta?.quickExpiresAt;
    _quickExpiresAt = iso == null ? null : DateTime.tryParse(iso);
  }

  /// Gera as chaves e o segredo TOTP, mas NÃO persiste nem notifica — assim a
  /// tela de setup pode exibir o QR sem que o roteador troque de tela. A
  /// persistência acontece em [confirmSetup], após o usuário validar o código.
  Future<SetupResult> setup(String masterPassword) async {
    final salt = _crypto.randomSalt();
    final kek = await _crypto.deriveKek(masterPassword, salt, _params);
    final dek = _crypto.generateDek();
    final wrapped = await _crypto.wrapDek(dek, kek);

    final secret = _totp.generateSecret();
    final keyUri = _totp.keyUri(secret, label: 'cofre', issuer: 'Keyring');
    final totpEnc = await _crypto.encrypt(secret, dek);

    final codes = List<String>.generate(8, (_) => const Uuid().v4().replaceAll('-', '').substring(0, 10));
    final codesHash = jsonEncode(
        codes.map((c) => legacy.sha256.convert(utf8.encode(c)).toString()).toList());

    _pendingDek = dek;
    _pendingSecret = secret;
    _pendingMeta = VaultMetaRow(
      argon2Salt: salt,
      argon2Params: jsonEncode(_params.toJson()),
      wrappedDek: wrapped,
      totpSecretEnc: totpEnc,
      recoveryCodesHash: codesHash,
      settings: jsonEncode(const VaultSettings().toJson()),
      createdAt: DateTime.now().toIso8601String(),
    );
    return SetupResult(totpSecret: secret, keyUri: keyUri, recoveryCodes: codes);
  }

  /// Valida o código TOTP do setup pendente; se correto, persiste o cofre e já
  /// deixa desbloqueado. Retorna false se não há setup pendente ou o código é inválido.
  Future<bool> confirmSetup(String code) async {
    final meta = _pendingMeta;
    final secret = _pendingSecret;
    final dek = _pendingDek;
    if (meta == null || secret == null || dek == null) return false;
    if (!_totp.verify(code, secret)) return false;
    await _repo.saveVaultMeta(meta);
    _dek = dek;
    _isSetup = true;
    _settings = const VaultSettings();
    _pendingDek = null;
    _pendingSecret = null;
    _pendingMeta = null;
    _startTimer();
    notifyListeners();
    return true;
  }

  Future<bool> unlock(String masterPassword, String totpToken) async {
    final meta = await _repo.loadVaultMeta();
    if (meta == null) return false;
    final params = Argon2Params.fromJson(jsonDecode(meta.argon2Params) as Map<String, dynamic>);
    final kek = await _crypto.deriveKek(masterPassword, meta.argon2Salt, params);
    Uint8List dek;
    try {
      dek = await _crypto.unwrapDek(meta.wrappedDek, kek);
    } catch (_) {
      return false; // senha errada (tag GCM)
    }
    final secret = await _crypto.decrypt(meta.totpSecretEnc, dek);
    if (!_totp.verify(totpToken, secret)) return false;
    _dek = dek;
    _settings = VaultSettings.fromJson(jsonDecode(meta.settings) as Map<String, dynamic>);

    // A janela dos 7 dias conta do último login completo — e só dele.
    if (meta.wrappedDekQuick != null) {
      final expires = DateTime.now().add(quickUnlockWindow);
      await _repo.updateQuickUnlock(meta.wrappedDekQuick, expires.toIso8601String());
      _quickWrapped = meta.wrappedDekQuick;
      _quickExpiresAt = expires;
    }

    _startTimer();
    notifyListeners();
    return true;
  }

  /// Ativa o acesso rápido. Exige o cofre aberto — é o único momento em que o
  /// DEK existe para ser envolvido.
  ///
  /// Retorna false quando o aparelho não suporta, o cofre está trancado, ou o
  /// usuário cancelou o prompt. Em nenhum desses casos algo é gravado.
  Future<bool> enableQuickUnlock() async {
    final dek = _dek;
    if (dek == null) return false;
    if (!await _quick.isAvailable()) return false;

    final quickKey = _crypto.generateQuickKey();
    final wrapped = await _crypto.wrapDek(dek, quickKey);

    // Keystore antes do banco: uma chave órfã no keystore é inofensiva e será
    // sobrescrita. Um blob órfão no banco faria a próxima abertura acusar
    // invalidação sem o usuário ter feito nada.
    final status = await _quick.saveKey(quickKey, reason: 'Ativar o acesso rápido do Keyring');
    quickKey.fillRange(0, quickKey.length, 0);
    if (status != QuickKeyStatus.ok) return false;

    final expires = DateTime.now().add(quickUnlockWindow);
    await _repo.updateQuickUnlock(wrapped, expires.toIso8601String());
    _quickWrapped = wrapped;
    _quickExpiresAt = expires;
    notifyListeners();
    return true;
  }

  Future<void> disableQuickUnlock() async {
    await _forgetQuickUnlock();
    notifyListeners();
  }

  /// Abre o cofre pela biometria do aparelho, sem senha mestra nem TOTP.
  Future<QuickUnlockOutcome> unlockWithBiometrics() async {
    final meta = await _repo.loadVaultMeta();
    final blob = meta?.wrappedDekQuick;
    final iso = meta?.quickExpiresAt;
    if (meta == null || blob == null || iso == null) return QuickUnlockOutcome.unavailable;

    final expires = DateTime.tryParse(iso);
    if (expires == null || !expires.isAfter(DateTime.now())) {
      // Vencido não é inválido: o blob continua bom e o login completo o renova.
      return QuickUnlockOutcome.expired;
    }

    final read = await _quick.readKey(reason: 'Desbloquear o cofre Keyring');
    switch (read.status) {
      case QuickKeyStatus.cancelled:
        return QuickUnlockOutcome.cancelled;
      case QuickKeyStatus.unavailable:
        return QuickUnlockOutcome.unavailable;
      case QuickKeyStatus.missing:
        await _forgetQuickUnlock();
        notifyListeners();
        return QuickUnlockOutcome.invalidated;
      case QuickKeyStatus.ok:
        break;
    }

    final quickKey = read.key!;
    Uint8List dek;
    try {
      dek = await _crypto.unwrapDek(blob, quickKey);
    } catch (_) {
      // As duas metades não combinam — banco de outro aparelho, ou blob corrompido.
      await _forgetQuickUnlock();
      notifyListeners();
      return QuickUnlockOutcome.invalidated;
    } finally {
      quickKey.fillRange(0, quickKey.length, 0);
    }

    _dek = dek;
    _settings = VaultSettings.fromJson(jsonDecode(meta.settings) as Map<String, dynamic>);
    _startTimer();
    notifyListeners();
    return QuickUnlockOutcome.success;
  }

  /// Apaga as duas metades. Não notifica — quem chama decide quando.
  Future<void> _forgetQuickUnlock() async {
    await _quick.clearKey();
    await _repo.updateQuickUnlock(null, null);
    _quickWrapped = null;
    _quickExpiresAt = null;
  }

  void _startTimer() {
    _lockTimer?.cancel();
    final mins = _settings.autoLockMinutes;
    if (mins > 0) _lockTimer = Timer(Duration(minutes: mins), lock);
  }

  void touch() {
    if (isUnlocked) _startTimer();
  }

  void lock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    if (_dek != null) {
      _dek!.fillRange(0, _dek!.length, 0);
      _dek = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }
}
