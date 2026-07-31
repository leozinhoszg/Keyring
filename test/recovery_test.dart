import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/models/argon2_params.dart';
import 'package:keyring/services/crypto_service.dart';
import 'package:keyring/services/totp_service.dart';
import 'package:keyring/state/vault_repository.dart';
import 'package:keyring/state/vault_repository_io.dart';
import 'package:keyring/state/session_provider.dart';

import 'fakes/fake_quick_unlock.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<SessionProvider> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    return SessionProvider(SqliteVaultRepository(db), CryptoService(), TotpService(),
        const Argon2Params(), FakeQuickUnlockService());
  }

  /// Cofre pronto e trancado, como quem fechou o app depois de configurar.
  Future<(SessionProvider, SetupResult)> vaultPronto() async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    s.lock();
    return (s, res);
  }

  test('código de recuperação abre o cofre quando o TOTP se perdeu', () async {
    final (s, res) = await vaultPronto();
    final ok = await s.unlockWithRecoveryCode('senha-mestra', res.recoveryCodes.first);
    expect(ok, isTrue);
    expect(s.isUnlocked, isTrue, reason: 'é a saída de quem perdeu o Authy');
  });

  test('código de recuperação não dispensa a senha mestra', () async {
    final (s, res) = await vaultPronto();
    expect(await s.unlockWithRecoveryCode('senha-errada', res.recoveryCodes.first), isFalse);
    expect(s.isUnlocked, isFalse);
  });

  test('código inventado não abre', () async {
    final (s, _) = await vaultPronto();
    expect(await s.unlockWithRecoveryCode('senha-mestra', 'ABCDE-FGHIJ-KLMNO-PQRST'), isFalse);
    expect(s.isUnlocked, isFalse);
  });

  test('cada código serve uma vez só', () async {
    final (s, res) = await vaultPronto();
    final codigo = res.recoveryCodes.first;
    expect(await s.unlockWithRecoveryCode('senha-mestra', codigo), isTrue);
    s.lock();
    expect(await s.unlockWithRecoveryCode('senha-mestra', codigo), isFalse,
        reason: 'código consumido não pode reabrir o cofre');
    // os outros continuam valendo
    expect(await s.unlockWithRecoveryCode('senha-mestra', res.recoveryCodes[1]), isTrue);
  });

  test('após entrar pela recuperação dá para reconfigurar o TOTP', () async {
    final (s, res) = await vaultPronto();
    await s.unlockWithRecoveryCode('senha-mestra', res.recoveryCodes.first);

    final novo = await s.resetTotp();
    expect(novo.totpSecret, isNot(res.totpSecret));

    // o cofre reabre com o segredo novo, e o antigo não vale mais
    s.lock();
    expect(await s.unlock('senha-mestra', TotpService().currentCode(novo.totpSecret)), isTrue);
    s.lock();
    expect(await s.unlock('senha-mestra', TotpService().currentCode(res.totpSecret)), isFalse);
  });

  test('reconfigurar o TOTP exige o cofre aberto', () async {
    final (s, _) = await vaultPronto();
    expect(() => s.resetTotp(), throwsStateError);
  });

  test('os códigos têm entropia suficiente para resistir a força bruta', () async {
    final (_, res) = await vaultPronto();
    for (final c in res.recoveryCodes) {
      // 20 caracteres base32 = 100 bits; o formato antigo tinha 40.
      final semSeparador = c.replaceAll('-', '');
      expect(semSeparador.length, 20);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(semSeparador), isTrue);
    }
    expect(res.recoveryCodes.toSet().length, res.recoveryCodes.length);
  });
}
