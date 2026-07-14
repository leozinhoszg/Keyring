import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:keyring/models/argon2_params.dart';
import 'package:keyring/services/crypto_service.dart';
import 'package:keyring/services/totp_service.dart';
import 'package:keyring/state/vault_repository.dart';
import 'package:keyring/state/vault_repository_io.dart';
import 'package:keyring/state/session_provider.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<SessionProvider> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    return SessionProvider(SqliteVaultRepository(db), CryptoService(), TotpService(), const Argon2Params());
  }

  test('setup NAO persiste nem desbloqueia ate confirmar (evita troca de tela)', () async {
    final s = await fresh();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setup('senha-mestra');
    // setup apenas gera: sem notificar, sem desbloquear, sem marcar isSetup
    expect(notified, 0);
    expect(s.isUnlocked, isFalse);
    expect(s.isSetup, isFalse);
  });

  test('confirmSetup com codigo correto persiste e desbloqueia', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    expect(res.recoveryCodes.length, greaterThan(0));
    final ok = await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    expect(ok, isTrue);
    expect(s.isUnlocked, isTrue);
    expect(s.dek, isNotNull);
  });

  test('confirmSetup com codigo errado nao desbloqueia', () async {
    final s = await fresh();
    await s.setup('senha-mestra');
    expect(await s.confirmSetup('000000'), isFalse);
    expect(s.isUnlocked, isFalse);
  });

  test('unlock apos setup+confirm (reabrir o app)', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    s.lock();
    final ok = await s.unlock('senha-mestra', TotpService().currentCode(res.totpSecret));
    expect(ok, isTrue);
    expect(s.isUnlocked, isTrue);
  });

  test('unlock falha com senha errada', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    s.lock();
    expect(await s.unlock('errada', TotpService().currentCode(res.totpSecret)), isFalse);
  });

  test('lock apaga a DEK', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    s.lock();
    expect(s.isUnlocked, isFalse);
    expect(s.dek, isNull);
  });
}
