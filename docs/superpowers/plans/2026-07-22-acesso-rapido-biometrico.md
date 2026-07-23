# Acesso rápido por biometria — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir abrir o cofre com a biometria do aparelho em vez de senha mestra + código TOTP, exigindo o login completo a cada 7 dias.

**Architecture:** Uma `quickKey` aleatória de 32 bytes envolve o DEK. A chave vai para o keystore do SO (no Android, presa ao hardware e liberada só por autenticação); o DEK envolvido por ela vai para uma coluna nova em `vault_meta`. Nenhuma metade serve sozinha. Todo acesso a `local_auth`/`flutter_secure_storage` fica atrás da interface `QuickUnlockService`, que os testes falsificam.

**Tech Stack:** Flutter/Dart, `flutter_secure_storage` ^10.3.1, `local_auth` ^3.0.2, sqflite, provider.

**Spec:** `docs/superpowers/specs/2026-07-22-acesso-rapido-biometrico-design.md`

## Global Constraints

- **minSdk 28** — fixo em `android/app/build.gradle.kts`, não herdado de `flutter.minSdkVersion`.
- **Android usa `AndroidOptions.biometric(enforceBiometrics: true)`** — chave presa ao hardware. Nunca `AndroidOptions()` simples para a `quickKey`.
- **`biometricOnly: false`** em toda chamada ao `local_auth` — o PIN do aparelho é fallback aceito (decisão registrada na spec).
- **Janela de 7 dias** conta do último login completo; usar a biometria **nunca** a estende.
- **Nenhuma exceção de plataforma chega à UI.** Toda falha vira um valor de `QuickKeyStatus` ou `QuickUnlockOutcome`.
- **Zerar material de chave** (`fillRange(0, len, 0)`) depois de usar, como `lock()` já faz com o DEK.
- **A UI nunca diz só "digital".** Rótulos: "Entrar com digital ou PIN" (Android), "Entrar com Windows Hello" (Windows).
- **Schema só cresce.** Migrações usam `ALTER TABLE`/`CREATE`; nunca `DROP`/`DELETE`.
- Comentários e mensagens de UI em **português**, seguindo o código existente.

---

## Task 1: minSdk 28

**Files:**
- Modify: `android/app/build.gradle.kts:27`

**Interfaces:**
- Consumes: nada.
- Produces: build Android em API 28+, pré-requisito de `AndroidOptions.biometric`.

- [ ] **Step 1: Fixar o minSdk**

Em `android/app/build.gradle.kts`, dentro de `defaultConfig`, trocar a linha `minSdk = flutter.minSdkVersion` por:

```kotlin
        // 28 (Android 9) é o piso do AndroidOptions.biometric do flutter_secure_storage:
        // setUnlockedDeviceRequired e StrongBox exigem API 28. Fixo, não herdado de
        // flutter.minSdkVersion (hoje 24), para o piso não cair numa atualização do Flutter.
        minSdk = 28
```

- [ ] **Step 2: Confirmar que o build ainda passa**

