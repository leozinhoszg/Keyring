# Acesso rápido por biometria

Data: 2026-07-22
Status: aprovado, pronto para planejamento

## Problema

Abrir o cofre exige senha mestra **e** código TOTP do Authy em toda abertura, inclusive
depois do auto-lock de 5 minutos de inatividade. Pegar o celular e copiar 6 dígitos várias
vezes por dia é o gargalo — a senha mestra, sozinha, não incomoda.

## Contexto de segurança

Hoje, em `SessionProvider.unlock`, o TOTP é verificado **depois** de a senha mestra derivar
a KEK (Argon2id) e desembrulhar o DEK. O segredo TOTP está cifrado com o próprio DEK, então
só é possível conferi-lo com o cofre já aberto. Consequências:

- O TOTP é uma checagem lógica no app, não uma barreira criptográfica.
- Quem tiver o `vault.db` e a senha mestra lê tudo sem o Authy.
- Portanto, remover o TOTP do caminho de acesso rápido **não** enfraquece a criptografia.

A proteção real do cofre é a senha mestra + Argon2id. É essa que o acesso rápido substitui,
e é por isso que a substituta precisa estar presa ao dispositivo.

## Decisões

| Questão | Decisão |
|---|---|
| Plataformas-alvo | Android (APK) e Windows desktop |
| Fator de acesso rápido | Biometria do SO — digital no Android, Windows Hello no Windows |
| Login completo obrigatório | A cada 7 dias, contados do último login completo |
| Auto-lock por inatividade | Continua em 5 minutos (agora custa um toque) |
| Onde mora a chave | Metade no keystore do SO, metade no `vault.db` |

## Arquitetura

Chave de acesso rápido **indireta**: uma `quickKey` aleatória de 32 bytes envolve o DEK, e
as duas metades ficam separadas.

```
quickKey (32 bytes) ──► keystore do SO   (Android Keystore / DPAPI no Windows)
wrapped_dek_quick   ──► tabela vault_meta (vault.db)

DEK = unwrapDek(wrapped_dek_quick, quickKey)
```

Nenhuma metade serve sozinha. O `vault.db` — que vai para backup, pendrive, sync — não
contém nada utilizável em outro aparelho. O keystore sem o banco também não. Revogar o
acesso rápido é um `UPDATE` de uma linha, e funciona mesmo se o keystore estiver
inacessível.

A alternativa avaliada e recusada foi guardar o DEK direto no keystore: economiza a
migração de schema, mas expõe o DEK cru ao storage do SO e perde a separação
banco/dispositivo.

### Escolha do backend e seu limite

Implementação em Dart puro com `local_auth` + `flutter_secure_storage`, sem código nativo.

O limite honesto: a ligação entre a biometria e a chave é **lógica**, decidida pelo app —
o app autentica e, se der certo, lê a chave. Um Android com root, ou malware rodando como o
mesmo usuário no Windows, conseguiria extrair a `quickKey`. É o mesmo modelo que Bitwarden
e 1Password usam no desktop.

A alternativa forte (chave gerada dentro do Keystore com `setUserAuthenticationRequired`,
liberada por `BiometricPrompt` com `CryptoObject`, nunca saindo do TEE/StrongBox) exigiria
plugin nativo em Kotlin e WinRT — semanas de trabalho e manutenção contínua, contra um
atacante que, tendo root no aparelho, também captura a digital no próximo desbloqueio.

**O formato de dados não fecha essa porta.** A `quickKey` continua sendo 32 bytes; migrar
para o backend nativo depois troca apenas quem os guarda, sem alterar o schema.

## Componentes

### `QuickUnlockService` (novo — `lib/services/quick_unlock.dart`)

Interface abstrata + implementação real, seguindo o padrão de
`lib/state/vault_repository_factory.dart`. É a única fronteira que os testes falsificam, e
o único lugar do app que conhece `local_auth` e `flutter_secure_storage`.

```
Future<bool> isAvailable()               // aparelho tem biometria/Hello utilizável
Future<bool> authenticate(String reason) // dispara o prompt do SO
Future<void> saveKey(Uint8List quickKey)
Future<Uint8List?> readKey()             // null quando a chave não existe
Future<void> clearKey()
```