Run: `flutter build apk --release`
Expected: termina com `√ Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 3: Confirmar o minSdk dentro do APK**

Run:
```bash
AAPT=$(ls -d ~/AppData/Local/Android/Sdk/build-tools/*/aapt2.exe | sort -V | tail -1)
"$AAPT" dump badging build/app/outputs/flutter-apk/app-release.apk | grep sdkVersion
```
Expected: `sdkVersion:'28'`

- [ ] **Step 4: Commit**

```bash
git add android/app/build.gradle.kts
git commit -m "build: minSdk 28, exigido pela chave biometrica do Keystore"
```

---

## Task 2: Schema v2 — colunas do acesso rápido

**Files:**
- Modify: `lib/state/vault_repository.dart` (VaultMetaRow, createSchema, interface, nova função `migrateVault`)
- Modify: `lib/state/vault_repository_io.dart` (loadVaultMeta, updateQuickUnlock)
- Modify: `lib/services/database.dart` (versão e `_migrate`)
- Test: `test/vault_repository_test.dart`, `test/migration_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `VaultMetaRow.wrappedDekQuick` (`Uint8List?`) e `VaultMetaRow.quickExpiresAt` (`String?`)
  - `VaultRepository.updateQuickUnlock(Uint8List? wrapped, String? expiresAt) → Future<void>`
  - `migrateVault(Database db, int oldVersion, int newVersion) → Future<void>` (público, para o teste chamar a migração real)
  - `kVaultSchemaVersion == 2`

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao final de `test/vault_repository_test.dart` (dentro do `main()`):

```dart
  test('updateQuickUnlock grava e limpa apenas as colunas do acesso rapido', () async {
    final repo = await freshRepo();

    await repo.saveVaultMeta(VaultMetaRow(
      argon2Salt: Uint8List.fromList([1, 2]),
      argon2Params: '{}',
      wrappedDek: Uint8List.fromList([3, 4]),
      totpSecretEnc: Uint8List.fromList([5, 6]),
      recoveryCodesHash: '[]',
      settings: '{}',
      createdAt: 'agora',
    ));

    // recem-criado: acesso rapido desligado
    var meta = await repo.loadVaultMeta();
    expect(meta!.wrappedDekQuick, isNull);
    expect(meta.quickExpiresAt, isNull);

    // grava
    await repo.updateQuickUnlock(Uint8List.fromList([9, 9, 9]), '2026-08-01T00:00:00.000');
    meta = await repo.loadVaultMeta();
    expect(meta!.wrappedDekQuick, Uint8List.fromList([9, 9, 9]));
    expect(meta.quickExpiresAt, '2026-08-01T00:00:00.000');
    expect(meta.wrappedDek, Uint8List.fromList([3, 4]),
        reason: 'a meta original nao pode ser tocada');

    // limpa
    await repo.updateQuickUnlock(null, null);
    meta = await repo.loadVaultMeta();
    expect(meta!.wrappedDekQuick, isNull);
    expect(meta.quickExpiresAt, isNull);
    expect(meta.totpSecretEnc, Uint8List.fromList([5, 6]),
        reason: 'limpar o acesso rapido nao pode afetar o resto');
  });
```

O arquivo já tem os imports necessários e o helper `freshRepo()` — nada a adicionar no topo.

Substituir **todo** o corpo do `test(...)` existente em `test/migration_test.dart` pela migração real:

```dart
  test('migração v1→v2 preserva os dados e adiciona as colunas do acesso rápido', () async {
    final dir = await Directory.systemTemp.createTemp('keyring_mig');
    final dbPath = p.join(dir.path, 'vault.db');

    // v1: schema antigo, sem as colunas do acesso rápido, com uma credencial
    final db1 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE vault_meta (
          id INTEGER PRIMARY KEY CHECK (id = 1), argon2_salt BLOB NOT NULL,
          argon2_params TEXT NOT NULL, wrapped_dek BLOB NOT NULL,
          totp_secret_enc BLOB NOT NULL, recovery_codes_hash TEXT NOT NULL,
          settings TEXT NOT NULL, created_at TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE credentials (
          id TEXT PRIMARY KEY, title_enc BLOB NOT NULL, username_enc BLOB, password_enc BLOB,
          url_enc BLOB, notes_enc BLOB, project_enc BLOB,
          is_favorite INTEGER NOT NULL DEFAULT 0, strength_score INTEGER, password_hmac TEXT,
          expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
      }),
    );
    await db1.insert('credentials', {
      'id': 'c1',
      'title_enc': Uint8List.fromList([1, 2, 3]),
      'is_favorite': 0,
      'created_at': 'now',
      'updated_at': 'now',
    });
    await db1.close();

    // v2: a migração REAL do app
    final db2 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => createSchema(db),
        onUpgrade: migrateVault,
      ),
    );

    final rows = await db2.query('credentials');
    expect(rows.length, 1, reason: 'a credencial deve sobreviver à migração');
    expect(rows.first['id'], 'c1');

    final cols = await db2.rawQuery('PRAGMA table_info(vault_meta)');
    final names = cols.map((c) => c['name'] as String).toSet();
    expect(names, contains('wrapped_dek_quick'));
    expect(names, contains('quick_expires_at'));

    await db2.close();
    await dir.delete(recursive: true);
  });
```

- [ ] **Step 2: Rodar os testes e ver falhar**

Run: `flutter test test/vault_repository_test.dart test/migration_test.dart`
Expected: FAIL — `The getter 'wrappedDekQuick' isn't defined`, `The method 'updateQuickUnlock' isn't defined`, `Undefined name 'migrateVault'`.

- [ ] **Step 3: Adicionar os campos a `VaultMetaRow`**

Em `lib/state/vault_repository.dart`, substituir a classe `VaultMetaRow` inteira por:

```dart
class VaultMetaRow {
  final Uint8List argon2Salt;
  final String argon2Params;
  final Uint8List wrappedDek;
  final Uint8List totpSecretEnc;
  final String recoveryCodesHash;
  final String settings;
  final String createdAt;

  /// DEK envolvido pela chave de acesso rápido guardada no keystore do SO.
  /// Nulo = acesso rápido desligado. Sozinho, é inútil: sem a metade que mora
  /// no keystore daquele aparelho, não abre nada.
  final Uint8List? wrappedDekQuick;

  /// Vencimento da janela de acesso rápido (ISO-8601). Renovado a cada login
  /// completo; nunca estendido por usar a biometria.
  final String? quickExpiresAt;

  const VaultMetaRow({
    required this.argon2Salt,
    required this.argon2Params,
    required this.wrappedDek,
    required this.totpSecretEnc,
    required this.recoveryCodesHash,
    required this.settings,
    required this.createdAt,
    this.wrappedDekQuick,
    this.quickExpiresAt,
  });
}
```

- [ ] **Step 4: Declarar `updateQuickUnlock` na interface**

Em `lib/state/vault_repository.dart`, dentro de `abstract class VaultRepository`, logo abaixo de `Future<VaultMetaRow?> loadVaultMeta();`:

```dart
  /// Escreve apenas as colunas do acesso rápido. Passar `(null, null)` desliga.
  /// Separado de [saveVaultMeta] de propósito: aquele reescreve a meta inteira.
  Future<void> updateQuickUnlock(Uint8List? wrapped, String? expiresAt);
```

- [ ] **Step 5: Criar as colunas no schema e escrever a migração**

Em `lib/state/vault_repository.dart`, dentro de `createSchema`, substituir o `CREATE TABLE ... vault_meta` por:

```dart
  await db.execute('''CREATE TABLE IF NOT EXISTS vault_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1), argon2_salt BLOB NOT NULL, argon2_params TEXT NOT NULL,
    wrapped_dek BLOB NOT NULL, totp_secret_enc BLOB NOT NULL, recovery_codes_hash TEXT NOT NULL,
    settings TEXT NOT NULL, created_at TEXT NOT NULL,
    wrapped_dek_quick BLOB, quick_expires_at TEXT)''');
```

E adicionar, ao final do mesmo arquivo:

```dart
/// Migrações incrementais entre versões de schema. Cada degrau preserva os dados:
/// apenas ADD/ALTER/CREATE, nunca DROP/DELETE.
///
/// Pública para que `test/migration_test.dart` exercite a migração real do app,
/// em vez de uma imitação que só testaria o sqflite.
Future<void> migrateVault(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE vault_meta ADD COLUMN wrapped_dek_quick BLOB');
    await db.execute('ALTER TABLE vault_meta ADD COLUMN quick_expires_at TEXT');
  }
}
```

- [ ] **Step 6: Ligar a migração e subir a versão**

Em `lib/services/database.dart`:

1. Trocar `const int kVaultSchemaVersion = 1;` por `const int kVaultSchemaVersion = 2;`
2. Trocar o import `show createSchema` por `show createSchema, migrateVault`
3. Trocar `onUpgrade: _migrate,` por `onUpgrade: migrateVault,`
4. Apagar a função `_migrate` inteira (do comentário `/// Migrações incrementais...` até a chave de fechamento) — ela foi para `vault_repository.dart`

- [ ] **Step 7: Implementar no repositório SQLite**

Em `lib/state/vault_repository_io.dart`, substituir `loadVaultMeta` por:

```dart
  @override
  Future<VaultMetaRow?> loadVaultMeta() async {
    final rows = await _db.query('vault_meta', where: 'id = 1');
    if (rows.isEmpty) return null;
    final m = rows.first;
    return VaultMetaRow(
      argon2Salt: m['argon2_salt'] as dynamic, argon2Params: m['argon2_params'] as String,
      wrappedDek: m['wrapped_dek'] as dynamic, totpSecretEnc: m['totp_secret_enc'] as dynamic,
      recoveryCodesHash: m['recovery_codes_hash'] as String, settings: m['settings'] as String,
      createdAt: m['created_at'] as String,
      wrappedDekQuick: m['wrapped_dek_quick'] as dynamic,
      quickExpiresAt: m['quick_expires_at'] as String?,
    );
  }

  @override
  Future<void> updateQuickUnlock(Uint8List? wrapped, String? expiresAt) async {
    await _db.update(
      'vault_meta',
      {'wrapped_dek_quick': wrapped, 'quick_expires_at': expiresAt},
      where: 'id = 1',
    );
  }
```

Adicionar `import 'dart:typed_data';` no topo do arquivo se ainda não existir.

- [ ] **Step 8: Rodar os testes e ver passar**

Run: `flutter test test/vault_repository_test.dart test/migration_test.dart`
Expected: PASS, todos.

- [ ] **Step 9: Rodar a suíte inteira**

Run: `flutter test`
Expected: PASS — nenhuma regressão.

- [ ] **Step 10: Commit**

```bash
git add lib/state/vault_repository.dart lib/state/vault_repository_io.dart lib/services/database.dart test/vault_repository_test.dart test/migration_test.dart
git commit -m "feat(schema): v2 com colunas do acesso rapido

wrapped_dek_quick e quick_expires_at em vault_meta, nullable, via ALTER TABLE.
migrateVault vira publica para o teste exercitar a migracao real do app."
```

---

## Task 3: `QuickUnlockService` — contrato, fake e implementação

**Files:**
- Create: `lib/services/quick_unlock.dart` (contrato)
- Create: `lib/services/quick_unlock_platform.dart` (implementação real)
- Create: `test/fakes/fake_quick_unlock.dart` (fake para os testes)
- Test: `test/fakes/fake_quick_unlock_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `enum QuickKeyStatus { ok, cancelled, unavailable, missing }`
  - `class QuickKeyResult { final QuickKeyStatus status; final Uint8List? key; }`
  - `abstract class QuickUnlockService` com `isAvailable()`, `saveKey(Uint8List, {required String reason})`, `readKey({required String reason})`, `clearKey()`
  - `class PlatformQuickUnlockService implements QuickUnlockService`
  - `class FakeQuickUnlockService implements QuickUnlockService` (em `test/`)

- [ ] **Step 1: Escrever o contrato**

Criar `lib/services/quick_unlock.dart`:

```dart
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
```

- [ ] **Step 2: Escrever o fake e seu teste**

Criar `test/fakes/fake_quick_unlock.dart`:

```dart
import 'dart:typed_data';
import 'package:keyring/services/quick_unlock.dart';

/// Fake em memória do keystore do SO, para os testes rodarem sem hardware.
///
/// Os campos públicos permitem encenar cada desfecho: `available`,
/// `nextSaveStatus` e `nextReadStatus`. Quando `nextReadStatus` é null, o
/// comportamento é o real — devolve a chave guardada, ou `missing` se não há.
class FakeQuickUnlockService implements QuickUnlockService {
  Uint8List? stored;
  bool available = true;
  QuickKeyStatus? nextSaveStatus;
  QuickKeyStatus? nextReadStatus;

  int clearCalls = 0;
  int readCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<QuickKeyStatus> saveKey(Uint8List quickKey, {required String reason}) async {
    final forced = nextSaveStatus;
    if (forced != null && forced != QuickKeyStatus.ok) return forced;
    // copia: o chamador zera o buffer original depois de gravar
    stored = Uint8List.fromList(quickKey);
    return QuickKeyStatus.ok;
  }

  @override
  Future<QuickKeyResult> readKey({required String reason}) async {
    readCalls++;
    final forced = nextReadStatus;
    if (forced != null && forced != QuickKeyStatus.ok) return QuickKeyResult(forced);
    final s = stored;
    if (s == null) return const QuickKeyResult(QuickKeyStatus.missing);
    return QuickKeyResult(QuickKeyStatus.ok, Uint8List.fromList(s));
  }

  @override
  Future<void> clearKey() async {
    clearCalls++;
    stored = null;
  }
}
```

Criar `test/fakes/fake_quick_unlock_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyring/services/quick_unlock.dart';
import 'fake_quick_unlock.dart';

void main() {
  test('devolve a chave gravada', () async {
    final f = FakeQuickUnlockService();
    expect(await f.saveKey(Uint8List.fromList([1, 2, 3]), reason: 'x'), QuickKeyStatus.ok);
    final r = await f.readKey(reason: 'x');
    expect(r.status, QuickKeyStatus.ok);
    expect(r.key, Uint8List.fromList([1, 2, 3]));
  });

  test('sem chave gravada devolve missing', () async {
    final r = await FakeQuickUnlockService().readKey(reason: 'x');
    expect(r.status, QuickKeyStatus.missing);
    expect(r.key, isNull);
  });

  test('guarda uma copia: zerar o buffer do chamador nao apaga a chave', () async {
    final f = FakeQuickUnlockService();
    final k = Uint8List.fromList([7, 7, 7]);
    await f.saveKey(k, reason: 'x');
    k.fillRange(0, k.length, 0);
    expect((await f.readKey(reason: 'x')).key, Uint8List.fromList([7, 7, 7]));
  });

  test('clearKey apaga e conta as chamadas', () async {
    final f = FakeQuickUnlockService();
    await f.saveKey(Uint8List.fromList([1]), reason: 'x');
    await f.clearKey();
    expect(f.clearCalls, 1);
    expect((await f.readKey(reason: 'x')).status, QuickKeyStatus.missing);
  });
}
```

- [ ] **Step 3: Rodar e ver passar**

Run: `flutter test test/fakes/fake_quick_unlock_test.dart`
Expected: PASS, 4 testes.

- [ ] **Step 4: Escrever a implementação de plataforma**

Criar `lib/services/quick_unlock_platform.dart`:

```dart
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
```

- [ ] **Step 5: Verificar que compila**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/quick_unlock.dart lib/services/quick_unlock_platform.dart test/fakes/
git commit -m "feat: contrato e implementacao do QuickUnlockService

Android usa AndroidOptions.biometric (chave presa ao Keystore, autenticacao
por uso, destruida se uma digital nova for cadastrada). Windows usa DPAPI com
local_auth por cima. containsKey antes do read separa cancelamento de chave
destruida, para uma digital mal lida nao custar a reconfiguracao."
```

---

## Task 4: `SessionProvider` — ativar e desativar

**Files:**
- Modify: `lib/services/crypto_service.dart` (novo `generateQuickKey`)
- Modify: `lib/state/session_provider.dart`
- Modify: `lib/main.dart` (injeção)
- Test: `test/session_provider_test.dart`

**Interfaces:**
- Consumes: `QuickUnlockService`, `QuickKeyStatus` (Task 3); `VaultRepository.updateQuickUnlock`, `VaultMetaRow.wrappedDekQuick`, `VaultMetaRow.quickExpiresAt` (Task 2).
- Produces:
  - `SessionProvider(VaultRepository, CryptoService, TotpService, Argon2Params, QuickUnlockService)` — **quinto parâmetro posicional, obrigatório**
  - `bool get quickUnlockEnabled`, `bool get quickUnlockAvailable`, `DateTime? get quickUnlockExpiresAt`, `bool get quickUnlockUsable`
  - `Future<bool> enableQuickUnlock()`, `Future<void> disableQuickUnlock()`
  - `CryptoService.generateQuickKey() → Uint8List`

- [ ] **Step 1: Escrever os testes que falham**

Em `test/session_provider_test.dart`, adicionar aos imports:

```dart
import 'package:keyring/services/quick_unlock.dart';
import 'fakes/fake_quick_unlock.dart';
```

Substituir o helper `fresh()` por uma versão que devolve o provider **e** o fake:

```dart
  late FakeQuickUnlockService quick;

  Future<SessionProvider> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await createSchema(db);
    quick = FakeQuickUnlockService();
    return SessionProvider(
        SqliteVaultRepository(db), CryptoService(), TotpService(), const Argon2Params(), quick);
  }
```

Adicionar os testes ao final do `main()`:

```dart
  test('ativar acesso rapido grava as duas metades', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));

    expect(s.quickUnlockEnabled, isFalse);
    expect(await s.enableQuickUnlock(), isTrue);
    expect(s.quickUnlockEnabled, isTrue);
    expect(quick.stored, isNotNull, reason: 'a chave deve ir para o keystore');
    expect(s.quickUnlockExpiresAt, isNotNull);
    expect(s.quickUnlockExpiresAt!.isAfter(DateTime.now().add(const Duration(days: 6))), isTrue);
  });

  test('ativar com prompt cancelado nao grava nada no banco', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));

    quick.nextSaveStatus = QuickKeyStatus.cancelled;
    expect(await s.enableQuickUnlock(), isFalse);
    expect(s.quickUnlockEnabled, isFalse, reason: 'keystore antes do banco: nada gravado');
    expect(quick.stored, isNull);
  });

  test('ativar em aparelho sem tela de bloqueio e recusado', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));

    quick.available = false;
    expect(await s.enableQuickUnlock(), isFalse);
    expect(s.quickUnlockEnabled, isFalse);
    expect(quick.stored, isNull);
  });

  test('ativar exige o cofre aberto', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    s.lock();
    expect(await s.enableQuickUnlock(), isFalse);
  });

  test('desativar limpa as duas metades', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    await s.enableQuickUnlock();

    await s.disableQuickUnlock();
    expect(s.quickUnlockEnabled, isFalse);
    expect(s.quickUnlockExpiresAt, isNull);
    expect(quick.stored, isNull);
    expect(quick.clearCalls, 1);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/session_provider_test.dart`
Expected: FAIL — `too many positional arguments`, `The getter 'quickUnlockEnabled' isn't defined`.

- [ ] **Step 3: Adicionar `generateQuickKey` ao `CryptoService`**

Em `lib/services/crypto_service.dart`, logo abaixo de `Uint8List generateDek() => _randomBytes(32);`:

```dart
  /// Chave que envolve o DEK para o acesso rápido. Mesmo tamanho e mesma fonte
  /// do DEK; nomeada à parte porque o ciclo de vida é outro — esta vive no
  /// keystore do SO e é revogada sem tocar no cofre.
  Uint8List generateQuickKey() => _randomBytes(32);
```

- [ ] **Step 4: Implementar no `SessionProvider`**

Em `lib/state/session_provider.dart`:

1. Adicionar aos imports: `import '../services/quick_unlock.dart';`

2. Trocar os campos e o construtor:

```dart
  final VaultRepository _repo;
  final CryptoService _crypto;
  final TotpService _totp;
  final Argon2Params _params;
  final QuickUnlockService _quick;

  SessionProvider(this._repo, this._crypto, this._totp, this._params, this._quick);
```

3. Adicionar aos campos de estado, junto de `VaultSettings _settings`:

```dart
  Uint8List? _quickWrapped;
  DateTime? _quickExpiresAt;
  bool _quickAvailable = false;

  /// Janela de acesso rápido, contada do último login completo.
  static const Duration quickUnlockWindow = Duration(days: 7);
```

4. Adicionar os getters, junto dos existentes:

```dart
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
```

5. Substituir `refreshStatus` por:

```dart
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
```

6. Adicionar os métodos, antes de `_startTimer`:

```dart
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

  /// Apaga as duas metades. Não notifica — quem chama decide quando.
  Future<void> _forgetQuickUnlock() async {
    await _quick.clearKey();
    await _repo.updateQuickUnlock(null, null);
    _quickWrapped = null;
    _quickExpiresAt = null;
  }
```

- [ ] **Step 5: Atualizar a injeção no `main.dart`**

Em `lib/main.dart`:

1. Adicionar aos imports: `import 'services/quick_unlock_platform.dart';`
2. Trocar a linha do `SessionProvider` por:

```dart
  final session = SessionProvider(
      repo, crypto, TotpService(), const Argon2Params(), PlatformQuickUnlockService());
```

- [ ] **Step 6: Rodar e ver passar**

Run: `flutter test test/session_provider_test.dart`
Expected: PASS, todos — os 6 originais e os 5 novos.

- [ ] **Step 7: Commit**

```bash
git add lib/services/crypto_service.dart lib/state/session_provider.dart lib/main.dart test/session_provider_test.dart
git commit -m "feat(session): ativar e desativar o acesso rapido

Grava a chave no keystore antes do blob no banco: chave orfa e inofensiva,
blob orfao faria a proxima abertura acusar invalidacao sem motivo."
```

---

## Task 5: `SessionProvider` — desbloquear com biometria

**Files:**
- Modify: `lib/state/session_provider.dart`
- Test: `test/session_provider_test.dart`

**Interfaces:**
- Consumes: tudo da Task 4.
- Produces:
  - `enum QuickUnlockOutcome { success, cancelled, unavailable, expired, invalidated }` (em `lib/state/session_provider.dart`)
  - `Future<QuickUnlockOutcome> unlockWithBiometrics()`
  - `unlock()` passa a renovar `quick_expires_at` quando o acesso rápido está ativo

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao final do `main()` de `test/session_provider_test.dart`:

```dart
  test('desbloqueia com biometria e devolve o MESMO DEK', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    final dekAntes = Uint8List.fromList(s.dek!);
    await s.enableQuickUnlock();
    s.lock();

    expect(await s.unlockWithBiometrics(), QuickUnlockOutcome.success);
    expect(s.isUnlocked, isTrue);
    expect(s.dek, dekAntes, reason: 'o cofre so abre com o DEK original');
  });

  test('biometria cancelada nao abre nem desativa o acesso rapido', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    await s.enableQuickUnlock();
    s.lock();

    quick.nextReadStatus = QuickKeyStatus.cancelled;
    expect(await s.unlockWithBiometrics(), QuickUnlockOutcome.cancelled);
    expect(s.isUnlocked, isFalse);
    expect(s.dek, isNull);
    expect(s.quickUnlockEnabled, isTrue,
        reason: 'falha acidental nao pode custar a reconfiguracao');
  });

  test('chave sumida do keystore invalida e cai para o login completo', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    await s.enableQuickUnlock();
    s.lock();

    quick.stored = null; // app reinstalado, ou digital nova cadastrada no Android
    expect(await s.unlockWithBiometrics(), QuickUnlockOutcome.invalidated);
    expect(s.isUnlocked, isFalse);
    expect(s.quickUnlockEnabled, isFalse);
  });

  test('chave trocada (blob nao decifra) invalida', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    await s.enableQuickUnlock();
    s.lock();

    quick.stored = CryptoService().generateQuickKey(); // outra chave qualquer
    expect(await s.unlockWithBiometrics(), QuickUnlockOutcome.invalidated);
    expect(s.isUnlocked, isFalse);
    expect(s.quickUnlockEnabled, isFalse);
  });

  test('janela vencida exige login completo e preserva o blob', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    await s.enableQuickUnlock();

    // envelhece a janela direto no banco, sem injetar relogio na producao
    await s.debugRepository.updateQuickUnlock(
      (await s.debugRepository.loadVaultMeta())!.wrappedDekQuick,
      DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    );
    await s.refreshStatus();
    s.lock();

    expect(await s.unlockWithBiometrics(), QuickUnlockOutcome.expired);
    expect(s.isUnlocked, isFalse);
    expect(s.quickUnlockEnabled, isTrue, reason: 'o blob continua valido');
    expect(quick.readCalls, 0, reason: 'nem chega a pedir a digital');
  });

  test('login completo renova a janela de 7 dias', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    await s.enableQuickUnlock();

    await s.debugRepository.updateQuickUnlock(
      (await s.debugRepository.loadVaultMeta())!.wrappedDekQuick,
      DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    );
    await s.refreshStatus();
    s.lock();

    expect(await s.unlock('senha-mestra', TotpService().currentCode(res.totpSecret)), isTrue);
    expect(s.quickUnlockExpiresAt!.isAfter(DateTime.now().add(const Duration(days: 6))), isTrue);

    // e a renovação foi realmente persistida, não só refletida em memória
    final meta = await s.debugRepository.loadVaultMeta();
    expect(DateTime.parse(meta!.quickExpiresAt!).isAfter(DateTime.now().add(const Duration(days: 6))),
        isTrue);
  });

  test('sem acesso rapido configurado devolve unavailable', () async {
    final s = await fresh();
    final res = await s.setup('senha-mestra');
    await s.confirmSetup(TotpService().currentCode(res.totpSecret));
    s.lock();
    expect(await s.unlockWithBiometrics(), QuickUnlockOutcome.unavailable);
  });
```

Adicionar `import 'dart:typed_data';` ao topo do arquivo de teste, se ainda não houver.

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/session_provider_test.dart`
Expected: FAIL — `The method 'unlockWithBiometrics' isn't defined`, `Undefined name 'QuickUnlockOutcome'`, `The getter 'debugRepository' isn't defined`.

- [ ] **Step 3: Implementar**

Em `lib/state/session_provider.dart`:

1. Adicionar o enum no topo do arquivo, logo após os imports:

```dart
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
```

2. Adicionar o getter de teste, junto dos outros getters:

```dart
  /// Exposto para os testes envelhecerem a janela direto no banco, evitando
  /// injeção de relógio no código de produção.
  @visibleForTesting
  VaultRepository get debugRepository => _repo;
```

O import `package:flutter/foundation.dart` já existe no arquivo e traz `@visibleForTesting`.

3. Adicionar o método, logo após `enableQuickUnlock`:

```dart
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
```

4. No método `unlock`, logo antes de `_startTimer();`, inserir a renovação:

```dart
    // A janela dos 7 dias conta do último login completo — e só dele.
    if (meta.wrappedDekQuick != null) {
      final expires = DateTime.now().add(quickUnlockWindow);
      await _repo.updateQuickUnlock(meta.wrappedDekQuick, expires.toIso8601String());
      _quickWrapped = meta.wrappedDekQuick;
      _quickExpiresAt = expires;
    }
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/session_provider_test.dart`
Expected: PASS, todos.

- [ ] **Step 5: Rodar a suíte inteira**

Run: `flutter test`
Expected: PASS, sem regressões.

- [ ] **Step 6: Commit**

```bash
git add lib/state/session_provider.dart test/session_provider_test.dart
git commit -m "feat(session): desbloqueio por biometria e renovacao da janela

Cancelar nao invalida; chave ausente ou blob que nao decifra invalidam.
A janela de 7 dias conta do ultimo login completo e nunca e estendida por
usar a biometria."
```

---

## Task 6: `UnlockScreen` — modo rápido

**Files:**
- Modify: `lib/screens/unlock_screen.dart`

**Interfaces:**
- Consumes: `SessionProvider.quickUnlockUsable`, `unlockWithBiometrics()`, `QuickUnlockOutcome` (Task 5).
- Produces: nada consumido por tarefas seguintes.

- [ ] **Step 1: Reescrever a tela**

Substituir o conteúdo inteiro de `lib/screens/unlock_screen.dart` por:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../state/session_provider.dart';
import '../widgets/keyring_background.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pw = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  /// Quando true, mostra o formulário de senha mestra + TOTP. Começa false se o
  /// acesso rápido estiver disponível.
  bool _showFullForm = false;

  /// O prompt do SO abre sozinho uma vez ao entrar na tela. Se o usuário
  /// cancelar, não reabrimos — vira um botão, para não virar um loop.
  bool _autoPromptDone = false;

  /// No Android o PIN do aparelho também abre; prometer só "digital" seria mentir.
  String get _quickLabel =>
      Platform.isWindows ? 'Entrar com Windows Hello' : 'Entrar com digital ou PIN';

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionProvider>();
    _showFullForm = !session.quickUnlockUsable;
    if (session.quickUnlockUsable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _quickUnlock());
    }
  }

  Future<void> _quickUnlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _autoPromptDone = true;
    });
    final session = context.read<SessionProvider>();
    final outcome = await session.unlockWithBiometrics();
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == QuickUnlockOutcome.success) return; // o roteador troca a tela

    final message = switch (outcome) {
      QuickUnlockOutcome.expired => 'Já se passaram 7 dias — confirme sua senha mestra.',
      QuickUnlockOutcome.invalidated =>
        'Acesso rápido foi desativado neste dispositivo. Entre com a senha mestra para reativá-lo.',
      QuickUnlockOutcome.unavailable => 'Acesso rápido indisponível neste dispositivo.',
      QuickUnlockOutcome.cancelled => null,
      QuickUnlockOutcome.success => null,
    };

    setState(() {
      // Cancelar mantém o botão à mão; os demais desfechos exigem o formulário.
      if (outcome != QuickUnlockOutcome.cancelled) _showFullForm = true;
    });
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    final ok = await context.read<SessionProvider>().unlock(_pw.text, _code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _pw.clear();
      _code.clear();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Senha mestra ou código TOTP inválidos')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final showQuickButton = session.quickUnlockUsable;

    return Scaffold(
      body: KeyringBackground(
        scrim: 0.5,
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', width: 72, height: 72),
                  const SizedBox(height: 16),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Desbloquear cofre',
                              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          if (showQuickButton) ...[
                            FilledButton.icon(
                              onPressed: _busy ? null : _quickUnlock,
                              icon: const Icon(Icons.fingerprint, size: 20),
                              label: Text(_autoPromptDone ? 'Tentar novamente' : _quickLabel),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (!_showFullForm)
                            TextButton(
                              onPressed: _busy ? null : () => setState(() => _showFullForm = true),
                              child: const Text('Usar senha mestra'),
                            ),
                          if (_showFullForm) ...[
                            TextField(
                              controller: _pw,
                              obscureText: true,
                              autofocus: !showQuickButton,
                              decoration: const InputDecoration(labelText: 'Senha mestra'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _code,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6)
                              ],
                              decoration:
                                  const InputDecoration(labelText: 'Código do Authy (6 dígitos)'),
                              onSubmitted: (_) => _unlock(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: _busy ? null : _unlock,
                                child: const Text('Desbloquear')),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verificar que compila**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/screens/unlock_screen.dart
git commit -m "feat(ui): modo rapido na tela de desbloqueio

Prompt do SO dispara uma vez ao abrir; cancelar vira botao em vez de loop.
Rotulo por plataforma, sem prometer so digital quando o PIN tambem abre."
```

---

## Task 7: `SettingsScreen` — toggle do acesso rápido

**Files:**
- Modify: `lib/screens/settings_screen.dart`

**Interfaces:**
- Consumes: `SessionProvider.quickUnlockEnabled`, `quickUnlockAvailable`, `quickUnlockExpiresAt`, `enableQuickUnlock()`, `disableQuickUnlock()` (Task 4).
- Produces: nada.

- [ ] **Step 1: Adicionar o handler**

Em `lib/screens/settings_screen.dart`, adicionar `import 'dart:io';` ao topo e o método abaixo, logo após `_import()`:

```dart
  Future<void> _toggleQuickUnlock(bool enable) async {
    final session = context.read<SessionProvider>();
    if (!enable) {
      await session.disableQuickUnlock();
      if (mounted) _toast('Acesso rápido desativado.');
      return;
    }
    final ok = await session.enableQuickUnlock();
    if (!mounted) return;
    _toast(ok
        ? 'Acesso rápido ativado.'
        : 'Não foi possível ativar — a autenticação foi cancelada ou o aparelho não suporta.');
  }

  String _quickSubtitle(SessionProvider session) {
    if (!session.quickUnlockAvailable) {
      return 'Configure uma digital ou PIN no aparelho para usar o acesso rápido';
    }
    final expires = session.quickUnlockExpiresAt;
    if (session.quickUnlockEnabled && expires != null) {
      final d = expires.day.toString().padLeft(2, '0');
      final m = expires.month.toString().padLeft(2, '0');
      return 'Ativo. Senha mestra será pedida em $d/$m';
    }
    return Platform.isWindows
        ? 'Use o Windows Hello para abrir o cofre sem a senha mestra'
        : 'Use sua digital ou o PIN do aparelho para abrir o cofre sem a senha mestra';
  }
```

- [ ] **Step 2: Adicionar o toggle ao card "Segurança"**

No `build`, trocar `final settings = context.read<SessionProvider>().settings;` por:

```dart
    final session = context.watch<SessionProvider>();
    final settings = session.settings;
```

E, dentro do `Card` cujo título é `'Segurança'`, adicionar após a linha do clipboard:

```dart
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Acesso rápido'),
              subtitle: Text(_quickSubtitle(session)),
              value: session.quickUnlockEnabled,
              onChanged: session.quickUnlockAvailable ? _toggleQuickUnlock : null,
            ),
```

- [ ] **Step 3: Verificar que compila**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Rodar a suíte**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(ui): toggle do acesso rapido nas configuracoes"
```

---

## Task 8: Verificação em aparelho e notas de versão

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: tudo.
- Produces: versão 1.1.0.

- [ ] **Step 1: Build e teste manual no Android**

Run: `flutter build apk --release`

Instalar no aparelho e verificar, nesta ordem:

1. Abrir o cofre com senha mestra + TOTP.
2. Configurações → ligar "Acesso rápido" → o prompt de digital aparece → confirmar.
3. O subtítulo passa a mostrar a data de vencimento.
4. Fechar o app completamente e reabrir → o prompt de digital abre sozinho → o cofre abre sem digitar nada.
5. Reabrir e **cancelar** o prompt → o botão "Tentar novamente" fica disponível, e o acesso rápido **continua ativo** nas configurações.
6. Esperar o auto-lock de 5 min → desbloquear com a digital.
7. Cadastrar uma digital nova nas configurações do Android → reabrir o Keyring → deve cair no formulário completo com a mensagem de acesso rápido desativado. **Este é o teste que prova o `setInvalidatedByBiometricEnrollment`** e não tem como ser coberto por teste automatizado.
8. Reativar o acesso rápido e confirmar que volta a funcionar.

- [ ] **Step 2: Atualizar o CHANGELOG**

Em `CHANGELOG.md`, substituir a linha `## [Não lançado]` por:

```markdown
## [Não lançado]

## [1.1.0] — 2026-07-22

### Adicionado

- **Acesso rápido por biometria.** Abrir o cofre passa a exigir só a digital
  (ou o Windows Hello, no desktop), em vez de senha mestra + código do Authy. A
  senha mestra continua sendo pedida a cada 7 dias, e o código do Authy só junto
  dela. O auto-lock de 5 minutos, que antes custava os dois fatores, agora custa
  um toque.

  A chave que abre o cofre fica dividida: metade no cofre de credenciais do
  sistema, metade no `vault.db`. Nenhuma serve sozinha — copiar o `vault.db`
  para outro aparelho não leva o acesso rápido junto.

  No Android a chave é gerada **dentro do Keystore**, presa ao hardware: nunca
  sai do chip, exige autenticação a cada uso e é **destruída automaticamente se
  uma digital nova for cadastrada** no aparelho. No Windows a proteção é do
  Hello sobre o DPAPI, sem equivalente preso ao hardware.

  Ativar em Configurações → Segurança → Acesso rápido.

### Alterado

- **Android 9 (API 28) passa a ser o mínimo**, contra Android 7 antes. É o piso
  da chave biométrica presa ao hardware; abaixo disso o acesso rápido seria
  apenas uma conveniência sem proteção real.

### Segurança

- O PIN/padrão do aparelho é aceito como alternativa à digital, nas duas
  plataformas. Quem souber o PIN do seu celular ou do seu Windows abre o cofre
  sem a senha mestra — trade-off escolhido para não trancar você fora quando o
  sensor não lê o dedo.
```

E adicionar `[1.1.0]: https://github.com/leozinhoszg/Keyring/releases/tag/v1.1.0` junto dos outros links, ao final do arquivo.

- [ ] **Step 3: Subir a versão**

Em `pubspec.yaml`, trocar `version: 1.0.2+3` por `version: 1.1.0+4`.

- [ ] **Step 4: Rodar tudo uma última vez**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` e todos os testes passando.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md pubspec.yaml
git commit -m "release: 1.1.0 com acesso rapido por biometria"
```

---

## Fora de escopo, registrado

**Recovery codes não recuperam nada.** Os 8 códigos do setup têm o SHA-256 gravado em
`recovery_codes_hash`, mas nenhum código lê essa coluna, e o DEK não está envolvido por
nenhuma chave derivada deles — esquecer a senha mestra continua significando perder o cofre.
O acesso rápido não cria o problema, mas reduz a repetição que mantinha a senha mestra na
memória. Merece plano próprio; a spec detalha em *Risco pré-existente*.