### Schema v2 — `lib/services/database.dart`

Duas colunas nullable em `vault_meta`, adicionadas via `ALTER TABLE` no `_migrate` já
preparado. `kVaultSchemaVersion` passa de 1 para 2.

| coluna | tipo | conteúdo |
|---|---|---|
| `wrapped_dek_quick` | BLOB | DEK envolvido pela `quickKey`, via o `wrapDek` existente |
| `quick_expires_at` | TEXT | ISO-8601 — vencimento da janela de 7 dias |

Ambas nulas significa acesso rápido desligado. `VaultMetaRow` ganha os dois campos como
nullable; `createSchema` passa a criá-las já na v2 para bancos novos.

Método novo no repositório:

```
Future<void> updateQuickUnlock(Uint8List? wrapped, String? expiresAt)
```

Escreve só essas duas colunas, sem reescrever a meta inteira.

### `SessionProvider`

```
bool get quickUnlockEnabled          // há blob no banco
Future<bool> quickUnlockAvailable()  // plataforma suporta
DateTime? get quickUnlockExpiresAt

Future<bool> enableQuickUnlock()     // exige cofre aberto
Future<void> disableQuickUnlock()
Future<QuickUnlockOutcome> unlockWithBiometrics()
```

`enableQuickUnlock` retorna `false` quando o prompt de confirmação é cancelado ou a
plataforma não suporta — em ambos os casos nada é gravado e o toggle volta para desligado.

`QuickUnlockOutcome` distingue os desfechos que a UI trata de formas diferentes:
`success`, `cancelled`, `unavailable`, `expired`, `invalidated`.

## Fluxos

### Ativar (nas configurações, com o cofre aberto)

1. Confirma com um prompt de biometria — não faz sentido confiar numa digital não testada.
2. Gera `quickKey` com o `Random.secure()` já existente em `CryptoService`.
3. `wrapDek(dek, quickKey)`.
4. Grava a `quickKey` no keystore.
5. Grava blob e `agora + 7 dias` via `updateQuickUnlock`.
6. Zera a `quickKey` da memória.

A ordem dos passos 4 e 5 importa. Keystore primeiro: se a escrita no banco falhar, sobra uma
chave órfã no keystore — inofensiva, e sobrescrita na próxima tentativa. Na ordem inversa,
sobraria um blob no banco sem chave correspondente, e a próxima abertura cairia em
`invalidated` sem que o usuário tenha feito nada.

### Entrar com biometria

1. App abre; há blob e a data não venceu.
2. Prompt do SO dispara automaticamente, **uma vez**.
3. `readKey()` → `unwrapDek(blob, quickKey)`.
4. DEK em memória, cofre aberto, timer de auto-lock iniciado, `quickKey` zerada.

Sem senha, sem Authy.

### Login completo

Idêntico a hoje. Ao final, se o acesso rápido estiver ativo, **renova**
`quick_expires_at` para +7 dias.

A janela conta do último login completo e **nunca** é estendida por usar a digital — é isso
que implementa a regra dos 7 dias.

## Invalidação

A distinção mais fácil de errar: falha acidental não pode custar reconfiguração, e estado
ambíguo não pode virar acesso silencioso.

**Invalida** — zera as duas colunas e chama `clearKey()`:

- O usuário desativa nas configurações.
- `readKey()` volta vazio: app reinstalado, keystore resetado, ou `vault.db` trazido de
  outro aparelho.
- `unwrapDek` falha na tag GCM: chave trocada ou blob corrompido.

Os dois últimos são o mesmo caso — a metade do dispositivo não bate com a metade do banco.
Cai para o login completo com aviso claro, sem exceção propagando para a UI.

**Não invalida** — apenas volta ao formulário completo:

- Prompt cancelado pelo usuário.
- Biometria não reconhecida, ou lockout do SO por excesso de tentativas (o SO já limita;
  o app não reimplementa contador).
- Janela de 7 dias vencida — o blob continua criptograficamente válido e o login completo
  simplesmente renova a data.

### Limitações conhecidas

**Android:** cadastrar uma digital nova no aparelho **não** invalida a chave nesta
abordagem. Quem tiver o aparelho desbloqueado e adicionar a própria digital passa a abrir o
cofre. Só o backend nativo (`setInvalidatedByBiometricEnrollment`) resolve.

**Windows:** o Hello aceita o **PIN do Windows** como alternativa à digital, e o
`local_auth` não permite bloquear isso na plataforma. Na prática, acesso rápido no Windows
significa "digital ou o PIN daquela máquina". O PIN do Hello é preso ao TPM do aparelho —
não é uma senha copiável — mas é diferente do que a palavra "biometria" sugere. A UI usa o
rótulo "Windows Hello", não "digital", para não enganar.

**Fora de escopo:** troca de senha mestra não existe no app hoje. Quando existir, decidir se
invalida o acesso rápido — tecnicamente não precisa (o DEK não muda), mas quem troca a senha
mestra normalmente suspeita de comprometimento.

## Interface

### `UnlockScreen` — dois modos

**Modo rápido** (padrão quando disponível): mantém logo e título; no lugar dos dois campos,
um botão grande com ícone de digital — *"Entrar com digital"* no Android, *"Entrar com
Windows Hello"* no Windows — e abaixo um link discreto *"Usar senha mestra"* que revela o
formulário atual.

O prompt do SO dispara sozinho ao abrir a tela, uma vez. Cancelou, o botão fica disponível
para nova tentativa — sem reabrir em loop.

**Modo completo:** o formulário de hoje, inalterado. É o fallback de todos os desfechos que
não são `success`, cada um com sua mensagem:

| desfecho | mensagem |
|---|---|
| `expired` | "Já se passaram 7 dias — confirme sua senha mestra." |
| `invalidated` | "Acesso rápido foi desativado neste dispositivo. Entre com a senha mestra para reativá-lo." |
| `cancelled` | sem mensagem — o botão continua ali |

### `SettingsScreen`

Toggle "Acesso rápido", com subtítulo refletindo o estado real. O texto do estado desligado
muda por plataforma, pela mesma razão do rótulo da `UnlockScreen` — no Windows o fator pode
ser o PIN do Hello, e chamá-lo de digital seria enganoso:

- desligado, Android → "Use sua digital para abrir o cofre sem a senha mestra"
- desligado, Windows → "Use o Windows Hello para abrir o cofre sem a senha mestra"
- ligado → "Ativo. Senha mestra será pedida em 29/07" (data real de `quick_expires_at`)
- plataforma sem suporte → o item não aparece

## Testes

Com `FakeQuickUnlockService` em memória, sem tocar em hardware. Estende
`test/session_provider_test.dart` e `test/migration_test.dart`.

1. Ativar → travar → entrar com biometria devolve **o mesmo DEK**.
2. Biometria negada → `isUnlocked` continua falso e o DEK não vaza.
3. Chave ausente no keystore → colunas zeradas, desfecho `invalidated`, sem exceção.
4. Blob corrompido → mesmo tratamento.
5. Janela vencida (data gravada no passado direto no banco) → desfecho `expired`, exige
   login completo.
6. Login completo com acesso rápido ativo → renova para +7 dias.
7. Desativar → colunas nulas e `clearKey()` chamado.
8. Migração v1→v2 preserva credenciais existentes.

O teste 5 grava `quick_expires_at` diretamente no banco em vez de injetar um relógio — evita
adicionar injeção de tempo ao código de produção só para teste.

## Riscos de implementação

**minSdk.** `local_auth` e `flutter_secure_storage` exigem API 23. O projeto usa
`flutter.minSdkVersion` em `android/app/build.gradle.kts`, que pode estar em 21. Se estiver,
subir para 23 — isso afeta o build de APK no GitHub Actions, então é a **primeira** coisa a
validar no plano, não a última.

**`local_auth` no Windows.** O suporte vem do pacote federado `local_auth_windows`
(`UserConsentVerifier`). Confirmar que está incluído por padrão na versão escolhida de
`local_auth` e que a flag `biometricOnly` é ignorada na plataforma — o comportamento
esperado está descrito em Limitações conhecidas.

**`flutter_secure_storage` no Android.** Definir `AndroidOptions` com
`encryptedSharedPreferences: true` explicitamente, sem depender do padrão da versão.
